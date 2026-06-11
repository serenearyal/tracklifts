# TrackLifts — Nutrition & Body Roadmap

Goal: a fully-loaded food + body-composition logger that competes with the best
(Cronometer-class micronutrient depth), with **search-and-add as the engine** and
photo / voice / barcode as convenience layers on top.

**How to use this doc:** work top-down. Each phase has a **Goal**, a **Build** checklist,
and a **Done when** bar. Don't start a phase until the one above it meets its "Done when."
Check items off as you go; the next unchecked phase is always what to do next.

**Status:** ✅ **Phase 0 + Phase 1 + Phase 2 machinery shipped** (body-weight log; food search → log →
diary → goals; ~30-nutrient registry + DRI targets + micronutrient panel + completeness score + nutrient
trends + HealthKit; build green, logic tests pass). **Phase 2 data loaded:** `Resources/FoodCatalog.json`
generated from the **full USDA SR-Legacy (7,756 foods, ~32-nutrient panels)** and verified seeding on the
sim (7,756 `FoodItem`s, micros present); a **Nutrition Facts** breakdown now shows in the log + edit
sheets (not just macros). _Commit the 7.3 MB JSON to ship it; the raw FDC CSVs are gitignored._
**Phase 3 shipped:** ✅ custom foods, ✅ barcode scan + Open Food Facts (lookup + online branded search, cache,
ODbL), ✅ recipes, ✅ saved meals, ✅ water. **Next: Phase 4 — capture magic (voice → photo).** Remaining
Phase 1 polish: true FTS.

---

## Principles (don't violate these)

1. **The engine is search + add.** Every capture mode (photo/voice/barcode) resolves to the
   *same* confirmation sheet that writes a diary entry. Build search first; the rest layer on.
2. **AI proposes, the DB + user dispose.** Models only produce a *query + portion estimate*
   against our curated food DB. They never invent nutrient numbers.
3. **Protect the offline promise.** Search, voice, and barcode stay on-device/private. Only
   photo recognition may use the cloud — and only behind an explicit opt-in.
4. **History is immutable.** A diary entry stores a *snapshot* of its nutrients, so editing or
   deleting a food never rewrites the past (Cronometer-correct).
5. **Lean into the wedge.** This app is also the user's lifting log. Energy balance ↔ body-weight
   trend ↔ strength trend in one place is the differentiator no other food app has.

---

## Architecture decisions (locked)

- **Food DB:** bundle a curated **USDA SR Legacy + Foundation** subset (public domain, full
  ~80-nutrient panel, a few MB indexed SQLite) as the offline engine. Expand to branded/barcodes
  via **Open Food Facts** online (ODbL — add attribution), caching hits locally. A `FoodProvider`
  adapter keeps a paid API swappable later.
- **Nutrient storage:** typed `NutrientVector` (Codable) stored as one blob on `FoodItem`
  (per-100 g/ml); promote only headline macros (kcal, protein, carb, fat, fiber, sugar, sodium)
  to real SwiftData columns for fast sort/predicate. Daily totals = in-memory sum of the day's
  entries (trivial). No 80-column table.
- **Diary entries snapshot** the scaled `NutrientVector` (+ keep a `FoodItem` reference for
  "view food"). Totals use the snapshot.
- **Platform:** iOS 26.2 floor → use **Foundation Models** (on-device LLM, `@Generable`),
  **SpeechAnalyzer/SpeechTranscriber** (on-device STT), and **VisionKit DataScanner** (barcodes).
- **Surface:** a new **"Food" (Diary) tab** in the FORGE language, reusing `ForgeCard`,
  `StatTile`, `EmberButton`, Swift Charts, and the `LibraryModeSwitcher` segmented control.

## Open decisions (resolve before the phase that needs them)

- **D1 — Data source:** ✅ RESOLVED — bundled a curated **258-food Swift catalog** (whole + common
  foods, per-100 g macros + portions) for the offline engine. Full USDA→SQLite import + Open Food
  Facts online expansion = deferred follow-up.
