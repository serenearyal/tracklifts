# tracklifts — Correctness & Performance Review

_Principal-level static review of the whole repository. Findings are evidence-based with `path:line` citations. Headline items were independently re-verified by the orchestrator against current source._

## 1. Executive summary

Overall health is **good**: the highest-risk areas for this app — SwiftData iOS-17 to-many-on-uninserted-model handling, cross-actor `ModelContext` safety, the SQLite-backed/debounced food search, untrusted OFF/AI input sanitization (`maxPer100g`, `Double.safeInt`) — are all handled correctly. No data-race or known-crash-class violations were found.

The real defects cluster in two places:

- **One correctness bug class — reachable crashes** from numeric `TextField(value:format:.number)` inputs that are **not upper-clamped** and then feed a raw `Int(Double.rounded())`, which **traps** on any value ≥ `Int.max` (~19 digits). Three reachable sites: editing a diary entry's grams, a custom food's serving size, and the onboarding weight/goal-weight fields. (Note: the Age/Height onboarding fields are *not* affected — they have no text field.)
- **Four High performance issues**, all the same shape: an **unbounded `@Query` filtered/aggregated in Swift inside computed properties referenced multiple times per render**, plus `NutrientVector` JSON-decoding on every `.nutrients` access. These cost grows silently with diary/workout history and bites long-term users on the most-used screens (food diary, progress overview, workout logger).

Counts (excluding Tentative from headlines):

| Severity | Bugs | Performance |
|---|---|---|
| High | 1 (class, 3 sites) | 4 |
| Medium | 4 | 4 |
| Low | 4 | 5 |

Biggest wins: clamp the numeric inputs + route displays through `safeInt` (kills the crash class in ~6 lines); move the first-launch catalog seed off the main actor; hoist multiply-referenced computed properties into single `body`-level `let`s.

## 2. Scope & methodology

**Covered:** every tracked source file under `tracklifts/` (Data, Models, Shared, Features, App), the offline `tools/usda-import.swift`, and the test/fixtures for context. Reviewed via 5 parallel specialist passes (concurrency/async/network, data-layer/algorithmic-complexity, models/nutrition-math, SwiftUI view perf/state, error-handling/resource/boundary), then consolidated and de-duplicated. Headline findings (the crash class, PERF-1/2/3) were re-read and re-verified directly by the orchestrator.

**Limits:** static analysis only — no Instruments/runtime profiling, no load testing, and no `xcodebuild`/`swift analyze` warning pass was run (see Residual). Performance magnitudes are reasoned from complexity + realistic data scale (catalog ≈ **7,756 foods / 7 MiB**; diary/workout tables grow unbounded with use), not measured. PERF-4 (LogWorkoutView) was traced by the specialist pass but not independently re-verified line-by-line by the orchestrator.

## 3. Findings (by severity)

---

### BUG-1 — Unclamped numeric `TextField` → raw `Int(Double)` traps (3 reachable crash sites)
- **Type:** Bug · **Severity:** High · **Confidence:** Confirmed
- **Locations (sink ← source):**
  - `tracklifts/Models/Food.swift:164` (`restate` → `"\(Int(newGrams.rounded())) g"`) ← `tracklifts/Features/Food/FoodDiaryView.swift:487` (grams `TextField`, `.number`) + `:542` (`save()` guards only `grams > 0`, no upper bound).
  - `tracklifts/Features/Food/FoodSearchView.swift:569` (`"\(Int(grams.rounded())) g total"`, `grams = portion.grams * quantity`) ← `tracklifts/Features/Food/EditFoodView.swift:97` + `:182` (`decimalField($servingGrams)` is an unclamped `.number` `TextField`).
  - `tracklifts/Features/Onboarding/OnboardingView.swift:489` (`weightLabel`), `:490` (`targetWeightLabel`), `:569` (`paceDetail` weeks) ← `:240` Weight and `:263` Goal-weight `tickerField` (line 443 `TextField(value:format:.number)`, **not** clamped; the slider/steppers are clamped but the text field is not). Rendered at `:265` (`Text("Now: \(weightLabel)")`) and `:592` (`planTimeframeLine`).
