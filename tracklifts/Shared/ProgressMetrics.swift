//
//  ProgressMetrics.swift
//  tracklifts
//
//  Pure functions that turn logged history into chartable progression data.
//

import Foundation
import SwiftData

/// The progression metric the user is viewing.
enum ProgressMetric: String, CaseIterable, Identifiable {
    case oneRepMax = "Est. 1RM"
    case topWeight = "Top Weight"
    case volume = "Volume"
    case bestReps = "Best Reps"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .oneRepMax: "bolt.fill"
        case .topWeight: "scalemass.fill"
        case .volume: "chart.bar.fill"
        case .bestReps: "repeat"
        }
    }

    /// Whether the metric's value is expressed in the user's weight unit.
    var isWeightUnit: Bool { self != .bestReps }
}

/// The time range a progression chart is restricted to.
enum TimeWindow: String, CaseIterable, Identifiable {
    case all
    case ninety
    case thirty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All time"
        case .ninety: "Last 90 days"
        case .thirty: "Last 30 days"
        }
    }

    /// Number of days back from today, or nil for "all time".
    var days: Int? {
        switch self {
        case .all: nil
        case .ninety: 90
        case .thirty: 30
        }
    }
}

/// One point on a progression chart — the best value of a metric in a session.
struct ProgressPoint: Identifiable {
    let id: PersistentIdentifier
    let date: Date
    let value: Double
}

enum ProgressCalculator {
    /// Builds an ordered series of points for a given exercise and metric by
    /// scanning the logged sessions it appears in.
    static func series(
        for exercise: Exercise,
        metric: ProgressMetric,
        in sessions: [WorkoutSession]
    ) -> [ProgressPoint] {
        var points: [ProgressPoint] = []
        for session in sessions {
            let entries = session.entries.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
            guard !entries.isEmpty else { continue }
            let allSets = entries.flatMap(\.sets).filter { $0.reps > 0 }
            guard !allSets.isEmpty else { continue }

            let value: Double
            switch metric {
            case .oneRepMax:
                value = allSets.map(\.estimatedOneRepMax).max() ?? 0
            case .topWeight:
                value = allSets.map(\.effectiveWeight).max() ?? 0
            case .volume:
                value = allSets.reduce(0) { $0 + $1.volume }
            case .bestReps:
                value = Double(allSets.map(\.reps).max() ?? 0)
            }
            points.append(ProgressPoint(id: session.persistentModelID, date: session.date, value: value))
        }
        return points.sorted { $0.date < $1.date }
    }

    /// The all-time best estimated 1RM for an exercise across sessions.
    static func personalBestOneRepMax(for exercise: Exercise, in sessions: [WorkoutSession]) -> Double {
        series(for: exercise, metric: .oneRepMax, in: sessions).map(\.value).max() ?? 0
    }

    /// Trend between the first and most recent value of a series, as a percent.
    static func trendPercent(_ points: [ProgressPoint]) -> Double? {
        guard let first = points.first?.value, first > 0,
              let last = points.last?.value, points.count > 1 else { return nil }
        return (last - first) / first * 100
    }
}
