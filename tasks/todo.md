# Task: Food performance at 7,756-catalog scale (2026-06-10)

Symptom: jank searching + adding food after the catalog grew 258 → 7,756. Root causes found via 3 parallel audits.

## Done
- [x] **Search**: `FoodSearchView` no longer `@Query`-loads all foods. Debounced (220 ms) SQLite fetch —
      `#Predicate` localizedStandardContains(name|brand) + `fetchLimit 60`; relevance rank on the capped set.
      Verified by `foodSearchPredicateMatchesNameAndBrandCaseInsensitively`.
- [x] **Per-row decode**: `FoodRow.servingKcal` reads stored `kcalPer100g` instead of decoding the blob.
- [x] **Add**: `LogFoodView.add` dismisses first; `HealthKitManager.syncDay` body wrapped in `Task { @MainActor }`
      (was a sync fetch + full-day decode before dismiss). All syncDay callers now non-blocking.
- [x] **Diary**: `total` computed once per render, threaded into summaryCard/microLink (was ~6× full decode).
      `NutrientVector` reuses static JSONEncoder/Decoder. `NutritionGoals.targetable` → `static let`.
- [x] **CloudDedup**: `dedupeFoods` count-guard (skip the 7.7k fetch+group when seed count unchanged) +
      `purgeLegacyCurated` COUNT guard; CloudKit import storm trailing-debounced (8 s); removed the redundant
      launch purge in ContentView (CloudDedup.start already runs it).
- [x] Build green (0 warnings); 35/35 unit tests pass.

## Deferred (latent, not the acute pain)
- [ ] Scope diary/recents `@Query` to the day via a `#Predicate` child view (loads all entries today; fine while small).

---

# Task: Single-source USDA catalog — retire the curated ghosts (2026-06-10)

