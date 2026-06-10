//
//  Workout.swift
//  tracklifts
//
//  A logged training session: a date, plus the exercises performed and the
//  sets recorded under each. This is the data progression charts are built from.
//

import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var date: Date = Date()
    var notes: String = ""
    /// Optional label, e.g. the split day this session was based on ("Push").
    var title: String = ""
    /// Monotonic creation timestamp used to order sessions logged on the same
    /// calendar day (the user-facing `date` is normalized to midnight by the
    /// date picker, so it can't disambiguate same-day sessions on its own).
    var createdAt: Date = Date()

    // Optional because CloudKit requires every relationship to be optional
    // (container creation hard-fails otherwise). Read via orderedEntries.
    @Relationship(deleteRule: .cascade, inverse: \LoggedExercise.session)
    var entries: [LoggedExercise]? = []

    init(date: Date = Date(), title: String = "") {
        self.date = date
        self.title = title
        self.createdAt = Date()
    }

    var orderedEntries: [LoggedExercise] {
        (entries ?? []).sorted { $0.order < $1.order }
    }

    var entryCount: Int { entries?.count ?? 0 }

    /// Total volume (reps × weight, summed across every set) for the session.
    var totalVolume: Double {
        (entries ?? []).reduce(0) { $0 + $1.totalVolume }
    }

    var totalSets: Int {
        (entries ?? []).reduce(0) { $0 + $1.setCount }
    }
}

@Model
final class LoggedExercise {
    var order: Int = 0
    var session: WorkoutSession?
    var exercise: Exercise?

    // Optional for CloudKit (see WorkoutSession.entries). Read via orderedSets.
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.loggedExercise)
    var sets: [LoggedSet]? = []

    init(exercise: Exercise, order: Int) {
        self.exercise = exercise
        self.order = order
    }

    var orderedSets: [LoggedSet] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    var setCount: Int { sets?.count ?? 0 }

    var totalVolume: Double {
        (sets ?? []).reduce(0) { $0 + $1.volume }
    }

    /// Heaviest weight lifted across the session's sets for this exercise.
    /// Uses effective load so body-weight lifts count body weight + added.
    var topWeight: Double {
        (sets ?? []).map(\.effectiveWeight).max() ?? 0
    }

    /// Best estimated one-rep max across the sets (Epley formula).
    var bestEstimatedOneRepMax: Double {
        (sets ?? []).map(\.estimatedOneRepMax).max() ?? 0
    }
}

@Model
final class LoggedSet {
    var reps: Int = 0
    var weight: Double = 0
    var order: Int = 0
    var loggedExercise: LoggedExercise?

    init(reps: Int, weight: Double, order: Int) {
        self.reps = reps
        self.weight = weight
        self.order = order
    }

    var volume: Double { Double(reps) * effectiveWeight }

    /// Epley estimated 1RM: weight × (1 + reps/30). A single-number proxy for
    /// strength that rewards both heavier weight and more reps. Uses effective
    /// load so body-weight lifts are scored on body weight + added weight.
    var estimatedOneRepMax: Double {
        guard reps > 0 else { return 0 }
        let w = effectiveWeight
        if reps == 1 { return w }
        return w * (1.0 + Double(reps) / 30.0)
    }
}

// MARK: - Session factories

extension WorkoutSession {
    /// Inserts and returns a fresh, empty session dated now. Callers hand it
    /// straight to the new-workout sheet.
    static func blank(in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(date: .now)
        context.insert(session)
        return session
    }

    /// Clones a past session's exercises and sets into a fresh session for
    /// today. Each child is inserted as it's created (SwiftData on iOS 17
    /// crashes when to-many relationships of un-inserted models are touched).
    static func repeated(from source: WorkoutSession, in context: ModelContext) -> WorkoutSession {
        let new = WorkoutSession(date: .now, title: source.title)
        context.insert(new)
        for entry in source.orderedEntries {
            guard let exercise = entry.exercise else { continue }
            let newEntry = LoggedExercise(exercise: exercise, order: entry.order)
            newEntry.session = new
            context.insert(newEntry)
            for set in entry.orderedSets {
                let newSet = LoggedSet(reps: set.reps, weight: set.weight, order: set.order)
                newSet.loggedExercise = newEntry
                context.insert(newSet)
            }
        }
        return new
    }
}