- **D2 — Photo AI (needed for Phase 4):** strictly offline (skip/limit photo, or paid on-device
  SDK like Passio) vs. cloud Claude-vision opt-in (best accuracy). Voice stays on-device either
  way. → _TBD_

## Data model reference (mirror existing `@Model` conventions: default values on every
## property, enums as raw strings + computed accessor, `createdAt`, cascade relationships)

```swift
struct NutrientVector: Codable, Equatable { /* kcal, protein, carb, fat, fiber, sugar,
    sodium + ~70 micros; + scaled(by:) and + operators for aggregation */ }

@Model final class FoodItem {       // canonical food (seeded or custom)
    var name = ""; var brand = ""; var source = FoodSource.usda.rawValue
    var barcode = ""; var per100gJSON = Data(); var kcalPer100g = 0.0  // promoted column
    var isCustom = false; var isFavorite = false; var createdAt = Date()
    @Relationship(deleteRule: .cascade, inverse: \FoodPortion.food) var portions: [FoodPortion] = []
}
@Model final class FoodPortion { var label = ""; var gramWeight = 0.0; var isDefault = false
    var order = 0; var food: FoodItem? }                     // "1 cup = 240 g"
@Model final class DiaryEntry { var date = Date(); var mealRaw = Meal.breakfast.rawValue
    var grams = 0.0; var nutrientsJSON = Data()              // SNAPSHOT
    var foodName = ""; var createdAt = Date(); var food: FoodItem? }
@Model final class BodyWeightEntry { var date = Date(); var weight = 0.0; var bodyFat = 0.0 }
@Model final class NutrientTarget { var nutrientKey = ""; var amount = 0.0; var isAuto = true }
// Phase 3+: Recipe, RecipeItem, WaterEntry
```
Register new models in the `Schema([...])` in `trackliftsApp.swift`. Seed the bundled DB once
via the `SeedManager` pattern (fetchCount==0 guard + a versioned import flag in UserDefaults).

---

## Phase 0 — Body weight log  ✅

**Goal:** real body-weight *history* (was a single `@AppStorage("bodyWeight")` number).

**Build**
- [x] `BodyWeightEntry` model (date, weight, optional bodyFat) + added to schema + preview container.
- [x] `BodyMetrics.refreshCurrent(from:)` mirrors the *latest* entry → calisthenics effective-load
      math unchanged. One-time `SeedManager.seedBodyWeightIfNeeded` migrates the legacy value.
- [x] Quick-add weight via `AddBodyWeightSheet` (decimal field + date), respects `WeightUnit`.
- [x] Weight-trend chart (`BodyWeightView`, Swift Charts) + range picker (reused `TimeWindow`:
      All/90d/30d) + Latest/Lowest/Highest + window delta + history list w/ per-entry deltas + delete.
- [x] Surfaced in Progress (`BodyWeightSummaryCard` w/ sparkline) and Settings (opens the log).

**Shipped:** `Models/BodyWeight.swift`, `Features/Progress/BodyWeightView.swift`; edits to
`Shared/Bodyweight.swift`, `SettingsView.swift`, `ProgressOverviewView.swift`, `SeedManager.swift`,
`ContentView.swift`, `trackliftsApp.swift`. Build green (iPhone 17 Pro / iOS 26.2).

**Done when:** ✅ you can log weights over time and see a trend; calisthenics load still uses the
latest weight. _Unlocks:_ the body-composition half of the wedge (Phase 5).

---

## Phase 1 — The engine: search + diary  ✅  (core MVP — Done-when met)

**Goal:** a usable food logger — search a real catalog, add to a daily diary, see energy + macros.

**Build**
- [x] Curated **258-food catalog** (`FoodLibrary+Core/+Produce.swift`, 119 + 139, built by two
      parallel agents) with per-100 g macros + portions. *(Full USDA→SQLite import deferred — D1.)*
- [x] `FoodItem` / `FoodPortion` / `DiaryEntry` / `Meal` models + `NutrientVector` (sparse, Codable;
      diary entries snapshot their nutrients).
- [x] Bundled import on first launch (`FoodSeedManager`, count==0 guard).
- [x] Search (`FoodSearchView`) — name/brand filter, favorites first. *(In-memory; SQLite FTS
      deferred until the catalog reaches USDA scale.)*
