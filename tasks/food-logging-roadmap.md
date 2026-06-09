# TrackLifts — Nutrition & Body Roadmap

Goal: a fully-loaded food + body-composition logger that competes with the best
(Cronometer-class micronutrient depth), with **search-and-add as the engine** and
photo / voice / barcode as convenience layers on top.

**How to use this doc:** work top-down. Each phase has a **Goal**, a **Build** checklist,
and a **Done when** bar. Don't start a phase until the one above it meets its "Done when."
Check items off as you go; the next unchecked phase is always what to do next.

**Status:** ✅ **Phase 0 complete** (body-weight log shipped; build green). **Next: Phase 1** — the
search engine + diary. Resolve **D1** (food data source) before starting it.

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

- **D1 — Data source (needed for Phase 1):** free bundled USDA core *(recommended start)* vs.
  paid provider (better branded/restaurant, costs money + network). → _TBD_
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

## Phase 1 — The engine: search + diary  ⬜  ← the core MVP

**Goal:** a usable food logger — search a real DB, add to a daily diary, see energy + macros.
(Resolve **D1** first.)

**Build**
- [ ] One-time USDA→SQLite curation script (a few k common whole foods, full panel + portions).
      Output committed as a bundled resource. *(Spike this before finalizing the schema.)*
- [ ] `FoodItem` / `FoodPortion` / `DiaryEntry` / `Meal` models + `NutrientVector` value type.
- [ ] Bundled-DB import on first launch (SeedManager pattern + versioned flag).
- [ ] **FTS search** over the bundled DB (ranked; recents + favorites first) — fast + great.
- [ ] Add-food flow: result → pick portion → quantity → meal → commit `DiaryEntry` (snapshot).
- [ ] **Food/Diary tab** (FORGE): date header, per-meal sections (Breakfast/Lunch/Dinner/Snacks),
      running energy ring + macro rings, daily totals.
- [ ] Recents, favorites, quick-add, copy previous day; edit/delete entries.
- [ ] Manual energy + macro targets (in Settings); show % of target.

**Done when:** a user can log a full day by searching foods and see accurate calories + macros
against a target. _Unlocks:_ everything else (all modes feed this engine).

---

## Phase 2 — Cronometer parity: micros + targets + HealthKit  ⬜

**Goal:** the micronutrient depth + automated targets that make it competitive.

**Build**
- [ ] Full **micronutrient panel** screen (vitamins, minerals, fats, etc.) with % of target.
- [ ] `NutrientTarget` auto-set from age/sex/weight (DRI/RDA); manual override.
- [ ] **Completeness score** (Cronometer's signature daily "how complete was your nutrition").
- [ ] Nutrient **charts over time** (Swift Charts), reusing Progress patterns.
- [ ] **HealthKit:** read body mass + active energy; write dietary energy + macros. Entitlement +
      permission flow + App Review notes.

**Done when:** every logged day shows a full nutrient breakdown vs. personalized targets, and data
flows to/from Health. _Unlocks:_ credibility + the TDEE math in Phase 5.

---

## Phase 3 — Breadth: barcode, custom foods, recipes, water  ⬜

**Goal:** cover the long tail so users aren't blocked by a missing food.

**Build**
- [ ] **Barcode scan** (`VisionKit DataScannerViewController`) → GTIN → Open Food Facts → upsert
      `FoodItem` (+ OFF attribution). Cache locally.
- [ ] Online **branded search** fallback (OFF) when the bundled DB misses.
- [ ] **Custom foods** (user-entered nutrition labels) + edit.
- [ ] **Recipes** (`Recipe` + `RecipeItem`): compose foods, set yield/servings, log a serving.
- [ ] **Meals** (save a group of foods as a reusable quick-add).
- [ ] **Water** tracking.

**Done when:** users can log packaged products by scan, build recipes, and never hit a dead end.

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
