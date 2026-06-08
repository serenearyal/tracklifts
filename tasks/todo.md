# TrackLifts — Build Plan

## Models (SwiftData)
- [ ] MuscleGroup enum (display, symbol, color)
- [ ] Exercise
- [ ] Split / SplitDay / SplitItem
- [ ] WorkoutSession / LoggedExercise / LoggedSet
- [ ] Metric helpers (1RM, volume, best set)

## Data
- [ ] Exercise seed library (~65 exercises)
- [ ] Seeding on first launch

## Shared
- [ ] Theme / colors
- [ ] Reusable components (cards, stat pills, empty states)
- [ ] Weight unit (AppStorage)

## Features
- [ ] App entry + ModelContainer + RootTabView
- [ ] Log: history list + new/edit session + inline set entry + exercise picker
- [ ] Exercises: library grouped by muscle, search, favorites, custom add, detail
- [ ] Splits: list + editor (days + exercises)
- [ ] Progress: charts (max weight / 1RM / volume), PRs, favorites overview

## Verify
- [x] xcodebuild succeeds for simulator (BUILD SUCCEEDED, iPhone 17 Pro / iOS 26.2)
- [x] App launches; empty states render
- [x] Seeding verified in store: 69 exercises across 7 groups
- [ ] UI smoke test drives all tabs + logging flow

## Enhancements (round 2)
- [x] Session-over-session delta on logging screen ("+3% vs last")
- [x] Time-range picker on charts (All / 90d / 30d) + windowed % change
- [x] Bold PR badge "🏆 New PR!" when a logged session beats the record
- [x] Fixed real bug: same-day sessions compared equal (DatePicker normalizes
      date to midnight) → added WorkoutSession.createdAt tiebreak in isBefore()
- [x] Added gated SampleData seeder (--seed-sample) + UI test, all passing

## Review
- All models, seed, shared components, and 4 feature areas built.
- Synchronized file group auto-included every new .swift file (no pbxproj edits).
- iOS 26.2 target → SwiftData + Swift Charts + new Tab API used directly.
</content>

## Redesign — "FORGE" dark theme (round 3)
- [x] Design system: Bebas Neue + Archivo (bundled, runtime-registered), ember palette, grain bg
- [x] Restyled all screens: Log, Exercises, Splits, Progress, detail, editor, pickers, settings
- [x] Custom components: ForgeCard, ScreenHeader, StatTile, EmberButton, TrendChip, glowing PR badge
- [x] Staggered appear animations, gradient charts, ranked records
- [x] Fixed nav bug (ScrollView+LazyVStack tap) and unbounded-width bug (ZStack-wrapped TabView)
- [x] Full UI test suite green; all screens verified via screenshots

## Intuitive progress + gestures (round 4)
- [x] Progress tab scope selector: Tracked (all logged, zero setup) / Favorites / per-Split
- [x] Split scope shows day-grouped trend cards (no favoriting needed)
- [x] Bulk favorite: "Favorite all lifts in split" + per-day ⋯ menu in split editor
- [x] Bulk favorite from Splits list (context menu) too
- [x] Gestures: tap split exercise → progress; leading-swipe to favorite; Repeat Workout on a session; richer exercise context menu
- [x] SampleData seeds a PPL split; UI test covers scope + bulk-favorite; suite green

## Publish-readiness (round 5) — logo, reordering, bodyweight

### Logo / App Icon  (agent, parallel)
- [ ] CoreGraphics generator → 1024² PNGs: primary, dark, tinted, + transparent mark
- [ ] Wire AppIcon.appiconset/Contents.json; add Logo imageset
- [ ] In-app brand lockup shown in Settings → About
- [ ] Verify: Read PNG + simulator home-screen screenshot shows the icon

### Reorder while logging (+ everywhere it makes sense)
- [ ] Reusable `ReorderSheet` + `ReorderRequest` (always-on edit mode, FORGE styled)
- [ ] LogWorkoutView: reorder exercises (toolbar)
- [ ] SplitEditorView: reorder days + reorder exercises within a day (menus)

### Bodyweight exercises (pull-ups, sit-ups, …)
- [ ] `Exercise.isBodyweight` (+ seed obvious calisthenics) + idempotent backfill
- [ ] `BodyMetrics.current` body-weight setting + Settings field
- [ ] `LoggedSet.effectiveWeight` = bodyweight + added (graceful fallback to reps)
- [ ] Logging UI: reps-hero row, optional "+ added", BW badge
- [ ] `Exercise.primaryMetric` (Best Reps when pure bodyweight w/o body weight)
- [ ] Progress (charts, trend cards, PRs, detail hero) adapt; set summaries "12 reps"
- [ ] EditExerciseView bodyweight toggle for custom exercises

### Verify
- [ ] xcodebuild (iPhone 17 Pro, iOS 26.2 — id EC286661-…) BUILD SUCCEEDED
- [ ] UI test extended: reorder + bodyweight logging + screenshots; export & eyeball
- [ ] README + memory updated
