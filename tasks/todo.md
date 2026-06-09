# Task: IA restructure — 5 tabs → Today · Train · Food · Progress

Plan: `~/.claude/plans/enumerated-discovering-newt.md` (2026-06-09)

Consolidate the tab bar so the app scales with roadmap Phases 2–5. New Today
dashboard (first tab), Train merges Log+Library, Settings demoted to a gear
pushed from Today.

## Checklist

- [x] 1. `Models/Workout.swift`: add `WorkoutSession.blank(in:)` + `.repeated(from:in:)` factories
- [x] 2. `Models/Nutrition.swift`: add `Meal.defaultForNow`
- [x] 3. `Shared/Components.swift`: move `MacroProgressBar` + `MacroStat` in
- [x] 4. `FoodDiaryView.swift`: drop moved structs + `defaultMealForNow`
- [x] 5. `WorkoutHistoryView.swift`: embeddable (no NavigationStack/background), light header, use factories
- [x] 6. NEW `Features/Train/TrainView.swift`: 3-segment switcher (Log | Splits | Exercises)
- [x] 7. DELETE `Features/Library/LibraryView.swift`; fix stale comments in siblings
- [x] 8. NEW `Features/Today/TodayView.swift`: dashboard (nutrition / training / weight / week)
- [x] 9. `SettingsView.swift`: remove own NavigationStack (now pushed from Today)
- [x] 10. `ContentView.swift`: AppTab enum, 4-tab TabView(selection:)
- [x] 11. `trackliftsUITests.swift`: update tab/segment strings (compile only, don't run)
- [x] 12. Docs: roadmap changelog entry + review section here
- [x] Build passes (`build-for-testing` on fresh iPhone 17 sim id)

## Review (2026-06-09)

**Tab bar: Today · Train · Food · Progress** (was Log · Food · Library · Progress · Settings).

- **Today** (`Features/Today/TodayView.swift`, new): date header + gear → pushes
  `SettingsView`; nutrition card (kcal vs goal, LEFT/OVER, macro bars — tap jumps to
  Food tab via `AppTab` binding, + presents `FoodSearchView`); training card
  (`EmberButton` "Log Today's Workout" + ghost "Repeat Last Workout" via the new
  `WorkoutSession` factories, or today's `SessionRow`s once logged); body-weight card
  (`BodyWeightSummaryCard` → `BodyWeightView`, + presents `AddBodyWeightSheet`,
  `BodyMetrics.refreshCurrent` kept in sync via `onChange`); this-week `StatTile` strip.
- **Train** (`Features/Train/TrainView.swift`, new): `LibraryView` pattern generalized to
  3 segments — Log (refactored embeddable `WorkoutHistoryView` with sibling-style
  `Eyebrow` + plus-circle header) | Splits | Exercises. `LibraryView.swift` deleted;
  segment ids now `trainSegment.*`.
- **Settings**: own `NavigationStack` removed (it's a pushed destination now), content
  untouched.
- Reused throughout: `MacroProgressBar`/`MacroStat` (moved to `Shared/Components.swift`),
  `SessionRow`, `Meal.defaultForNow` (extracted to model), session clone logic
  (extracted to `WorkoutSession.repeated(from:in:)`).

**Verification:** `build-for-testing` clean (zero warnings) on iPhone 17 / iOS 26.2 sim
(deployment target 17.0, classic `TabView(selection:) + .tabItem` API only);
`trackliftsTests` logic suite **TEST SUCCEEDED**. UI suite updated to the new tab/segment
names but intentionally not run (flaky; manual testing preferred).

**Manual smoke checklist:**
1. Launch → Today shows date header, 0-kcal nutrition card, Log Today's Workout, weight card.
2. Today: + on Nutrition → food search sheet; logging a food updates the card; card tap → Food tab.
3. Today: Log Today's Workout → New Workout sheet; after Done the session appears as a card; + still available in the Training row.
4. Today: Repeat Last Workout clones the most recent session.
5. Today: + on Body Weight → weigh-in sheet; card updates; card tap → full Body Weight log.
6. Gear → Settings pushes (back button returns); Body Weight + Recalculate still work from there.
7. Train tab: Log | Splits | Exercises segments all render; history push/edit, repeat/delete context menu, split editor, exercise detail all behave as before.
8. Food and Progress tabs unchanged; onboarding gate unchanged.

**Follow-up (not done here):** `website/` marketing copy still describes the old
Log/Library tab layout; refresh screenshots + copy when the new IA settles.
