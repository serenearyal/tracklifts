# Task: Performance benchmark suite + Instruments instrumentation (2026-06-16)

Goal: make the PERF gains measurable & regression-guardable. 4 parallel agents over
disjoint files. Layer 1 = XCTest `measure` micro-benchmarks (naive-vs-optimized deltas +
baselines); Layer 2 = os_signpost markers for the Instruments-only wins (seed freeze, render counts).

## Layer 1 — XCTest benchmarks (new files in trackliftsTests/)
- [x] `DiaryPerformanceTests` — DiaryMath.total + group-by-meal, optimized vs naive 6× (PERF-3/6/7/8); ~3,960 entries
- [x] `ProgressPerformanceTests` — ProgressCalculator.series single-pass vs E× recompute (PERF-2/4/9); 30 ex × 200 sessions
- [x] `CatalogPerformanceTests` — seed throughput (PERF-1 CPU) + FoodSearch.run + confidentMatch (PERF-11); 5,000 foods
- [x] `PerfBench.swift` — `benchMillis` ContinuousClock helper (prints per-iteration avg/min to stdout)

## Layer 2 — Instruments instrumentation (app source)
- [x] `Shared/PerfSignpost.swift` — `Perf` OSSignposter helper (renderTick event + interval)
- [x] FoodSeedManager: signpost interval around seed (shows the freeze in Hangs/Time Profiler)
- [x] FoodDiary/ProgressOverview/LogWorkout bodies: render-tick signpost (counts re-evals)
- [x] FoodSeedManager.benchmarkSeed — synchronous internal seed entry for the benchmark

## Verification
- [x] Test target compiles — fixed missing `import OSLog` (FoodSeedManager) + `.wallClock`→`.wallClockTime`
- [x] Full unit suite green — **TEST SUCCEEDED**, 0 failures (logic + 8 perf benchmarks)
- [x] Wire CatalogPerformanceTests → FoodSeedManager.benchmarkSeed (dropped inline dup)
- [x] Captured numbers (from run totals; setUp identical within each pair → Δ is the optimized delta):
  - Diary aggregation: optimized **2.77 s** vs naive **4.61 s** → ~**184 ms/render saved** at ~4k entries
  - Progress overview: optimized **3.08 s** vs naive **4.35 s** → ~**126 ms/render saved** at 30 ex × 200 sessions
  - Seed throughput: **~5 s / 5,000 foods** (~8 s at prod 7,756) — the work PERF-1 moved off the main thread
  - Search ~45 ms/query, confident-match ~40 ms over 5k foods (PERF-11 was a minor opt)

## Notes
- xcodebuild does NOT echo test `print()` or `measure` averages to the terminal (routed to the
  .xcresult). So CLI shows per-test TOTALS; exact per-iteration averages + baselines are in Xcode's
  Report Navigator (Product ▸ Perform Action ▸ Test, or open the .xcresult). `measure {}` blocks drive
  Xcode's regression baselines; `benchMillis` prints per-iteration avg/min in Xcode's console.
- Instruments: filter to subsystem `serene.tracklifts`, category `Performance` — `SeedCatalog` interval
  shows the first-launch hang (Time Profiler / Hangs); `*.body` render-tick events count re-evals.
- NOT committed yet (awaiting go-ahead).

---

# Task: Implement perf+bug review fixes (2026-06-16)

Source: `tasks/perf-bug-review.md` (23 findings). Fixing ALL. Approach: 5 parallel
subagents over disjoint file groups (A/B/C1/C2/D), then one integration build.
Legend: 🔴 High · 🟠 Medium · 🟡 Low. Owner agent in parens.

## Crash class — BUG-1 (raw `Int(Double)` traps) 🔴
- [x] Food.swift:164 `restate` → `.rounded().safeInt` (C1)
- [x] FoodDiaryView `save()` clamp grams ≤ 100_000 before restate (C1)
- [x] FoodSearchView:578 "g total" → `.rounded().safeInt` (C2)
- [x] EditFoodView clamp `servingGrams` ≤ 100_000 on save (C2)
- [x] OnboardingView clamp Weight/Goal-weight fields (clamping Binding) + `.safeInt` labels (D)