- [x] Add-food flow (`LogFoodView`): portion → quantity → meal → live macro preview → commit.
- [x] **Food tab** (`FoodDiaryView`): day navigator, per-meal sections (B/L/D/Snacks), energy +
      P/C/F summary bars vs goals, entry rows (delete), copy-previous-day.
- [x] Manual energy + macro targets (Settings) + progress vs target.
- [x] Mopped up: favorite toggle (search context menu), tap-to-edit/delete an entry, recents shortcut.
- [ ] _Still open (overlap Phase 2/3):_ custom foods, quick-add, true FTS, USDA/branded expansion.

**Shipped:** `Models/Nutrition.swift`, `Models/Food.swift`, `Data/FoodLibrary*.swift`,
`Data/FoodSeedManager.swift`, `Features/Food/FoodDiaryView.swift`, `Features/Food/FoodSearchView.swift`;
schema + RootView (new **Food** tab) + Settings goals. Build green (iPhone 17 Pro / iOS 26.2).

**Done when:** ✅ a user can log a full day by searching foods and see calories + macros vs a target.

---

## Phase 2 — Cronometer parity: micros + targets + HealthKit  ⬜

**Goal:** the micronutrient depth + automated targets that make it competitive.

**Build**
- [x] Full **micronutrient panel** screen (vitamins, minerals, fats) with % of target (`MicronutrientPanelView`).
- [x] Auto-set targets from age/sex/weight (DRI/RDA, `NutrientReference.swift`); manual override (`MicronutrientTargetsView`).
- [x] **Completeness score** (`Completeness.swift`) — capped adequacy − bounded stay-under penalty.
- [x] Nutrient **charts over time** (`NutrientTrendView`, Swift Charts), cloning the BodyWeight chart.
- [x] **HealthKit** (`HealthKitManager`): read body mass + active energy; write dietary energy + macros.
      Entitlement + usage strings + permission flow done; loop-safe (disjoint read/write sets).
- [x] _Data:_ `FoodCatalog.json` from full SR-Legacy (7,756 foods, full panel); verified seeding on sim (7,756 FoodItems).
- [x] _UI:_ Nutrition Facts (vitamins/minerals/fats + %DV) in the log + edit sheets.
- [ ] _Device:_ verify HealthKit real reads + capability provisioning on hardware.

**Done when:** every logged day shows a full nutrient breakdown vs. personalized targets, and data
flows to/from Health. _Unlocks:_ credibility + the TDEE math in Phase 5. **Status: code complete + green;
awaiting the USDA data import (offline, user-run) + a device pass for HealthKit.**

---

## Phase 3 — Breadth: barcode, custom foods, recipes, water  ✅

**Goal:** cover the long tail so users aren't blocked by a missing food.

**Build**
- [x] **Barcode scan** (`VisionKit DataScannerViewController`) → GTIN → Open Food Facts → upsert
      `FoodItem` (+ OFF attribution). Cache locally. _(device-only scan; sim verifies build + mapping + search)_
- [x] Online **branded search** fallback (OFF) when the bundled DB misses.
- [x] **Custom foods** (user-entered nutrition labels) + edit. _(`EditFoodView`: create/edit/delete)_
- [x] **Recipes** (`Recipe` + `RecipeIngredient`): compose foods, set servings; logs a serving via a derived
      `.recipe` food through the existing LogFoodView (micros / nutrient panel / completeness free).
- [x] **Meals** (`SavedMeal`): "Save as meal" from a logged diary section → re-log the whole group in one tap.
- [x] **Water** tracking (`WaterEntry` + ml/oz/cup unit + goal; diary card with quick-add + undo).

**Done when:** ✅ users can log packaged products by scan, build recipes, save meals, and track water — no dead ends.

---

## Phase 4 — Capture magic: voice, then photo  ⬜

**Goal:** the "wow" input modes — both funneling into the Phase 1 engine. (Resolve **D2** before photo.)

