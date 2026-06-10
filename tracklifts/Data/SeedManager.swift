//
//  SeedManager.swift
//  tracklifts
//

import Foundation
import SwiftData

enum SeedManager {
    /// One-time flag: have we reconciled seeded exercises' body-weight flags?
    private static let backfillFlag = "didBackfillBodyweight_v1"

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
        // A fresh store is seeded with correct flags already, so mark the
        // backfill done. Otherwise it would run on the next launch and revert
        // any bodyweight toggle the user makes during this first session.
        UserDefaults.standard.set(true, forKey: backfillFlag)
        try? context.save()
    }

    /// Bootstraps the weight log from the legacy single body-weight setting: if
    /// the user had set a body weight (used for calisthenics load) but has no
    /// logged weigh-ins yet, seed one so their value becomes the first point.
    @MainActor
    static func seedBodyWeightIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<BodyWeightEntry>())) ?? 0
        guard count == 0, BodyMetrics.current > 0 else { return }
        // An established iCloud user's weigh-ins are about to sync in — don't
        // seed a stray legacy point alongside them.
        guard !(CloudSync.isEnabled && CloudPrefs.shared.remoteSaysOnboarded) else { return }
        context.insert(BodyWeightEntry(date: .now, weight: BodyMetrics.current))
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
        try? context.delete(model: BodyWeightEntry.self)
        try? context.delete(model: DiaryEntry.self)
        try? context.delete(model: FoodPortion.self)
        try? context.delete(model: FoodItem.self)
        BodyMetrics.current = 0
        UserDefaults.standard.set(true, forKey: Profile.didOnboardKey) // skip onboarding in UI tests
        UserDefaults.standard.removeObject(forKey: backfillFlag)
        try? context.save()
    }

    /// Marks seeded calisthenics as body-weight on stores created before the
    /// flag existed. Runs once; only touches non-custom exercises by exact name.
    @MainActor
    static func backfillBodyweightIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: backfillFlag) else { return }
        defer { UserDefaults.standard.set(true, forKey: backfillFlag) }

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