## High performance 🔴
- [x] PERF-1 FoodSeedManager + ContentView: async seed, `Task.yield()` between batches (D)
- [x] PERF-2 ProgressOverviewView: single series map, hoist trackedExercises/ordered (B)
- [x] PERF-3 FoodDiaryView: group-once by meal; `==` start-of-day; kill empty-day rescan (C1)
- [x] PERF-4 LogWorkoutView: compute previousEntry/best once; hoist sort (B)

## Medium 🟠
- [x] BUG-2 SpeechCapture: gate handler on `.listening`; stop() sets idle first (A)
- [x] BUG-3 CaptureView: split text/photo task handles (A)
- [x] BUG-4 FoodVisionProvider: Gemini `timeoutInterval = 30` (A)
- [x] BUG-5 NutritionPlan/OnboardingView: ETA from realized (clamped) rate (D)
- [x] BUG-6 OpenFoodFacts: `Task.isCancelled` check after await (A)
- [x] PERF-5 FoodSearchView + RecipeEditorView: bound recentEntries (fetchLimit 200) (C2)
- [x] PERF-6 MicronutrientPanelView: hoist `total` once (C1)
- [x] PERF-7 NutrientTrendView: hoist `points` once (C1)
- [x] PERF-8 TodayView: hoist eaten/weekSessions (latestWeight left as-is, see note) (C1)

## Low 🟡
- [x] BUG-7 HealthKitManager: gate "connected" on sharingAuthorized (D)
- [x] BUG-8 Completeness: user-specific stay-under set (D)
- [x] BUG-9 FoodProvider/FoodSearchView: RemoteFood Identifiable, drop id:\.offset (C2)
- [x] BUG-10 BodyWeight: normalize date to startOfDay in init (D)
- [x] BUG-11 FoodVisionProvider + OpenFoodFacts: one bounded retry on 429/5xx (A)
- [x] PERF-9 ExerciseProgressView: hoist `points` once (B)
- [x] PERF-10 CloudPrefs: debounce pushLocal (400ms), drop routine synchronize() (D)
- [x] PERF-11 FoodSearch + CaptureMatcher: precompute query tokens once (D + C2)
- [x] PERF-12 CaptureView: JPEG decode/encode off the main actor (nonisolated async) (A)
- [x] PERF-13 usda-import: build tool only — NO ACTION needed
- [x] Quick-win `.safeInt` sweep: TodayView, FoodDiaryView:188, CaptureMatcher:172,179 (C1/C2)

## Verification
- [x] Integration build green — **BUILD SUCCEEDED**, 0 errors / 0 warnings (iPhone 16 / iOS 18.0 sim; target is iOS 17.0)
- [x] Hermetic logic tests (`trackliftsTests`) — **all passed, 0 failures** (exit 0). Notably the CaptureMatcher
  confidence/density suite (PERF-11), CloudPrefs push/idempotency (PERF-10), and DRI/NutrientReference (BUG-5/8) all green.
- [x] Review section (below)

## Review (2026-06-16) — all 23 perf+bug findings fixed
- **Approach:** 5 parallel subagents over disjoint file groups (no two agents touched the same file → zero
  edit conflicts), one integration build + the hermetic logic suite to verify. Orchestrator re-verified the
  crash-class sites and the perf hot paths against source first; that pre-check corrected a misattributed
  finding (the "Age field" crash from the review was NOT real — Age/Height use a sliderbound `tickerStepper`
  with no text field; the actual onboarding crash was the Weight/Goal-weight `tickerField`).
- **Crash class (BUG-1) closed at all 3 reachable sites:** diary grams edit, custom-food serving, onboarding
  weight — inputs clamped at the boundary (≤100_000 g / `weightBounds`) AND every raw `Int(Double)` display
  routed through the existing saturating `Double.safeInt`. No more `Int.max` traps from a typed field.