- **Description:** `Int(_: Double)` is a trapping conversion in Swift — it crashes (SIGABRT) on NaN/Inf or any finite value greater than `Int.max`. A `.number`/`FloatingPointFormatStyle` decimal-pad field happily parses a 19–20-digit entry into a *finite* `Double` exceeding `Int.max`. The codebase has a saturating `Double.safeInt` (`Nutrition.swift:229`) and funnels almost every display conversion through it — but these three input→label/persist paths bypass it and use raw `Int(x.rounded())`.
- **Impact:** Hard crash on plausible-to-malicious single-field input in three common flows: editing a logged food, creating a custom food and opening it, and first-run onboarding.
- **Trigger/repro:** e.g. Food tab → tap a logged entry → Grams = `99999999999999999999` → Save → `restate` traps. Or onboarding → Weight field → type a ~19-digit number → advance → `weightLabel` renders → trap.
- **Fix:** (a) Clamp at the input boundary — the app already establishes sane caps elsewhere (OFF serving `≤ 10_000`, capture grams hint `≤ 50_000`): clamp `servingGrams`/edited grams to e.g. `min(value, 100_000)` and onboarding weight/target to the existing `weightBounds`/`targetBounds` in the field setter, not just the slider. (b) Route every remaining `Int(x.rounded())` display through the existing saturating helper: `x.rounded().safeInt`. Both together; (b) alone removes the crash even if a bad value slips through.

---

### PERF-1 — First-launch catalog seed decodes 7 MiB + inserts ~7,700 foods synchronously on the main actor
- **Type:** Performance · **Severity:** High · **Confidence:** Confirmed
- **Location:** `tracklifts/Data/FoodSeedManager.swift:32-51` (decode `:34-35`, insert loop `:42-49`); invoked from `ContentView`'s `.task` (`ContentView.swift:47`).
- **Description:** `seedIfNeeded` is `@MainActor` and **synchronous** (no `await`/`Task.yield` anywhere between the decode and the end of the insert loop). It does `Data(contentsOf:)` + `JSONDecoder().decode([CatalogRecord])` of the 7 MiB catalog, then a 7,756-iteration loop each building a `FoodItem` (which JSON-*encodes* a `NutrientVector`), `context.insert`, and inserting 2–3 `FoodPortion` rows (~20k total inserts). Because `.task` runs on the main actor and the function never suspends, the main actor is occupied for the entire decode+insert — the UI is frozen for the duration on first launch (and any post-reinstall reseed). The `try? context.save()` every 500 rows bounds transaction size but not main-actor occupation.
- **Impact:** O(n) with a large constant (n≈7,700) on the main thread → multi-hundred-ms-to-seconds hang on the user's *first* launch. Single biggest cost in scope.
- **Fix:** Do the decode + insert on a background `ModelContext` (`ModelContext(container)`) from a detached task and `await` it from `.task`; or, if kept on-actor, `await Task.yield()` between batches so frames present. The iOS-17 to-many-after-insert discipline in `insertPortions` is already correct and carries over. Expected gain: first-launch hang → imperceptible; foods stream in.

---

### PERF-2 — ProgressOverviewView recomputes per-exercise series O(exercises × sessions × sets) every render, and `trackedExercises` 2–3×
- **Type:** Performance · **Severity:** High · **Confidence:** Confirmed
- **Location:** `tracklifts/Features/Progress/ProgressOverviewView.swift:140-167` (`recentPRs`, `trackedExercises`), and the per-card `series` recompute in `ExerciseTrendCard`/`trendList` (~`:264`,`:335`).
- **Description:** `recentPRs` (`:140`) loops `trackedExercises` and calls `ProgressCalculator.series(for:..., in: sessions.reversed())` **per exercise** — `series` is O(sessions × sets), so the loop is O(E × S × sets), and `sessions.reversed()` is re-allocated each iteration (`:144`). `trackedExercises` (`:157`) is itself an O(sessions × entries) scan, recomputed independently by `recordsSection` and by `scopeContent`/`trendList`; then each rendered `ExerciseTrendCard` recomputes its own `series` again. All in computed properties, so it re-runs on **every** body evaluation — including each scope-chip tap, the primary interaction on this showcase tab.
- **Impact:** At ~30 exercises × ~150 sessions × 4 sets, a single render is tens of thousands of set traversals, doubled by the trend cards — visible jank on tab open and every chip tap.
- **Fix:** Compute `trackedExercises` once into a `let` and pass it down; build one `[PersistentIdentifier: [ProgressPoint]]` series map in a single pass over sessions and hand slices to `recentPRs` and each card; cache `Array(sessions.reversed())` once. Best: move aggregation behind an `@Observable` model recomputed only when `sessions` changes.