**Build**
- [ ] **Voice (on-device):** `SpeechAnalyzer/SpeechTranscriber` → transcript → parse with
      Foundation Models (`@Generable` → `[{food, qty, unit}]`) → fuzzy-match to DB → confirm sheet.
- [ ] Natural-language quick-add ("a bowl of oatmeal with blueberries") sharing the same parser.
- [ ] **Photo:** image → multimodal model → `[{foodName, estimatedGrams, confidence}]` → match
      each to a DB food (micros come from the DB) → confirm portions. Cloud path behind explicit
      opt-in (or on-device SDK per D2).
- [ ] Unified capture sheet: segmented **Search / Scan / Photo / Voice**, all ending at one
      confirmation step.

**Done when:** a user can log a meal by talking to the app fully offline, and (opt-in) by photo.

---

## Phase 5 — The wedge: energy balance + correlations  ⬜

**Goal:** the differentiator — tie nutrition to the training log already in the app.

**Build**
- [ ] **BMR/TDEE** (Mifflin-St Jeor from weight/height/age/sex + activity); prefer HealthKit
      active energy when available, with a rough resistance-training estimate fallback.
- [ ] **Net calories** = intake − expenditure, shown on the diary.
- [ ] **Correlations** view: energy balance ↔ body-weight trend ↔ strength/volume trend.
- [ ] Streaks, Home-Screen widgets, polish.

**Done when:** the app shows how eating, body weight, and lifting move together — something no
pure food app can.

---

## Sequencing notes

- **Hardest parts** are the food-DB curation/indexing/search-relevance (Phase 1) and the
  nutrient schema/migrations — not the UI. De-risk by spiking the USDA→SQLite script early.
- **Highest value, lowest effort:** Phase 0 (quick win) + Phase 1 (the real MVP). Ship those,
  then layer micros (P2) and modes (P4).
- Scope roughly **doubles the app**. Keep each phase independently shippable.

## Changelog
- _2026-06-08_ — Roadmap created from the architecture discussion. No phases started yet.
- _2026-06-08_ — **Phase 0 shipped:** body-weight log (`BodyWeightEntry`, `BodyWeightView`,
  Progress summary card, Settings entry point, legacy-value migration). Build green.
- _2026-06-08_ — **Phase 1 engine shipped:** 258-food catalog (two parallel agents), nutrition
  models, search→log flow, Food diary tab + goals, new Food tab. Build green. Follow-ups: FTS,
  recents, edit-entry, favorite toggle, USDA/branded import.
- _2026-06-08_ — **iOS 17 support:** target 26.2→17.0, classic TabView, SwiftData to-many-on-fresh
  fix; verified on the iOS 17.0 simulator.
- _2026-06-09_ — **Phase 1 mop-up:** favorite toggle in search, tap-to-edit/delete diary entries,
  recents shortcut (+ shared MacroPreview). Build green; launches clean on iOS 17.0.