- **4 High perf fixes:** first-launch seed no longer freezes the UI (async + `Task.yield()`); ProgressOverview,
  FoodDiary, and LogWorkout no longer re-scan/re-decode unbounded `@Query`s 3–6× per render (single-pass maps,
  body-level `let` hoisting, `==` start-of-day instead of per-entry `Calendar.isDate`).
- **Behavior preserved:** all perf fixes are pure memoization/hoisting; nutrition math, PR/series semantics,
  and matcher behavior unchanged (logic suite confirms). BUG-8 is a latent-correctness fix (identical output
  today). Two deliberate scope-limited deviations logged above (PERF-1 fallback, PERF-8 latestWeight).
- **Not committed** (per the no-auto-commit rule) — working tree only.
- **Residual (unchanged from the review):** perf gains are static/structural — magnitudes still want an
  Instruments pass under a year of seeded data; device-only paths (HealthKit denial UX, live camera) need a
  hardware eyeball. PERF-1 could later move to a true background `ModelContext` if the `@Model` inits are made
  `nonisolated` (a deliberate, separable shared-API change).

## Notes / deviations from spec
- PERF-1: kept seeding on the main context but made `seedIfNeeded` `async` and added
  `await Task.yield()` after decode + every 200 inserts (the finding's sanctioned fallback).
  A true background `ModelContext` was avoided because the `@Model` inits are MainActor-isolated
  (whole-target default), so a detached context would require marking those inits `nonisolated`
  in Food.swift — a shared-API change out of scope. Still unfreezes the UI during the import.
- PERF-8: `latestWeight` left unchanged — the `@Query` sorts by `date` only, but `latestWeight`
  breaks ties on `(date, createdAt)`; swapping to `weights.last` could change the shown weight on
  same-day entries. Hoisting done; the re-sort kept intentionally.
- BUG-8: latent fix (current stay-under DRI limits are sex/age-independent, so output is identical
  today) — removes the fixed-male/30 vs real-user membership mismatch.

---

# Task: Phase 4 — Capture magic (typed + voice + photo) (2026-06-11)

Plan: `~/.claude/plans/idempotent-dazzling-lovelace.md` (approved). One pipeline, three front-ends → a
shared review-and-confirm step. **Decisions:** text/voice parse = on-device heuristic (offline, Principle 3);
photo = cloud Gemini behind an opt-in (D2). iOS-17 floor has no on-device LLM, so heuristic not Foundation Models.

## Slice 1 — Pipeline core (logic, tested first)
- [x] `Data/MealTextParser.swift`: `ParsedItem` + heuristic `parse` (segment on commas/and/with; quantity as digits/fractions/written/fused "200g"; unit synonyms; drop fillers)
- [x] `Data/CaptureMatcher.swift`: `CaptureMatch` + `match` (FoodSearch best hit) + pure `resolveGrams` (hint → mass/volume table → food portion → default×qty)
- [x] `MealTextParserTests` + `CaptureMatcherTests` (hermetic, 12 tests); build + tests green

## Slice 2 — Confirm sheet + typed capture
- [x] `Features/Capture/CaptureConfirmSheet.swift`: editable rows (swap food via `CaptureFoodPicker`, tweak grams, remove), MacroPreview totals, pinned meal-picker + "Add all" → one DiaryEntry per matched row (copies `logSavedMeal`)
- [x] `Features/Capture/CaptureView.swift`: text entry → parse → match → push confirm
- [x] Camera "Snap Meal" entries on `TodayView` (Nutrition header) + `FoodDiaryView` (beside search) + `.sheet` _(later reshaped to camera-first; see below)_
- [x] Build green (fixed a `compactMap(method)` main-actor warning → explicit closure); logic tests green

## Slice 3 — Voice
- [x] `Features/Capture/SpeechCapture.swift`: `SFSpeechRecognizer` (`requiresOnDeviceRecognition`) + `AVAudioEngine` + mic/speech auth
- [x] mic button in `CaptureView` (transcript → same parser); `project.pbxproj` mic + speech usage strings (both app configs)
- [x] Build green (no concurrency warnings)

## Slice 4 — Photo (Gemini, opt-in)
- [x] `Data/FoodVisionProvider.swift`: `FoodVisionProvider` + `GeminiFoodVision` (gemini-3.1-flash-lite, `responseMimeType` JSON) + `GeminiConfig` (env / `Secrets.plist`)
- [x] PhotosPicker photo button behind `photoAICloudEnabled` opt-in (first-use dialog + Settings toggle); ~1024px JPEG to cap cost
- [x] `.gitignore` `Secrets.plist` + committed `Secrets.example.plist`
- [x] Build green (full phase, 0 concurrency warnings)

## Review (2026-06-11)
- **One pipeline, three inputs.** Text, voice transcript, and photo all reduce to `[ParsedItem]` → `CaptureMatcher` → `CaptureConfirmList` → existing DiaryEntry commit. Nutrients always come from the matched catalog food (Principle 2) — the parser/model only proposes name + portion.
- **Offline-correct on iOS 17.** No on-device LLM at the 17.0 floor, so text/voice use a rule-based parser + `SFSpeechRecognizer`; only photo (which needs the model) leaves the device, behind an explicit opt-in (Settings toggle). Principle 3 intact.
- **Verified:** build green after every slice (0 concurrency warnings); +12 hermetic tests pass. Live mic + camera are device-only (sim has neither) — left to you. Photo needs a Gemini key (`Secrets.plist` or `GEMINI_API_KEY` env), else it shows a disabled state.
- **Not committed yet** (per the no-auto-commit rule).

## UX polish (2026-06-12)
- **Camera-first capture:** `MealCameraPicker` (UIImagePickerController `.camera`) → primary "Take a Photo";
  gallery as the secondary, sim falls back to gallery (mirrors the barcode scanner). Capture sheet reordered
  photo-first; smoothed opt-in (Enable → opens camera/gallery directly).
- **Explicit, prominent entries:** ✨ → a camera "Snap Meal" pill on Today + a camera button beside the Food
  tab's search bar. Broadened `NSCameraUsageDescription` to mention meals.
- **`PhotoStatusOverlay` (the big one):** replaces the bland spinner + tiny red error. While Gemini runs, a
  **vision-scan** over the captured photo (sweeping ember beam, viewfinder corner brackets, frosted status card
  cycling "Identifying foods → Estimating portions…", shimmer bar), cancellable. On failure, a **tailored
  recovery screen** distinguishing **no-food** / **unreadable** / **no-key**, each with a Bebas headline, helpful
  copy, and real CTAs (Retake / Gallery / Try Again / **type it instead**). Retry re-runs the same image; the
  in-flight task is cancelled on close. Build green, 0 concurrency warnings.
- **Overlay overflow fix:** the status/failure cards were full-bleed (`.frame(maxWidth: .infinity)`) and clipped
  text off-screen. **Actual fix:** cap the cards at a centered `cardMaxWidth = 320` (+ 16pt horizontal floor) so
  they sit inside the screen with side margins, not edge-to-edge. Backstops also added: `...DynamicTypeSize.xLarge`
  clamp, `lineLimit` + `minimumScaleFactor` on status phrase / headline / secondary buttons + shared `EmberButton`,
  smaller bases (headline 34→30, icon 86→76, less tracking), shorter "Choose Another Photo" → "Choose Photo".
  Build green. _(Clamp + shrink-to-fit alone did not resolve it — the width cap was the fix.)_

## Phase 4.1 — photo nutrition estimation for unknown foods (2026-06-12)
- **Problem:** a photographed food not in the catalog (a glazed donut) was a red "no match" dead-end — unloggable.
- [x] `ParsedItem.estimatedPer100g: NutrientVector?` — one optional field, photo-only (heuristic leaves it nil).
- [x] `FoodVisionProvider`: Gemini prompt now also returns each item's TOTAL nutrition (energy + 8 label macros,
  "always estimate even for foods in no database"); `decodeItems` → per-100 g via `NutrientVector.fromPerServing`.