---

### PERF-3 — FoodDiaryView re-scans the entire diary table 5–6× per render (Calendar-bucketed)
- **Type:** Performance · **Severity:** High · **Confidence:** Confirmed
- **Location:** `tracklifts/Features/Food/FoodDiaryView.swift:44-49` (`dayEntries`, `entries(for:)`), `:51-53` (`previousDayEntries`), `:67`, `:71-72` (`mealSection` ×4 → `:341`).
- **Description:** `allEntries` (`:30`) is an unbounded `@Query`. `body` correctly hoists `dayEntries`/`total` once (`:57-58`) — but `ForEach(Meal.allCases)` calls `mealSection(meal)` 4×, each calling `entries(for:)` (`:47`) which **re-derives `dayEntries` from scratch** (`:45`, full-table `Calendar.isDate(_:inSameDayAs:)` filter). That's 4 more full scans on top of the hoisted one, plus `previousDayEntries` (`:51`) is a 6th full scan whenever the current day is empty (`:67`, the common case on a fresh day). `Calendar.current` is re-fetched in each closure.
- **Impact:** ~5–6 × O(all-time entries) `Calendar` comparisons per render. At ~1 year of logging (thousands of entries) that's tens of thousands of `Calendar.isDate` calls on the main thread for every day-navigation/water-add/goal-change re-render.
- **Fix:** Compute the day slice once and group by meal in a single pass — `Dictionary(grouping: dayEntries) { $0.meal }` — and thread each meal's array into `mealSection`; drop `entries(for:)`'s internal re-derivation. Cache `let cal = Calendar.current`. `DiaryEntry.date` is already start-of-day (`Food.swift:121`), so the per-entry `isDate(inSameDayAs:)` can be a plain `==` against `startOfDay(for: day)`. Collapses 6 scans → 1.

---

### PERF-4 — LogWorkoutView recomputes `previousEntry`/`allTimeBest` over full session history per exercise, on every keystroke
- **Type:** Performance · **Severity:** High · **Confidence:** Firm (specialist-traced; not orchestrator-re-verified)
- **Location:** `tracklifts/Features/Log/LogWorkoutView.swift:188-200` (`lastPerformance`, `progressDelta`), `:246-307` (`previousEntry`, `allTimeBestBefore`); `allSessions` is the unbounded `@Query` at `:22`.
- **Description:** Each exercise section computes `previousEntry` **twice** (for `lastPerformance` and `progressDelta`), each call re-filtering and **re-sorting the entire `allSessions` history**; `isNewPersonalRecord` adds another full scan via `allTimeBestBefore`. This view's `body` re-evaluates on **every keystroke** into a reps/weight field (the `@Bindable session` set mutation propagates), so at K exercises and S prior sessions a single digit typed costs ~O(K × S log S × sets).
- **Impact:** The most keystroke-sensitive screen in the app; typing in a set field re-sorts the whole workout history many times per character. Janky set logging for established users.
- **Fix:** Compute `previousEntry(for:)` once per exercise and reuse for both footers; hoist the `allSessions.filter{isBefore}.sorted{...}` out of the per-exercise loop into one `body`-level `let`; compute `allTimeBestBefore` in the same single pass. Ideally these "last time / PR" values depend only on *prior* sessions, so derive them into `@State` when `allSessions.count` changes rather than on text edits.

---

### BUG-2 — `SpeechCapture` recognition-task completion handler is re-entrant into `stop()` after cancel
- **Type:** Bug · **Severity:** Medium · **Confidence:** Firm
- **Location:** `tracklifts/Features/Capture/SpeechCapture.swift:94-102` (handler), `:53-62` (`stop`).
- **Description:** The recognition result handler hops to the MainActor and calls `self.stop()` when `finished`. Manual `stop()` cancels the task, which fires the handler *again* with an error → schedules another `stop()`. Idempotent enough not to crash (optionals already nil), but it re-deactivates `AVAudioSession` a second time and can land a late transcript write on a torn-down capture.
- **Impact:** Redundant audio-session deactivation (can briefly disturb other audio) + wasted late write. Not a crash.
- **Trigger:** Start listening, then stop/dismiss while a partial result is pending.
- **Fix:** Gate the handler on current state so it no-ops after stop: in the `Task { @MainActor }` body, `guard let self, self.status == .listening else { return }` before mutating/`stop()`. Manual `stop()` sets `.idle` first → the late callback is ignored.