- _2026-06-09_ — **Food UX + goal-based targets:** pinned top search bar + dedicated "Search foods"
  entry, tappable favorite star (no long-press), swipe-to-delete diary entries (List-based). New
  **onboarding flow** (goal → stats → activity → live plan reveal) that sets energy + macro targets
  via Mifflin-St Jeor → TDEE → goal adjustment; editable/re-runnable in Settings ("Recalculate").
  Build green; onboarding verified rendering on the iOS 17.0 simulator. _(Partial Phase 2 "auto
  targets": energy + macros done from goal; DRI micronutrient targets still pending the data work.)_
- _2026-06-09_ — **IA restructure (5 tabs → 4):** new **Today** dashboard tab (today's energy/macros
  vs. targets, today's training + repeat-last, body-weight card + quick log, this-week strip);
  **Train** tab merges the old Log + Library behind a Log | Splits | Exercises switcher; Settings
  demoted to a gear pushed from Today. Frees the tab bar for the roadmap: capture sheet + energy
  balance land on Today (Phases 4–5), micros/water/recipes inside Food (Phases 2–3), correlations
  in Progress (Phase 5).
- _2026-06-10_ — **Phase 2 shipped (machinery, data-gated):** ~30-nutrient registry + published DRI/RDA
  table by sex/age (`NutrientReference.swift`); USDA FoodData Central importer (`tools/usda-import.swift`)
  → `Resources/FoodCatalog.json`, consumed by `FoodSeedManager` (falls back to the 258 Swift seed);
  `fdcId` identity + dedup; DRI auto-targets (onboarding/Recalculate, CloudPrefs-mirrored, editable);
  micronutrient panel; completeness score; nutrient trend charts; HealthKit (read body mass, write
  dietary energy/macros, loop-safe). **Architecture: Option B** (USDA seeded into SwiftData, not a
  bundled SQLite/FTS engine — keeps the Phase-1 food surface intact). Build green every slice; new
  DRI/completeness logic tests pass. _Open:_ user runs the importer on the FDC download to populate real
  micros; HealthKit real-data + capability provisioning need a device.
- _2026-06-10_ — **iCloud sync:** SwiftData store now CloudKit-backed (private DB
  `iCloud.serene.tracklifts`) so logs survive reinstall + sync across devices; prefs (profile,
  targets, unit, didOnboard-monotonic) mirror via iCloud KVS; idempotent seed dedup collapses the
  69-exercise/258-food catalog after cross-device merges; hermetic in-memory store for UI tests /
  unit-test host / previews; iCloud status card in Settings. **Release-blocking ops:** (1) deploy
  the CloudKit schema Development → Production in CloudKit Console *before* TestFlight/App Store
  (TestFlight uses Production), and re-deploy after any future model change (changes must stay
  additive); (2) requires the paid Apple Developer Program on team M9Q5YCJ5NU — build once in Xcode
  with automatic signing so the container/capability auto-register.
- _2026-06-11_ — **Phase 3 underway.** **Custom foods** (`EditFoodView`: create/edit/delete; nutrients entered
  per serving → stored per 100 g; surfaces in search + logs like any food; reuses `isCustom`/`.custom`/
  `NutrientVector` — no schema change). **Barcode + Open Food Facts**: `FoodProvider` adapter +
  `OpenFoodFactsProvider` (barcode lookup + online branded search over HTTPS, pure nutriment→`NutrientVector`
  mapping with kcal/kJ + salt→sodium + g→mg); `BarcodeScannerView` (VisionKit DataScanner live camera +
  a **photo-library path** — `PhotosPicker` → Vision `VNDetectBarcodesRequest` on a still image, so you can
  log a product later / when there's no camera, and the sim can exercise the whole barcode→OFF→log flow);
  scanned/online hits cached as `.openFoodFacts` `FoodItem`s (reuse-by-barcode, sync, ODbL attribution),
  miss → create-custom prefilled with the GTIN. No CloudKit schema change. Build green; OFF mapping +
  conversion unit-tested (live camera scan = device-only manual). **Next: recipes, meals, water.**
- _2026-06-11_ — **Phase 3 finished (recipes + saved meals + water).** Reuse over parallel paths: a **recipe** is
  a derived `.recipe` `FoodItem` (`RecipeMath.aggregate` sums ingredients → per-100 g + serving grams via
  `NutrientVector` +/scaled, micros included) so a serving logs through the existing `LogFoodView`→`DiaryEntry`
  path — micronutrient panel + completeness free; `RecipeEditorView` + `RecipeFoodPicker` recompute the food on
  save; deleting a recipe cascades to its food/ingredients while logged history keeps its snapshot. A **saved
  meal** (`SavedMeal`/`SavedMealItem`) snapshots a logged diary section ("Save as meal") and re-logs the group in
  one tap (re-priced from live foods; deleted items skipped). **Water** (`WaterEntry` + `WaterUnit` ml/oz/cup +
  goal, CloudPrefs-mirrored) adds a diary card with unit-aware quick-add + undo. Shared `FoodSearch` ranking
  extracted (Data/FoodSearch.swift). **5 new @Model types = additive CloudKit schema → redeploy Dev→Prod before
  the next TestFlight** (no migration code). Build green every slice; **57/57** logic tests pass (10 new:
  4 water + 2 saved-meal + 4 recipe). **Next: Phase 4 (voice → photo capture).**