- [x] `CaptureMatcher`: no catalog hit + estimate → build an **un-inserted** custom `FoodItem` (`isEstimated`),
  loggable with full macros; catalog match still wins; `gramsHint` keeps it off the un-inserted `portions`.
- [x] `CaptureConfirmSheet`: **"Estimated"** pill (sparkles, editable); `commit()` persists the food + a
  "1 serving" portion (reusable/searchable, re-photo re-matches); `changeFood` clears the flag on swap.
- [x] +2 hermetic `CaptureMatcherTests` (round-trip + catalog precedence); **71 passed / 0 failed**, build green.
- _Out of scope: micronutrient estimates; fuzzy dedup of differently-named estimates._

---

# Task: Phase 3 (finish) — Water + Saved Meals + Recipes (2026-06-11)

Plan: `~/.claude/plans/mossy-wondering-lamport.md` (approved). Finishes Phase 3 — cover the long tail so
users never hit a dead end. Three independently-shippable slices (Water → Saved Meals → Recipes), each
reusing the existing diary/log engine rather than a parallel path. **CloudKit:** 5 new `@Model` types =
additive schema change → redeploy Dev→Prod in CloudKit Console before the next TestFlight.

## Slice A — Water tracking
- [x] `Models/Water.swift` (new): `WaterEntry` (date, amountMl) + `WaterUnit` (ml/oz/cup) + `WaterGoals` (goal/unit keys)
- [x] `CloudSync.swift`: register `WaterEntry.self` in the Schema
- [x] `CloudPrefs.swift`: mirror `goalWaterMl` + `waterUnit`
- [x] `FoodDiaryView.swift`: water card after the summary (progress vs goal, unit-aware quick-add, undo)
- [x] `SettingsView.swift`: water goal + unit row in Daily Targets (edits in the chosen unit, stores ml)
- [x] `WaterTests`: unit round-trip + start-of-day normalization + day-total filtering
- [x] Build green (iPhone 17 / iOS 26.2 sim, 0 warnings in new/edited files); 51/51 logic tests pass (4 new water)

