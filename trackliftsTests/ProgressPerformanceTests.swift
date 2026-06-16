//
//  ProgressPerformanceTests.swift
//  trackliftsTests
//
//  Performance benchmark for the progress-series hot path that PERF-2/4/9
//  optimized — the "Progress" tab's per-render cost.
//
//  Two `measure {}` blocks bracket the same screen-load work:
//
//    • testProgressOverview_Optimized  — the CURRENT single-pass approach:
//      build the [exerciseID: series] map ONCE over the reversed sessions
//      (mirrors `ProgressOverviewView.trackedSeries`), then derive the PR list
//      and every trend card's latest/trend value straight from that map.
//
//    • testProgressOverview_Naive      — the OLD per-render approach this work
//      removed: `ProgressCalculator.series(...)` was rebuilt PER exercise for
//      `recentPRs`, AGAIN per trend card, and the `trackedExercises` "ever
//      logged" scan was recomputed several times per render. Because `series`
//      is itself O(sessions × sets), the screen paid ≈ O(exercises × sessions
//      × sets) on EVERY render — and SwiftUI re-rendered the whole screen on
//      each scope-chip tap (Tracked / Favorites / each split), so a single tap
//      did this work E× over.
//
//  The ratio between the two times is the multiple PERF-2/4/9 took out of the
//  Progress tab. Absolute numbers are machine-relative (XCTest reports them as
//  the regression baseline), but the *gap* between optimized and naive is the
//  headline result and is stable across machines.
//

import XCTest
import SwiftData
@testable import tracklifts

@MainActor
final class ProgressPerformanceTests: XCTestCase {

    // MARK: Synthetic scale
    //
    // Tuned to the scale where the old per-render cost bites: ~30 tracked
    // exercises × ~200 sessions × ~4 sets per logged exercise. The naive path's
    // E×(sessions×sets) work grows with all three, so this is enough to make the
    // optimized/naive gap obvious without making the suite slow to set up.

    private let exerciseCount = 30
    private let sessionCount = 200
    private let exercisesPerSession = 4
    private let setsPerExercise = 4

    // MARK: Fixture

