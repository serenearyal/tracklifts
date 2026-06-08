//
//  SeedManager.swift
//  tracklifts
//

import Foundation
import SwiftData

enum SeedManager {
    /// Inserts the default exercise catalog the first time the app runs.
    /// Safe to call on every launch — it no-ops once exercises exist, then
    /// runs a one-time backfill so stores seeded before body-weight support
    /// pick up the flag.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else {
            backfillBodyweightIfNeeded(context)
            return
        }

        for (name, group) in ExerciseLibrary.all {
            context.insert(Exercise(name: name, muscleGroup: group,
                                    isBodyweight: ExerciseLibrary.isBodyweight(name)))
        }
        try? context.save()
    }

    /// Wipes every model (children first) and the one-time flags. UI-test only
    /// hook so each run starts from a deterministic, empty store.
    @MainActor
    static func resetAll(_ context: ModelContext) {
        try? context.delete(model: LoggedSet.self)
        try? context.delete(model: LoggedExercise.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: SplitItem.self)
        try? context.delete(model: SplitDay.self)
        try? context.delete(model: Split.self)
        try? context.delete(model: Exercise.self)
        UserDefaults.standard.removeObject(forKey: "didBackfillBodyweight_v1")
        try? context.save()
    }

    /// Marks seeded calisthenics as body-weight on stores created before the
    /// flag existed. Runs once; only touches non-custom exercises by exact name.
    @MainActor
    static func backfillBodyweightIfNeeded(_ context: ModelContext) {
        let flag = "didBackfillBodyweight_v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        defer { UserDefaults.standard.set(true, forKey: flag) }

        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in all where !exercise.isCustom
        && ExerciseLibrary.isBodyweight(exercise.name) && !exercise.isBodyweight {
            exercise.isBodyweight = true
            changed = true
        }
        if changed { try? context.save() }
    }
}
