# TrackLifts

A simple, non-bloated iOS app for tracking gym lifts and seeing your progress
clearly over time. No timers, no social feed — just log what you did and watch
the numbers go up.

## Features

- **Exercise library** — ~70 exercises pre-organized by muscle group (Chest,
  Back, Shoulders, Biceps, Triceps, Legs, Core). Search, filter, add your own
  custom exercises, and ⭐️ favorite the lifts you care about.
- **Splits** — build your own routine (e.g. Push / Pull / Legs) with chosen
  exercises per day. Pull a whole day's exercises into a workout in one tap.
- **Manual logging** — record a session by hand: reps × weight for each set.
  Every exercise shows *last time*'s numbers so you know what to beat.
- **Progress charts** — per-exercise trends for Estimated 1RM, Top Weight,
  Volume, and Best Reps. The Progress tab surfaces recent personal records and
  favorite-lift sparklines at a glance.
- **kg / lb** toggle in Settings.

## How "progress" is measured

Progress isn't just heavier weight — doing more reps at the same weight counts
too. The app uses the **Epley estimated 1RM** (`weight × (1 + reps/30)`) as a
single strength number that rewards both, alongside raw top weight and total
volume (Σ reps × weight).

## Tech

- SwiftUI + **SwiftData** (persistence) + **Swift Charts** (visualization)
- 100% native, zero third-party dependencies
- Target: iOS 26.2

## Project layout

```
tracklifts/
  Models/        Exercise, Split/Day/Item, WorkoutSession/LoggedExercise/LoggedSet
  Data/          ExerciseLibrary (seed catalog) + SeedManager
  Shared/        WeightUnit, reusable components, ProgressMetrics (1RM/volume math)
  Features/
    Log/         workout history, the logging editor, exercise & split pickers
    Exercises/   library, detail (with progress + history), add/edit custom
    Splits/      split list + editor
    Progress/    overview (stats, PRs, favorites), per-exercise chart, settings
```

The Xcode project uses a synchronized file group, so any `.swift` file added
under `tracklifts/` is automatically included in the build.