## Slice B — Saved Meals
- [x] `SavedMeal`/`SavedMealItem` models (+ `FoodItem.savedMealItems` inverse) + schema registration
- [x] "Save as meal" action (bookmark button) on a diary meal section that has entries → `SaveMealSheet`
- [x] Log-as-group from FoodSearchView empty state → one DiaryEntry per item into the sheet's meal slot
- [x] `SavedMealTests`: builds from foods → logs N entries w/ right grams/portion/meal/day; deleted-food item skipped
- [x] Build green (0 warnings); 53/53 logic tests pass (2 new saved-meal)

## Slice C — Recipes
- [x] `Recipe`/`RecipeIngredient` models (+ `FoodItem.recipeIngredients`/`recipe` inverses) + `FoodSource.recipe` + schema
- [x] `RecipeMath.aggregate` (pure): ingredients → derived per100g + serving grams (reuses NutrientVector +/scaled)
- [x] `FoodSearch` helper extracted (Data/FoodSearch.swift); FoodSearchView.search + RecipeFoodPicker both use it
- [x] `RecipeEditorView` + `RecipeFoodPicker` (clones EditFoodView scaffold; live per-serving MacroPreview)
- [x] FoodSearchView: Recipes section + "Create a recipe"; recipe foods log via existing LogFoodView; pencil → RecipeEditorView
- [x] `RecipeTests`: pure aggregation + derived-food serving math (424→212/serving) + delete keeps logged history
- [x] Build green (0 warnings in my files); 57/57 logic tests pass (4 new recipe)

## Review (2026-06-11) — Phase 3 finished (Water + Saved Meals + Recipes)
- **Reuse over parallel paths.** Recipes become a derived `FoodItem` (source `.recipe`) so a serving logs through
  the *existing* LogFoodView → DiaryEntry path — micros, nutrient panel, completeness all work free. Saved meals
  are just a batch of normal DiaryEntry writes. Water is a tiny entry model + a diary card. Almost no new log UI.
