//
//  BodyWeight.swift
//  tracklifts
//
//  A logged body-weight measurement. The time-series behind the weight trend,
//  and the source of truth that keeps `BodyMetrics.current` (read by the
//  calisthenics effective-load math) in sync with the latest weigh-in.
//

import Foundation
import SwiftData

@Model
final class BodyWeightEntry {
    /// Normalized to the start of the day by the logging UI; same-day weigh-ins
    /// are disambiguated by `createdAt`.
    var date: Date = Date()
    var weight: Double = 0
    /// Optional body-fat %, 0 = not recorded. Surfaced in a later roadmap phase.
    var bodyFat: Double = 0
    var createdAt: Date = Date()

    init(date: Date = .now, weight: Double, bodyFat: Double = 0) {
        self.date = date
        self.weight = weight
        self.bodyFat = bodyFat
        self.createdAt = Date()
    }
}
