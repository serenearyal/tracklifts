//
//  Water.swift
//  tracklifts
//
//  Phase 3 hydration tracking. `WaterEntry` is a tiny time-series row (mirrors
//  `BodyWeightEntry`) that syncs through CloudKit; the daily goal + display unit
//  are UserDefaults scalars mirrored through `CloudPrefs`, exactly like the
//  nutrition goals. Storage is always milliliters — the unit only affects display.
//

import Foundation
import SwiftData

@Model
final class WaterEntry {
    /// Start of the day this entry belongs to; same-day adds ordered by `createdAt`.
    var date: Date = Date()
    /// Amount in milliliters — the canonical unit, regardless of how it's shown.
    var amountMl: Double = 0
    var createdAt: Date = Date()

    init(date: Date = .now, amountMl: Double) {
        self.date = Calendar.current.startOfDay(for: date)
        self.amountMl = amountMl
        self.createdAt = Date()
    }
}

/// How hydration is shown and entered. Storage is always milliliters.
enum WaterUnit: String, CaseIterable, Identifiable {
    case ml
    case oz   // US fluid ounce
    case cup  // 240 ml, matching nutrition-label cups

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ml: "ml"
        case .oz: "oz"
        case .cup: "cups"
        }
    }

    /// One unit of this measure in milliliters.
    var milliliters: Double {
        switch self {
        case .ml: 1
        case .oz: 29.5735
        case .cup: 240
        }
    }

    /// Quick-add increments offered on the diary water card, expressed in this unit.
    var quickAdds: [Double] {
        switch self {
        case .ml: [250, 500]
        case .oz: [8, 16]
        case .cup: [1, 2]
        }
    }
}

/// Daily water goal + display unit, stored via `@AppStorage` and mirrored through
/// iCloud (see `CloudPrefs`). Mirrors the `NutritionGoals` key/default shape.
enum WaterGoals {
    static let goalKey = "goalWaterMl"
    static let unitKey = "waterUnit"

    /// ~8 cups. Stored in ml so the display unit can change without touching it.
    static let defaultGoalMl: Double = 2000
}