- **Water** (Slice A): `WaterEntry` (ml-canonical) + `WaterUnit` (ml/oz/cup) + `WaterGoals`; CloudPrefs-mirrored
  goal/unit; diary card after the summary (progress vs goal, unit-aware quick-add chips, undo); Settings goal row
  edits in the chosen unit, stores ml.
- **Saved Meals** (Slice B): `SavedMeal`/`SavedMealItem`; "Save as meal" bookmark on a logged diary meal section
  → `SaveMealSheet`; surfaced in search's empty state, taps log every item into the sheet's meal/day; items
  re-price from the live food and skip a deleted one (snapshot kept for display).
- **Recipes** (Slice C): `Recipe`/`RecipeIngredient`; pure `RecipeMath.aggregate`; `RecipeEditorView`
  (+ `RecipeFoodPicker`) recomputes the derived food on save; Recipes section + "Create a recipe"; recipe foods
  are searchable and edit via a recipe-aware pencil in LogFoodView. Deleting a recipe cascades to its food +
  ingredients; logged history keeps its immutable snapshot (verified by test).
- **iOS-17 + CloudKit:** every new to-many child wired from the to-one side after insert; every relationship
  optional with defaults. **5 new @Model types = additive schema change → redeploy CloudKit Dev→Prod before the
  next TestFlight** (no migration code needed; existing rows unaffected).
- **Verified:** build green (0 warnings in new/edited files) after each slice; **57/57** logic tests pass
  (10 new: 4 water + 2 saved-meal + 4 recipe). Manual device/sim walk-throughs left to the user.
- **Not committed yet** (awaiting your go-ahead, per the no-auto-commit rule).

---

# Task: Phase 3 — Barcode scan + Open Food Facts (2026-06-11)

Plan: `~/.claude/plans/mossy-wondering-lamport.md` (approved; scope = barcode + online search). First network
layer, behind a `FoodProvider` adapter; OFF foods reuse existing barcode/source/NutrientVector → no schema change.

- [x] Slice 1: `Data/FoodProvider.swift` (protocol + RemoteFood) + `Data/OpenFoodFacts.swift` (client + pure
      nutriment mapping: kcal/kJ, salt→sodium, g→mg minerals). `OpenFoodFactsTests` (embedded fixtures, hermetic)
- [x] Slice 2: `Features/Food/BarcodeScannerView.swift` (VisionKit wrapper + unsupported fallback);
      `INFOPLIST_KEY_NSCameraUsageDescription` in both app configs (pbxproj)
- [x] Slice 3: FoodSearchView scan button → scanner → lookup → upsert/cache → LogFoodView; miss → EditFoodView
      w/ `prefillBarcode`; ODbL attribution on OFF foods; Settings credit row
- [x] Slice 4: online OFF text-search fallback section in FoodSearchView (debounced, cancellable)
- [ ] Slice 5 (deferred, optional): CloudDedup collapse OFF foods by barcode (local reuse-by-barcode already
      prevents single-device dups; cross-device dup is an edge case)
- [x] Build green (iPhone 17 / iOS 26.2 sim, 0 warnings); 47/47 logic tests pass (TEST SUCCEEDED).
      Camera scan = device-only manual (Simulator has no camera).

## Review (2026-06-11) — Barcode + Open Food Facts shipped (Slices 1–4)
- **First network layer**, behind `FoodProvider` (Data/FoodProvider.swift); `OpenFoodFactsProvider`
  (Data/OpenFoodFacts.swift) does v2 product + cgi search over HTTPS with an OFF User-Agent. Pure
  nutriment→`NutrientVector` mapping (kcal/kJ, salt→sodium, g→mg) is unit-tested against embedded fixtures.
