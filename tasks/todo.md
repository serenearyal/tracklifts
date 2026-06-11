# Task: numeric-field-to-top + Forearms / custom muscle groups

Plan: `~/.claude/plans/composed-cooking-clover.md` (approved 2026-06-10)

## Part 1 — Numeric field jumps to top of screen
- [x] Add `ScrollViewProxy.scrollFieldToTop(_:)` helper in `Shared/KeyboardSupport.swift`
- [x] LogWorkoutView: per-set `@FocusState`, ScrollViewReader, scroll set row to top
- [x] SettingsView: focus enum for 4 goal fields, scroll to top
- [x] FoodDiaryView (EditEntrySheet): grams focus, scroll macro+amount block to top
- [x] OnboardingView: change existing `.center` anchor → `.top` via helper
- [x] BodyWeightView: no change (field already top-pinned) — verified

## Part 2 — Forearms + custom muscle groups
- [x] MuscleGroup.swift: add `forearms` case (name/symbol/color)
- [x] MuscleGroup.swift: add `MuscleTag` resolver + `canonicalRaw` + `muscleTagsPresent`
- [x] Exercise.swift: add `var tag: MuscleTag`
- [x] Components.swift: `MuscleGlyph` takes `MuscleTag`
- [x] EditExerciseView: raw-string selection + "Add Custom Group" alert
- [x] ExerciseLibraryView: data-driven sections/filters
- [x] ExercisePickerView: data-driven sections/filters
- [x] Display migrations → `.tag` (ProgressOverview, ExerciseDetail, ExerciseProgress, SplitEditor, LogWorkout reorder)

## Verify
- [x] Clean build for iOS-17 target — **BUILD SUCCEEDED**, zero warnings (iPhone 17 / iOS 26.2 sim)

## Review (2026-06-10)

**Part 1 — focused numeric field now jumps to the top of the screen.**
New reusable `ScrollViewProxy.scrollFieldToTop(_:)` (KeyboardSupport.swift) — generalizes
the pattern already proven in onboarding: `withAnimation(.snappy) { scrollTo(id, anchor: .top) }`.
Wired into every typable numeric field:
- **Workout set logger** (the main complaint): `SetFieldFocus` enum keys reps/weight per set
  by `persistentModelID`; `body` now wraps the List in a `ScrollViewReader` and scrolls the
  focused set's row to the top. `SetRow` takes the focus binding.
- **Settings daily targets**: `GoalField` focus enum + `.id` per row; scrolls to top.
- **Food entry editor**: scrolls the macro+amount block (`.id("amount")` on `MacroPreview`)
  to the top, so the live macro readout stays visible just above the field.
- **Onboarding**: switched its existing `.center` anchor to the shared `.top` helper.
- **Body-weight sheet**: unchanged — its field is the hero pinned at the very top already.

**Part 2 — Forearms + custom muscle groups, no schema change.**
- Added built-in `forearms` (hand.raised.fill, orange).
- New `MuscleTag` (MuscleGroup.swift) resolves display name/symbol/color for a built-in
  **or** any custom string stored in `Exercise.muscleGroupRaw` (custom color = deterministic
  FNV hash → palette, stable across launches). `canonicalRaw(forInput:)` collapses typed
  names onto built-ins; `Collection<Exercise>.muscleTagsPresent` drives data-driven
  sections/filters. `Exercise.tag` is the display lens.
- `EditExerciseView`: muscle picker now lists built-ins + existing customs, plus an
  "Add Custom Group" alert; stores the raw string.
- Library + picker enumerate groups from data, so custom groups get their own colored
  section + filter chip automatically. All display sites migrated `.muscleGroup` → `.tag`.
- Storage stayed a `String` → CloudKit/iOS-17 safe (no model migration).

**Verification:** clean build for deployment target 17.0 on iPhone 17 / iOS 26.2, zero
warnings. Manual UI testing left to the user (convention).

**Revision (2026-06-10, user feedback):**
- Workout logger: scroll the **exercise card** (its name header + sets), not the bare set
  row, via `focusedEntryID` → its `LoggedExercise` section id.
- Last card wouldn't lift (nothing below to scroll into): add focus-gated bottom
  `contentMargins(500)` + defer the scroll a runloop.
- Settings: moved **iCloud Sync** card to the top.

**Simulator-verified fix (2026-06-10, user said "test it yourself"):**
Added `testKeyboardScrollPosition` (seeds a session, focuses set fields, screenshots).
Screenshots proved: (1) `scrollTo(.top)` parks the exercise **title under the transparent
nav bar** — that's the "blur"; (2) `.contentMargins(.top:)` is ignored by `scrollTo`
(70 vs 115 identical). **Fix: scroll the card with `anchor: .center`** — title lands crisp,
fully below the bar, upper-middle, field clear of the keyboard. Verified on Bench (1st) and
Squat (2nd) cards. Build green, zero warnings. Lesson + memory updated.
