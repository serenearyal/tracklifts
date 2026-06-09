//
//  Nutrition.swift
//  tracklifts
//
//  Core nutrition value types for the food log (Phase 1). Energy + macros now;
//  the keyed `NutrientVector` lets later phases add micronutrients with no
//  schema migration.
//

import Foundation

/// The nutrients we track. Phase 1 surfaces energy + macros.
enum Nutrient: String, CaseIterable, Identifiable {
    case energy, protein, carbs, fat, fiber, sugar, satFat, sodium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        case .satFat: "Sat. Fat"
        case .sodium: "Sodium"
        }
    }

    /// Display unit: kcal for energy, mg for sodium, grams for everything else.
    var unit: String {
        switch self {
        case .energy: "kcal"
        case .sodium: "mg"
        default: "g"
        }
    }

    var tint: String { rawValue } // hook for per-nutrient color, later
}

/// A sparse, migration-proof bag of nutrient amounts (energy kcal, macros grams,
/// sodium mg). Keyed by `Nutrient.rawValue` so new nutrients add without a
/// schema change. Persisted as encoded JSON on the SwiftData models.
struct NutrientVector: Codable, Equatable {
    var values: [String: Double]

    init(_ values: [String: Double]) { self.values = values }

    init(energy: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
         fiber: Double = 0, sugar: Double = 0, satFat: Double = 0, sodium: Double = 0) {
        values = [
            Nutrient.energy.rawValue: energy,
            Nutrient.protein.rawValue: protein,
            Nutrient.carbs.rawValue: carbs,
            Nutrient.fat.rawValue: fat,
            Nutrient.fiber.rawValue: fiber,
            Nutrient.sugar.rawValue: sugar,
            Nutrient.satFat.rawValue: satFat,
            Nutrient.sodium.rawValue: sodium,
        ]
    }

    subscript(_ n: Nutrient) -> Double {
        get { values[n.rawValue] ?? 0 }
        set { values[n.rawValue] = newValue }
    }

    var energy: Double { self[.energy] }
    var protein: Double { self[.protein] }
    var carbs: Double { self[.carbs] }
    var fat: Double { self[.fat] }

    func scaled(by factor: Double) -> NutrientVector {
        NutrientVector(values.mapValues { $0 * factor })
    }

    static func + (lhs: NutrientVector, rhs: NutrientVector) -> NutrientVector {
        var out = lhs.values
        for (key, value) in rhs.values { out[key, default: 0] += value }
        return NutrientVector(out)
    }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data) -> NutrientVector {
        (try? JSONDecoder().decode(NutrientVector.self, from: data)) ?? NutrientVector()
    }
}

/// Where a food came from.
enum FoodSource: String, Codable { case seed, custom, openFoodFacts }

/// Meal sections in the daily diary.
enum Meal: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, dinner, snacks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snacks: "carrot.fill"
        }
    }

    var order: Int { Meal.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Formatting helpers

extension Double {
    /// Whole-number kcal/gram string, e.g. "165".
    var asCalories: String { String(Int(rounded())) }
    /// Grams with at most one decimal, no trailing ".0".
    var asGrams: String {
        self == rounded() ? String(Int(rounded())) : String(format: "%.1f", self)
    }
}