---

### BUG-3 — CaptureView shares one `analyzeTask` handle between the text and photo flows; one silently cancels the other
- **Type:** Bug · **Severity:** Medium · **Confidence:** Firm
- **Location:** `tracklifts/Features/Capture/CaptureView.swift:39` (single `@State analyzeTask`), `:274-289` (text), `:330-342` (photo), `:75` (`onClose`).
- **Description:** Both the text estimate and the photo analysis store into the same `analyzeTask`, and each begins with `analyzeTask?.cancel()`. Starting a photo analysis (or closing) while a text estimate is in flight cancels the text task; the text path returns on `Task.isCancelled` without falling back, with no user feedback.
- **Impact:** Mixed-mode usage silently aborts in-flight work — confusing "nothing happened" behavior. No crash/leak.
- **Trigger:** Type a meal → Estimate → before it returns, tap "Take a Photo".
- **Fix:** Use separate handles (`textTask`, `photoTask`); cancel only the same-mode task; `onDisappear`/`onClose` cancels both.

---

### BUG-4 — Gemini requests have no `timeoutInterval` (default 60s) — capture can hang
- **Type:** Bug · **Severity:** Medium · **Confidence:** Firm
- **Location:** `tracklifts/Data/FoodVisionProvider.swift:110-117` (`GeminiFood.send`).
- **Description:** The request is built and sent via `URLSession.shared.data(for:)` with **no `req.timeoutInterval`**, so it uses the 60s default while the photo path uploads a base64 JPEG. Contrast `OpenFoodFacts.get` which correctly sets `req.timeoutInterval = 12`. The UI shows "Reading your meal…" for the whole duration (user-cancellable, but up to 60s on a flaky link).
- **Impact:** Up to a 60s hang before failure on degraded networks; the photo path has no on-device fallback (the text path does).
- **Fix:** `req.timeoutInterval = 30` (multimodal warrants a bit more than OFF's 12s).

---

### BUG-5 — Onboarding timeline (`weeksToTarget`) and calorie delta (`dailyEnergyDelta`) use different rates
- **Type:** Bug · **Severity:** Medium · **Confidence:** Firm
- **Location:** `tracklifts/Models/NutritionPlan.swift:216-235`; surfaced together in `OnboardingView.swift:569`/`:589`.
- **Description:** `weeksToTarget` divides the weight gap by the **raw, unclamped** `weeklyRateKg`, while `dailyEnergyDelta` clamps the implied daily deficit/surplus to `[200,1000]`/`[75,500]`. When the chosen rate falls outside that band the two diverge: the displayed ETA assumes a pace the committed calorie target won't actually deliver (too-slow custom rate → ETA too long; too-aggressive → user misses the shown date).
- **Impact:** "Reach X in ~N weeks" is internally inconsistent with the calorie goal. Cosmetic, not a crash.
- **Fix:** Derive the ETA from the *realized* (clamped) rate: `realizedWeeklyKg = abs(dailyEnergyDelta(...)) * 7 / kcalPerKg`, feed that into `weeksToTarget`. Or surface the clamp in the UI.

---

### BUG-6 — Open Food Facts text search has no cancellation tied to query churn
- **Type:** Performance (resilience) · **Severity:** Medium · **Confidence:** Tentative (depends on call site)
- **Location:** `tracklifts/Data/OpenFoodFacts.swift:31-45`, `:49-63`.
- **Description:** `search` awaits `cgi/search.pl` (the heavy OFF endpoint, `page_size=25`) with a 12s timeout but **no `Task.checkCancellation()`** after the await. If the caller starts a `Task` per keystroke without cancelling the prior one, superseded requests run to completion and stale results can land last. (The local catalog search is correctly debounced/limited — this is the separate *remote* path.)
- **Impact:** Redundant in-flight requests to the slowest OFF endpoint; possible stale-result ordering.
- **Fix:** Verify the call site cancels the previous `Task` before reassigning; add `try? Task.checkCancellation()` (or `if Task.isCancelled { return [] }`) after the await, before decoding.

---

### PERF-5 — `recentFoods` walks an unbounded all-time `@Query` in a computed property (2 copies)
- **Type:** Performance · **Severity:** Medium · **Confidence:** Confirmed
- **Location:** `tracklifts/Features/Food/FoodSearchView.swift:96-105` (and `:31` unbounded `@Query`); duplicate in `tracklifts/Features/Food/RecipeEditorView.swift:271-280` (`:265`).
- **Description:** `recentEntries` is an unbounded `@Query` (every `DiaryEntry` ever). `recentFoods` loops it, faulting `entry.food` relationships until 8 distinct foods, and re-runs on every body evaluation (every keystroke in the add-food sheet). Bounded to 8 outputs but scans until 8 distinct are found.
- **Impact:** O(total diary entries) materialized + O(k) relationship faults per render; grows with history.
- **Fix:** Bound the query (`fetchLimit ≈ 200` via an initialized `@Query(FetchDescriptor)`) or compute `recentFoods` once into `@State` in `.task`, not in a per-keystroke computed property.

---

### PERF-6 — MicronutrientPanelView re-decodes the whole day's diary per row (~30×)
- **Type:** Performance · **Severity:** Medium · **Confidence:** Confirmed
- **Location:** `tracklifts/Features/Food/MicronutrientPanelView.swift:21-23` (`total`), `:84` (`total[n]` per row).
- **Description:** `total` (computed) filters the unbounded `allEntries` and runs `DiaryMath.total`, JSON-decoding each entry's `NutrientVector`. It is referenced by ~30 `MicroPanelRow`s via `total[n]` — and because it's not hoisted, each subscript **re-evaluates the whole property**, re-decoding the day's entries 30+ times per render.
- **Impact:** On a heavy logging day (~25 entries) ~750 JSON decodes per render; re-renders on any micronutrient `@AppStorage` target edit.
- **Fix:** Hoist `let total = self.total` once in `body` and pass `total[n]` into each row (the row already takes the value — just compute the property once).

---

### PERF-7 — NutrientTrendView.points recomputes the full-history decode/bucket/sort 3× per render
- **Type:** Performance · **Severity:** Medium · **Confidence:** Confirmed
- **Location:** `tracklifts/Features/Food/NutrientTrendView.swift:33-45` (`points`); referenced at `:57`, `:110-111`, `:128`.
- **Description:** `points` iterates all diary entries (unbounded `@Query`), JSON-decodes `nutrients[selected]` per entry, buckets by `startOfDay`, maps, sorts, filters by window — and is a computed property referenced 3× per render, so the whole O(N) decode runs 3×. Re-renders on every nutrient/range change (the screen's core interactions).
- **Impact:** ~3 × O(all-time entries) JSON decodes per render; at a year of data, thousands → tens of thousands of decodes per interaction.
- **Fix:** Hoist `let pts = points` once and pass into `summaryRow`/`chart`. Better: decode each entry's vector once into an all-nutrient per-day cache, recomputed only when `entries.count` changes.

---

### PERF-8 — TodayView re-decodes `eaten` and re-filters `weekSessions` multiple times per render
- **Type:** Performance · **Severity:** Medium · **Confidence:** Confirmed
- **Location:** `tracklifts/Features/Today/TodayView.swift:35-53`.
- **Description:** `eaten` (`:38`) JSON-decodes today's entries and is referenced ~4× un-memoized in `nutritionSection`; `weekSessions` (`:49`) filters all sessions and is referenced 3×; `latestWeight` (`:45`) re-sorts the full (already-sorted) weights array each access.
- **Impact:** Bounded to today/this-week so smaller N, but trivially avoidable repeated decode/filter on a frequently-rendered tab.
- **Fix:** Hoist `let eaten = self.eaten`, `let week = weekSessions` once in `body`; use `weights.last?.weight` (the `@Query` is date-sorted) instead of re-sorting.

---

### BUG-7 — HealthKit marks itself "connected" even when the user denies permission
- **Type:** Bug · **Severity:** Low · **Confidence:** Firm
- **Location:** `tracklifts/Shared/HealthKitManager.swift:66-77`.
- **Description:** `requestAuthorization` sets `connectedKey = true`/`isAuthorized = true` on the non-throwing path, but `HKHealthStore.requestAuthorization` **does not throw on denial**. A user who taps "Don't Allow" still shows "Connected" while writes silently no-op (`store.save` errors are `try?`-swallowed at `:167`).
- **Impact:** Misleading "Connected" state; silent no-op dietary writes. (The cross-actor `ModelContext` isolation around HK is otherwise correct.)
- **Fix:** After the request, gate on write status: `let granted = writeTypes.allSatisfy { store.authorizationStatus(for: $0) == .sharingAuthorized }` and set the flags from `granted`.

---

### BUG-8 — `Completeness.score` penalty iterates the male/30 `targetable` set, not the user's sex/age
- **Type:** Bug · **Severity:** Low · **Confidence:** Firm
- **Location:** `tracklifts/Models/Completeness.swift:37-41`.
- **Description:** The adequacy half is correctly sex/age-filtered, but the stay-under penalty loop iterates `NutritionGoals.targetable` (a fixed `sex: .male, age: 30` membership list, `Food.swift:203`). Harmless today because all four stay-under limits are sex/age-independent — but a latent hazard the moment a sex/age-varying ceiling is added.
- **Impact:** None today; latent wrong-membership bug.
- **Fix:** Filter the user-specific set on both halves, e.g. by `limitKind == .stayUnder && target(sex:age:) != nil`.

---

### BUG-9 — `onlineResults` keyed by array index (`id: \.offset`)
- **Type:** Bug · **Severity:** Low · **Confidence:** Firm
- **Location:** `tracklifts/Features/Food/FoodSearchView.swift:142`.
- **Description:** `ForEach(Array(onlineResults.enumerated()), id: \.offset)` keys rows by position; on each debounced online refresh the list is replaced, so SwiftUI reuses rows by index. Harmless here (rows are immutable value displays, list replaced atomically) but defeats diffing/animation and is the index-identity anti-pattern. Elsewhere the code correctly uses `\.persistentModelID`.
- **Fix:** Give `RemoteFood` a stable `Identifiable` id (barcode or name+brand hash) and `ForEach(onlineResults)`.

---

### BUG-10 — `BodyWeightEntry` is not normalized to start-of-day like `DiaryEntry`/`WaterEntry`
- **Type:** Bug · **Severity:** Low · **Confidence:** Tentative
- **Location:** `tracklifts/Models/BodyWeight.swift:23-28`; `Profile.apply` inserts raw `.now` (`NutritionPlan.swift:309`).
- **Description:** Two of three time-series models self-normalize their `date` to `startOfDay`; `BodyWeightEntry` relies on callers, and one caller passes a raw timestamp. "Current weight" is unaffected (it sorts by `(date, createdAt)`), but any view grouping body-weight by exact `date` would split same-day weigh-ins.
- **Fix:** Normalize in `BodyWeightEntry.init` for consistency, or pass `startOfDay(for: .now)` in `Profile.apply`.

---

### BUG-11 — No retry/backoff on Gemini/OFF transient failures
- **Type:** Performance (resilience) · **Severity:** Low · **Confidence:** Firm
- **Location:** `tracklifts/Data/FoodVisionProvider.swift:117-119`; `tracklifts/Data/OpenFoodFacts.swift:54-62`.
- **Description:** Any non-2xx is terminal; a transient 429/503 fails the whole capture. The photo path has no fallback (text path falls back to on-device matching).
- **Fix:** One bounded retry with jittered backoff on 429/5xx for the Gemini call (and optionally OFF).

---

### PERF-9 — ExerciseProgressView recomputes `relevantSessions` + series 3× per render
- **Type:** Performance · **Severity:** Low–Medium · **Confidence:** Confirmed
- **Location:** `tracklifts/Features/Progress/ExerciseProgressView.swift:32-46`, referenced `:73`,`:89`,`:110`.
- **Description:** `points` (→ `relevantSessions` filter + full `ProgressCalculator.series`) is referenced 3× per render and recomputed each time; re-renders on metric/range toggles (the core interactions). Bounded to one exercise but trivially avoidable.
- **Fix:** `let pts = points` once in `body`; thread into `summaryRow`/`chart`.

---

### PERF-10 — `CloudPrefs.pushLocal` calls `synchronize()` on every UserDefaults change
- **Type:** Performance · **Severity:** Low · **Confidence:** Firm
- **Location:** `tracklifts/Shared/CloudPrefs.swift:57-62`, `:110-127`.
- **Description:** A `UserDefaults.didChangeNotification` observer runs the full whitelist comparison on every defaults write and calls `store.synchronize()` immediately when a mirrored value changes — so a continuous `@AppStorage` writer (goal slider) flushes KVS per tick. Apple advises against routine `synchronize()`.
- **Fix:** Debounce `pushLocal` (~400ms) and drop the explicit `synchronize()` (KVS auto-syncs; reserve it for background `scenePhase`).

---

### PERF-11 — `FoodSearch` re-lowercases/re-tokenizes the query for every candidate during ranking
- **Type:** Performance · **Severity:** Low · **Confidence:** Confirmed
- **Location:** `tracklifts/Data/FoodSearch.swift:27-41`; amplified by `CaptureMatcher.confidentMatch` (`CaptureMatcher.swift:88-95`, `limit: 200`).
- **Description:** The SQLite predicate + `fetchLimit` design is correct; the residual is `matchRank` recomputing `query.lowercased()` inside the `sorted` comparator (O(n log n) times) and `confidentMatch` re-tokenizing the query for up to 200 rows. Small in absolute terms.
- **Fix:** Precompute `lq`/`queryTokens` once before sorting/filtering and capture them.

---

### PERF-12 — Gallery/JPEG image work runs on the main actor
- **Type:** Performance · **Severity:** Low · **Confidence:** Tentative
- **Location:** `tracklifts/Features/Capture/CaptureView.swift:299-310`, `:368-376` (`prepareJPEG`).
- **Description:** The capture `Task` inherits the MainActor (whole-target default), so `UIImage(data:)`, the `UIGraphicsImageRenderer` EXIF-stripping redraw, and `jpegData` run on the main thread — tens of ms for a 12MP source, hitching as the review overlay animates. (`BarcodeScannerView.barcode(in:)` correctly does its Vision work `nonisolated`.)
- **Fix:** Move decode/resize/encode into a `nonisolated static` helper `await`-ed off-main; keep only the final UI assignment on the actor. Preserve the EXIF-stripping redraw.

---

### PERF-13 — `usda-import.swift` accumulates all foods' nutrients before applying `--limit` (build tool only)
- **Type:** Performance · **Severity:** Low · **Confidence:** Confirmed
- **Location:** `tools/usda-import.swift:166-189`.
- **Description:** `perFood` builds nutrients for every kept food across the big CSV before `--limit` slices to N. This is an offline developer tool ("NOT part of the app target") that never runs on device, and the full scan is inherent to the "most-data-complete, span A–Z" selection — so no action needed; noted for completeness.

---

## 4. Summary table

| ID | Type | Title | Severity | Confidence | Location |
|---|---|---|---|---|---|
| BUG-1 | Bug | Unclamped numeric `TextField` → raw `Int` trap (3 sites) | High | Confirmed | `Food.swift:164`; `FoodSearchView.swift:569`; `OnboardingView.swift:489` |
| PERF-1 | Perf | First-launch seed decode+insert on main actor | High | Confirmed | `FoodSeedManager.swift:32-51` |
| PERF-2 | Perf | ProgressOverview per-render O(E×S×sets) series recompute | High | Confirmed | `ProgressOverviewView.swift:140-167` |
| PERF-3 | Perf | FoodDiary 5–6× full-table rescan per render | High | Confirmed | `FoodDiaryView.swift:44-54,67` |
| PERF-4 | Perf | LogWorkout per-keystroke history scan+sort | High | Firm | `LogWorkoutView.swift:188-200,246-307` |
| BUG-2 | Bug | SpeechCapture stop() re-entrancy after cancel | Medium | Firm | `SpeechCapture.swift:94-102` |
| BUG-3 | Bug | Shared `analyzeTask` cancels cross-flow | Medium | Firm | `CaptureView.swift:39` |
| BUG-4 | Bug | Gemini request missing timeout | Medium | Firm | `FoodVisionProvider.swift:110-117` |
| BUG-5 | Bug | Timeline vs calorie-delta rate mismatch | Medium | Firm | `NutritionPlan.swift:216-235` |
| BUG-6 | Bug | OFF search not cancellable on query churn | Medium | Tentative | `OpenFoodFacts.swift:31-63` |
| PERF-5 | Perf | `recentFoods` unbounded `@Query` scan (×2) | Medium | Confirmed | `FoodSearchView.swift:96-105`; `RecipeEditorView.swift:271-280` |
| PERF-6 | Perf | Micronutrient panel re-decodes per row (~30×) | Medium | Confirmed | `MicronutrientPanelView.swift:21-23,84` |
| PERF-7 | Perf | NutrientTrend.points recomputed 3× | Medium | Confirmed | `NutrientTrendView.swift:33-45` |
| PERF-8 | Perf | TodayView un-memoized `eaten`/`weekSessions` | Medium | Confirmed | `TodayView.swift:35-53` |
| BUG-7 | Bug | HealthKit "connected" on denial | Low | Firm | `HealthKitManager.swift:66-77` |
| BUG-8 | Bug | Completeness penalty uses male/30 membership | Low | Firm | `Completeness.swift:37-41` |
| BUG-9 | Bug | `onlineResults` keyed by array index | Low | Firm | `FoodSearchView.swift:142` |
| BUG-10 | Bug | BodyWeightEntry not start-of-day normalized | Low | Tentative | `BodyWeight.swift:23-28` |
| BUG-11 | Bug | No retry/backoff on Gemini/OFF | Low | Firm | `FoodVisionProvider.swift:117`; `OpenFoodFacts.swift:54-62` |
| PERF-9 | Perf | ExerciseProgress points recomputed 3× | Low–Med | Confirmed | `ExerciseProgressView.swift:32-46` |
| PERF-10 | Perf | CloudPrefs `synchronize()` per defaults write | Low | Firm | `CloudPrefs.swift:57-62,110-127` |
| PERF-11 | Perf | FoodSearch re-lowercases query per comparator | Low | Confirmed | `FoodSearch.swift:27-41` |
| PERF-12 | Perf | Gallery/JPEG work on main actor | Low | Tentative | `CaptureView.swift:299-310,368-376` |
| PERF-13 | Perf | usda-import builds all before `--limit` (tool) | Low | Confirmed | `tools/usda-import.swift:166-189` |

## 5. Quick wins (low effort, high value)

- **Kill the crash class (BUG-1):** swap the ~3 raw `Int(x.rounded())` sinks to `x.rounded().safeInt` and clamp the grams/serving/weight `TextField`s to existing bounds. ~6 lines, removes 3 reachable crashes.
- **Hoist computed properties into `body`-level `let`s** (PERF-3, 6, 7, 8, 9): mechanical, low-risk, removes 2–6× repeated decode/scan on the hottest screens.
- **One-line Gemini timeout** (BUG-4): `req.timeoutInterval = 30`.
- **Stable `Identifiable` for `RemoteFood`** (BUG-9).
- **`.safeInt` consistency sweep** for the few remaining energy/goal display sites two lines from siblings that already use it: `TodayView.swift:129,137`, `FoodDiaryView.swift:188`, `CaptureMatcher.swift:172,179`.

## 6. Residual & follow-ups

- **No runtime profiling.** PERF magnitudes are static estimates; confirm PERF-1/2/3/4 with Instruments (Time Profiler) on a seeded device with a year of data. PERF-4 (LogWorkoutView) was specialist-traced but not orchestrator-re-verified line-by-line.
- **No compiler/analyzer pass run.** A `xcodebuild ... analyze` / warnings build (fresh sim id per `build-run-setup`) may surface additional leads — not run here to keep the review static. Available on request.
- **BUG-6 (OFF cancellation)** depends on the search call-site's `Task` management, which wasn't traced; verify the debounced caller cancels the prior task.
- **BUG-5 (timeline vs delta)** is a design-level consistency call — confirm intended UX before changing.
- **Device-only paths** (HealthKit reads, live barcode camera) couldn't be exercised statically; BUG-7's denial behavior is best confirmed on-device.

### Explicitly clean (examined, no issues)
- SwiftData iOS-17 to-many-on-uninserted-model crash class: **no violations** — all insert sites wire relationships from the to-one side after `insert` (`FoodSeedManager.insertPortions`, `CaptureConfirmSheet.persistEstimated`, `EditFoodView.attachPortion`, `RecipeEditorView`, `CloudDedup`, `WorkoutSession.repeated`).
- Cross-actor `ModelContext` safety, continuation single-resume (`SpeechCapture.requestPermissions`), camera/scanner teardown (`dismantleUIViewController`), retain cycles (weak captures throughout) — clean.
- Nutrition math: per-serving↔per-100g inverses, Atwater split, Epley 1RM, kg↔lb, water conversions, `Completeness` division guards, `safeInt` saturation — all correct.
- Food search core path (predicate + `fetchLimit` + debounce), `NutrientVector` shared coder reuse, denormalized `kcalPer100g`/snapshotted diary totals — already well-optimized.