- **Scanner** (BarcodeScannerView): VisionKit `DataScannerViewController` (ean13/8, upce, code128/39); graceful
  unsupported state on the Simulator. Needed `import Vision` for `VNBarcodeSymbology` + NSCameraUsageDescription.
- **Photo upload** (2026-06-11, per request — log a product later / no box in hand): the scanner also accepts a
  **library photo** via `PhotosPicker` (no permission string) → `VNDetectBarcodesRequest` on the still image
  (off-main, orientation-corrected; `nonisolated` to satisfy MainActor-default isolation). The no-camera state
  offers a prominent "Choose a Photo" — so the sim can now exercise the whole barcode→OFF→log flow via a photo.
- **Flow** (FoodSearchView): barcode button → scanner → local-cache hit (offline, instant) else OFF lookup →
  `upsert` (reuse-by-barcode, iOS-17-safe portion) → push LogFoodView; miss → EditFoodView prefilled w/ the GTIN.
  Online "Open Food Facts" search section appears when the local catalog is thin (debounced/cancellable).
- **OFF foods** = `source: .openFoodFacts` + barcode; no schema/CloudKit change, so they sync + survive dedup.
  ODbL attribution in LogFoodView + a Settings credit.
- **Gotchas found by tests:** (1) float `==` on g→mg conversions → use tolerance; (2) the v2 product endpoint
  returns the canonical `code` at the TOP level, not inside `product` → decoder now reads `resp.code`.
- **Verified:** build green (0 warnings in new files); 47 logic tests pass incl. 6 OFF mapping tests.
  Camera scanning itself is device-only (left to manual).

---

# Task: Phase 3 (start) — Custom foods (2026-06-11)

Plan: `~/.claude/plans/mossy-wondering-lamport.md` (approved). Let users create/edit/delete their own
foods that flow through the existing search → LogFoodView → diary path. Model is already custom-ready
(`isCustom`, `FoodSource.custom`, `portions`, keyed `NutrientVector`) → no schema/seed/CloudDedup change.

- [x] Nutrition.swift: `NutrientVector.fromPerServing(_:servingGrams:)` + `perServing(servingGrams:)` (pure, tested)
- [x] EditFoodView.swift (new): create/edit/delete; clones EditExerciseView + MicronutrientTargetsView grid;
      per-serving entry, Macros visible + "More nutrients" disclosure; `.keyboardDoneBar()`
- [x] FoodSearchView: "Create '<term>'" in no-match state + persistent create row → sheet EditFoodView(nil)
- [x] LogFoodView: pencil → EditFoodView(food) when `food.isCustom`
- [x] CustomFoodTests: per-serving↔per-100g round-trip + custom survives dedup/purge
- [x] Build green (iPhone 17 / iOS 26.2 sim, 0 warnings); 41/41 logic tests pass (TEST SUCCEEDED)

## Review (2026-06-11) — Custom foods shipped
- **New:** `EditFoodView` (create/edit/delete a `.custom` FoodItem), reached from search (no-match
  "Create '…'" + a persistent create row) and from `LogFoodView` (pencil, customs only). Nutrients are
  entered per serving (label + grams) and converted to per-100 g; full nutrient depth behind a "More
  nutrients" disclosure. `.keyboardDoneBar()` (the polish gap the Nutrient-Targets editor still has).
- **Zero plumbing churn:** model already custom-ready, so no schema/seed/CloudDedup change. Custom foods
  surface in search via the existing predicate and log via the existing `LogFoodView` with no special-casing.
- **iOS-17-safe:** portion wired from the to-one side after insert (mirrors `FoodSeedManager.insertPortions`).
- **Gotcha found:** `NutrientVector()` is zero-filled (8 macro keys), not empty — the `servingGrams <= 0`
  guard now returns `NutrientVector([:])` so it's genuinely empty (caught by `nonPositiveServingGramsYieldsEmpty`).
- **Verified:** build green (0 warnings in new files); 6 new tests (5 conversion + 1 model loggable/dedup-safe)
  pass with the full logic suite. Manual flow (create→log→edit→delete) left to the user.

---

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