Plan: `~/.claude/plans/partitioned-riding-adleman.md` (approved). Why: the Phase-1 curated catalog
(`FoodLibrary.all`, macros-only, fdcId 0 — e.g. "Kiwi") and the USDA catalog (e.g. "Kiwifruit, green,
raw") never reconcile (`CloudDedup` keys them `name|brand` vs `fdc:id`), so the old set syncs back from
iCloud as friendly-named, micro-empty duplicates users tap by mistake. Decision: **one source of truth =
USDA**; friendly names become a Stage-2 display overlay, never a 2nd nutrient store.

## Stage 1 — single-source USDA ✅
- [x] FoodSeedManager.seedIfNeeded: seed USDA catalog only; if JSON absent, seed nothing (drop the
      `FoodLibrary.all` fallback + its now-dead `seed([SeedFood])` overload)
- [x] CloudDedup.purgeLegacyCurated: delete `sourceRaw=="seed" && fdcId==0` foods; wired into `runIfDue`
      (re-runs on each CloudKit import → cloud copies clear) + called once in ContentView RootView.task
      (cloud-off upgrade path; runIfDue is cloud-gated)
- [x] Tests (CloudSyncTests/CloudDedupTests): `purgeRemovesLegacyCuratedKeepsDiaryAndCustoms`,
      `purgeIsIdempotent` — ghost dies; USDA/custom survive; diary snapshot preserved (food nullified)
- [x] Build green; 6/6 CloudDedupTests pass; clean reinstall → 7,756 foods, **0** fdcId=0 seed ghosts
- [ ] **User:** commit `tracklifts/Resources/FoodCatalog.json` (now the only catalog); optionally reset
      CloudKit Dev env for an instant clean slate (else purge converges over a sync cycle)

## Stage 2 — friendly name/portion overlay (follow-up, separable)
- [ ] Generate `Resources/FoodAliases.json` (`[{fdcId,name,portions}]`) by matching the 258 FoodLibrary
      foods → catalog fdcIds (verified, not fuzzy-on-nutrients); apply at seed time in FoodSeedManager

---

# Task: Phase 2 — Nutrition depth (micros, DRI targets, completeness, charts, HealthKit)

Plan: `~/.claude/plans/partitioned-riding-adleman.md` (superseded by the task above)
Decision: **Option B** — USDA data seeded into SwiftData (not a bundled SQLite/FTS engine).

## Slice 0 — `fdcId` identity column ✅
- [x] Food.swift: `fdcId` on FoodItem + DiaryEntry (trailing defaulted init param; DiaryEntry copies food.fdcId)
- [x] FoodLibrary.swift: `fdcId` on SeedFood (trailing default)
- [x] FoodSeedManager.swift: pass `fdcId`
- [x] Build green (BUILD SUCCEEDED, iPhone 17 / iOS 26.2 sim)

## Slice 1 — Nutrient registry expansion
- [ ] Nutrition.swift: ~22 micro cases + label/unit; keep macro convenience init macro-only
- [ ] New NutrientReference.swift: NutrientGroup, NutrientLimitKind, DRI table (sex/age-band, published)
- [ ] Build green

## Slice 2 — USDA importer tool (off-app) ✅
- [x] tools/usda-import.swift: FDC CSV → FoodCatalog.json; id→Nutrient map; unit normalization (kJ→kcal, Vit D IU→mcg)
- [x] `--verify` (spot-check) + `--limit` + synthetic fixture (tools/usda-fixture/)
- [x] Verified offline: chicken/spinach panels + Vit D 4 IU→0.1 mcg correct; branded skipped; clean JSON
- Note: dropped `--bootstrap` (a standalone script can't see app types); app falls back to FoodLibrary.all until FoodCatalog.json exists

## Slice 3 — Catalog ingestion + search/dedup hardening ✅
- [x] FoodSeedManager.swift: decode FoodCatalog.json (micros via dict init) else FoodLibrary.all; batch save every 500
- [x] CloudDedup.swift: key on fdcId when non-zero (else name|brand)
- [x] FoodSearchView.swift: search perf (empty short-circuit, localizedStandardContains, prefix(50))
- [x] Build green. Runtime still on 258 fallback until FoodCatalog.json generated (favorite/log/recents untouched)

## Slice 4 — DRI auto-targets + manual override ✅
- [x] NutritionGoals: key(for:) + defaultTarget(_:sex:age:) + targetable
- [x] Profile.apply: also write micro targets (onboarding + Recalculate)
- [x] CloudPrefs.mirrored: append micro keys
- [x] SettingsView: MicronutrientTargetsView link (new editable Nutrient Targets screen)
- [x] Build green

## Slice 5 — Micronutrient panel UI ✅
- [x] MicronutrientPanelView (grouped rows, MacroProgressBar, stay-under "LIMIT" caution)
- [x] FoodDiaryView: "Micronutrients ›" entry row
- [x] Build green

## Slice 6 — Daily completeness score ✅
- [x] Completeness.swift: score(total:sex:age:) (capped coverage − bounded stay-under penalty)
- [x] Surface headline in panel + badge on diary Micronutrients row
- [x] Build green

## Slice 7 — Nutrient-over-time charts ✅
- [x] NutrientTrendView (cloned BodyWeightView chart; nutrient + TimeWindow pickers; target RuleMark)
- [x] Linked from panel ("Nutrient trends over time")
- [x] Build green

## Slice 8 — HealthKit ✅
- [x] Entitlement (healthkit) + Info.plist usage strings (pbxproj, both configs)
- [x] HealthKitManager: read bodyMass→BodyWeightEntry, write dietary* per-day; loop-safe (disjoint read/write sets, idempotent sync id/version)
- [x] SettingsView Apple Health card; wired into RootView.task + every diary mutation
- [x] Build green (sim, zero warnings); device caveat for real reads / capability provisioning

## Review (2026-06-10) — Phase 2 shipped (8 slices, all builds green; logic tests pass)

**What shipped**
- **Nutrient registry** (Nutrition.swift, NutrientReference.swift): ~30 nutrients (8 macros + 11 vitamins + 9 minerals + 4 fats), each with unit/group/limit-kind; published DRI/RDA/AI by sex/age band + stay-under limits. Keyed `NutrientVector` → zero schema migration.
- **USDA importer** (tools/usda-import.swift): FDC SR-Legacy+Foundation CSV → Resources/FoodCatalog.json; nutrient-id map + unit normalization (kJ→kcal, Vit D IU→mcg). Verified on synthetic fixture (tools/usda-fixture/). `--verify`/`--limit`.
- **Catalog ingestion** (FoodSeedManager): prefers FoodCatalog.json (full micros via dict init, batched) else the 258 Swift seed. `fdcId` on FoodItem/DiaryEntry; CloudDedup keys on it; search hardened for thousands.
- **DRI targets** (NutritionGoals.key(for:)/targetable; Profile.apply): onboarding + Recalculate write per-nutrient targets; CloudPrefs-mirrored; editable in a new Nutrient Targets screen.
- **Micronutrient panel** (MicronutrientPanelView): grouped rows, progress vs target, stay-under "LIMIT" caution; linked from the diary.
- **Completeness score** (Completeness.swift): capped adequacy coverage − bounded stay-under penalty; panel header + diary badge.
- **Nutrient trends** (NutrientTrendView): cloned BodyWeightView chart; nutrient + range pickers; target rule line.
- **HealthKit** (HealthKitManager): read body mass → BodyWeightEntry funnel; write dietary energy/macros as idempotent per-day samples; disjoint read/write sets → loop-safe; Settings card; RootView + diary-mutation wiring.

**Architecture decision:** Option B (USDA data seeded into SwiftData), NOT a bundled SQLite/FTS engine — keeps the working Phase-1 food surface, reuses CloudDedup, no C-interop. (Plan file: ~/.claude/plans/partitioned-riding-adleman.md)

**Verification:** clean iOS-17 build on iPhone 17 / iOS 26.2 sim, zero warnings, after every slice. New `NutrientTargetsTests` (DRI resolution + completeness behavior) pass with the existing suite — **TEST SUCCEEDED**. Importer verified by running on the fixture (chicken/spinach panels, Vit D 4 IU→0.1 mcg).

**Remaining manual steps (data + device — can't be done in this environment):**
1. **USDA data:** download FoodData Central SR-Legacy + Foundation "Full Download" CSVs → `swift tools/usda-import.swift --input <dir> --output tracklifts/Resources/FoodCatalog.json --limit 3000`; add the JSON to the app target. Until then the app runs on the 258-food bootstrap (only fiber/sodium/sat-fat carry values → micro panel mostly 0, completeness low — expected, not a bug).
2. **HealthKit on device:** build once in Xcode (signed) so the HealthKit capability registers with the provisioning profile; verify real body-mass/active-energy reads + dietary writes on hardware.

**Known minor polish (non-blocking):** the new Nutrient Targets editor relies on default ScrollView keyboard avoidance rather than the focused-field-scroll-to-top pattern.