    /// An in-memory store plus a fully wired synthetic training history,
    /// returned oldest→newest is irrelevant (the view queries reverse-by-date);
    /// `sessions` here is newest→first to mirror the `@Query(order: .reverse)`.
    private func makeHistory() throws -> (context: ModelContext,
                                          exercises: [Exercise],
                                          sessions: [WorkoutSession]) {
        // Mirror the model list used by the other test fixtures.
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
            WaterEntry.self, SavedMeal.self, SavedMealItem.self,
            Recipe.self, RecipeIngredient.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))

        // ~30 weighted exercises. Weighted (not bodyweight) so `primaryMetric`
        // is `.oneRepMax` and every set contributes a non-trivial series value.
        var exercises: [Exercise] = []
        for i in 0..<exerciseCount {
            let ex = Exercise(name: "Exercise \(i)", muscleGroup: .chest)
            context.insert(ex)
            exercises.append(ex)
        }

        // ~200 sessions spread one day apart, each touching a rotating window of
        // exercises with ~4 sets each. Build strictly from the to-one side after
        // insert (iOS 17: never append to a to-many on an un-inserted model),
        // exactly like `WorkoutSession.repeated`.
        let now = Date()
        var sessions: [WorkoutSession] = []
        for s in 0..<sessionCount {
            let date = now.addingTimeInterval(Double(-s) * 86_400)  // 1 day apart
            let session = WorkoutSession(date: date, title: "Day \(s % 4)")
            context.insert(session)

            for e in 0..<exercisesPerSession {
                let exercise = exercises[(s + e) % exerciseCount]
                let entry = LoggedExercise(exercise: exercise, order: e)
                entry.session = session            // to-one side after insert
                context.insert(entry)

                for setIdx in 0..<setsPerExercise {
                    // Mild progression over time so series have real variation
                    // and `recentPRs` finds genuine bests (newest sessions heaviest).
                    let weight = 40.0 + Double(setIdx) * 5.0 + Double(sessionCount - s) * 0.1
                    let reps = 5 + (setIdx % 4)
                    let set = LoggedSet(reps: reps, weight: weight, order: setIdx)
                    set.loggedExercise = entry      // to-one side after insert
                    context.insert(set)
                }
            }
            sessions.append(session)
        }
        try context.save()

        // Newest-first, matching `@Query(sort: \WorkoutSession.date, order: .reverse)`.
        sessions.sort { $0.date > $1.date }
        return (context, exercises, sessions)
    }

    /// The "ever-logged, most-recently-trained first" scan — a verbatim copy of
    /// `ProgressOverviewView.trackedExercises`. The naive path recomputes this
    /// several times per render; the optimized path computes it once.
    private func trackedExercises(_ sessions: [WorkoutSession]) -> [Exercise] {
        var seen = Set<PersistentIdentifier>()
        var result: [Exercise] = []
        for session in sessions {
            for entry in session.orderedEntries {
                guard let ex = entry.exercise, entry.setCount > 0 else { continue }
                if seen.insert(ex.persistentModelID).inserted { result.append(ex) }
            }
        }
        return result
    }

    // MARK: Optimized — single pass (current behavior)

    func testProgressOverview_Optimized() throws {
        let (_, _, sessions) = try makeHistory()

        measure {
            // ── Shared inputs computed ONCE (mirrors `ProgressOverviewView.body`).
            let tracked = trackedExercises(sessions)
            let ordered = Array(sessions.reversed())

            // ── ONE series map for the whole screen (mirrors `trackedSeries`).
            var series: [PersistentIdentifier: (metric: ProgressMetric, points: [ProgressPoint])] = [:]
            series.reserveCapacity(tracked.count)
            for exercise in tracked {
                let metric = exercise.primaryMetric
                series[exercise.persistentModelID] = (metric,
                    ProgressCalculator.series(for: exercise, metric: metric, in: ordered))
            }

            // ── Recent PRs derived from the map, no recompute (mirrors `recentPRs`).
            var prs: [(exercise: Exercise, value: Double, date: Date)] = []
            for exercise in tracked {
                guard let entry = series[exercise.persistentModelID] else { continue }
                let points = entry.points
                guard points.count >= 2, let best = points.map(\.value).max(), best > 0,
                      let last = points.last, last.value >= best - 0.001 else { continue }
                prs.append((exercise, best, last.date))
            }
            let topPRs = prs.sorted { $0.date > $1.date }.prefix(5)

            // ── Every trend card reuses its precomputed points (the latest value
            //    + trend chip the card renders), no per-card `series` call.
            var cardChecksum = 0.0
            for exercise in tracked {
                let points = series[exercise.persistentModelID]?.points ?? []
                if let latest = points.last?.value { cardChecksum += latest }
                if let trend = ProgressCalculator.trendPercent(points) { cardChecksum += trend }
            }

            // Touch the outputs so the optimizer can't elide the work.
            XCTAssertGreaterThanOrEqual(topPRs.count, 0)
            XCTAssertFalse(cardChecksum.isNaN)
        }

        // Same workload, with a CLI-visible per-iteration average.
        benchMillis("Progress.optimized") {
            let tracked = trackedExercises(sessions)
            let ordered = Array(sessions.reversed())

            var series: [PersistentIdentifier: (metric: ProgressMetric, points: [ProgressPoint])] = [:]
            series.reserveCapacity(tracked.count)
            for exercise in tracked {
                let metric = exercise.primaryMetric
                series[exercise.persistentModelID] = (metric,
                    ProgressCalculator.series(for: exercise, metric: metric, in: ordered))
            }

            var prs: [(exercise: Exercise, value: Double, date: Date)] = []
            for exercise in tracked {
                guard let entry = series[exercise.persistentModelID] else { continue }
                let points = entry.points
                guard points.count >= 2, let best = points.map(\.value).max(), best > 0,
                      let last = points.last, last.value >= best - 0.001 else { continue }
                prs.append((exercise, best, last.date))
            }
            let topPRs = prs.sorted { $0.date > $1.date }.prefix(5)

            var cardChecksum = 0.0
            for exercise in tracked {
                let points = series[exercise.persistentModelID]?.points ?? []
                if let latest = points.last?.value { cardChecksum += latest }
                if let trend = ProgressCalculator.trendPercent(points) { cardChecksum += trend }
            }

            XCTAssertGreaterThanOrEqual(topPRs.count, 0)
            XCTAssertFalse(cardChecksum.isNaN)
        }
    }

    // MARK: Naive — per-exercise recompute (old behavior PERF-2/4/9 removed)

    func testProgressOverview_Naive() throws {
        let (_, _, sessions) = try makeHistory()

        measure {
            // ── `trackedExercises` was recomputed ~3× per render (the records
            //    section, the track section, and the scope content all read it).
            let tracked = trackedExercises(sessions)
            _ = trackedExercises(sessions)
            let trackedAgain = trackedExercises(sessions)

            // ── Recent PRs: a fresh `series` call PER exercise (no shared map).
            //    Each call reverses the sessions itself, as the old code did.
            var prs: [(exercise: Exercise, value: Double, date: Date)] = []
            for exercise in tracked {
                let ordered = Array(sessions.reversed())
                let points = ProgressCalculator.series(for: exercise,
                                                       metric: exercise.primaryMetric,
                                                       in: ordered)
                guard points.count >= 2, let best = points.map(\.value).max(), best > 0,
                      let last = points.last, last.value >= best - 0.001 else { continue }
                prs.append((exercise, best, last.date))
            }
            let topPRs = prs.sorted { $0.date > $1.date }.prefix(5)

            // ── Every trend card recomputed its OWN series from scratch (the old
            //    `ExerciseTrendCard.resolvedPoints()` with no `precomputed`), and
            //    re-reversed the sessions per card.
            var cardChecksum = 0.0
            for exercise in trackedAgain {
                let ordered = Array(sessions.reversed())
                let points = ProgressCalculator.series(for: exercise,
                                                       metric: exercise.primaryMetric,
                                                       in: ordered)
                if let latest = points.last?.value { cardChecksum += latest }
                if let trend = ProgressCalculator.trendPercent(points) { cardChecksum += trend }
            }

            XCTAssertGreaterThanOrEqual(topPRs.count, 0)
            XCTAssertFalse(cardChecksum.isNaN)
        }

        // Same workload, with a CLI-visible per-iteration average.
        benchMillis("Progress.naive") {
            let tracked = trackedExercises(sessions)
            _ = trackedExercises(sessions)
            let trackedAgain = trackedExercises(sessions)

            var prs: [(exercise: Exercise, value: Double, date: Date)] = []
            for exercise in tracked {
                let ordered = Array(sessions.reversed())
                let points = ProgressCalculator.series(for: exercise,
                                                       metric: exercise.primaryMetric,
                                                       in: ordered)
                guard points.count >= 2, let best = points.map(\.value).max(), best > 0,
                      let last = points.last, last.value >= best - 0.001 else { continue }
                prs.append((exercise, best, last.date))
            }
            let topPRs = prs.sorted { $0.date > $1.date }.prefix(5)

            var cardChecksum = 0.0
            for exercise in trackedAgain {
                let ordered = Array(sessions.reversed())
                let points = ProgressCalculator.series(for: exercise,
                                                       metric: exercise.primaryMetric,
                                                       in: ordered)
                if let latest = points.last?.value { cardChecksum += latest }
                if let trend = ProgressCalculator.trendPercent(points) { cardChecksum += trend }
            }

            XCTAssertGreaterThanOrEqual(topPRs.count, 0)
            XCTAssertFalse(cardChecksum.isNaN)
        }
    }

    // MARK: Micro-baseline — one `series` call over the full history

    /// Absolute cost of a single `ProgressCalculator.series` call across the
    /// whole synthetic history — the indivisible unit the naive path paid E×.
    func testProgressSeriesSingleExercise() throws {
        let (_, exercises, sessions) = try makeHistory()
        let ordered = Array(sessions.reversed())
        let exercise = exercises[0]

        measure {
            let points = ProgressCalculator.series(for: exercise, metric: .oneRepMax, in: ordered)
            XCTAssertFalse(points.isEmpty)
        }

        // Same workload, with a CLI-visible per-iteration average.
        benchMillis("Progress.singleSeries") {
            let points = ProgressCalculator.series(for: exercise, metric: .oneRepMax, in: ordered)
            XCTAssertFalse(points.isEmpty)
        }
    }
}
