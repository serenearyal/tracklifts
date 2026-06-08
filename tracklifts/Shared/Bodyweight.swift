//
//  Bodyweight.swift
//  tracklifts
//
//  Support for body-weight movements (pull-ups, sit-ups, dips…). Such sets log
//  reps plus *added* weight (0 = pure bodyweight). When the user records their
//  body weight in Settings, calisthenics gain a real load so volume / 1RM trends
//  become meaningful; without it, progress falls back to reps.
//

import Foundation

/// Process-wide mirror of the user's body weight (stored in the active unit).
/// Backed by the same `UserDefaults` key as `@AppStorage("bodyWeight")`, so the
/// model layer can compute effective load without threading the value through
/// every call site. `0` means "not set".
enum BodyMetrics {
    static let key = "bodyWeight"

    static var current: Double {
        get { UserDefaults.standard.double(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var isSet: Bool { current > 0 }
}

// MARK: - Effective load

extension LoggedSet {
    /// Whether this set belongs to a body-weight exercise.
    var isBodyweight: Bool { loggedExercise?.exercise?.isBodyweight ?? false }

    /// The load used for volume / 1RM math. Weighted lifts use the logged
    /// weight directly. Body-weight lifts use (body weight + added); if the
    /// user hasn't recorded a body weight, only the added weight counts.
    var effectiveWeight: Double {
        guard isBodyweight else { return weight }
        let bodyWeight = BodyMetrics.current
        return bodyWeight > 0 ? bodyWeight + weight : weight
    }

    /// A compact human summary of one set, e.g. "8×60kg", "12 reps", "10 +15kg".
    func summary(unit: WeightUnit) -> String {
        if isBodyweight {
            if weight > 0 { return "\(reps) +\(weight.trimmedWeight)\(unit.label)" }
            return "\(reps) reps"
        }
        return "\(reps)×\(weight.trimmedWeight)\(unit.label)"
    }
}

// MARK: - Which metric represents "progress" for an exercise

extension Exercise {
    /// True when a weight-based metric is meaningful right now — always for
    /// weighted lifts, and for body-weight lifts once a body weight is recorded.
    var tracksExternalLoad: Bool { !isBodyweight || BodyMetrics.isSet }

    /// The headline progression metric for this exercise. Pure body-weight
    /// movements (no recorded body weight) progress by reps instead of 1RM.
    var primaryMetric: ProgressMetric { tracksExternalLoad ? .oneRepMax : .bestReps }
}
