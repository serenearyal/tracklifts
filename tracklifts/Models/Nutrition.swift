//
//  Nutrition.swift
//  tracklifts
//
//  Core nutrition value types for the food log (Phase 1). Energy + macros now;
//  the keyed `NutrientVector` lets later phases add micronutrients with no
//  schema migration.
//

import Foundation

/// The nutrients we track. Phase 1 surfaced energy + macros; Phase 2 adds the
/// micronutrient panel (vitamins, minerals, fats). `rawValue`s are permanent —
/// they are the persisted JSON keys in every `NutrientVector`.
enum Nutrient: String, CaseIterable, Identifiable {
    // Macros (Phase 1)
    case energy, protein, carbs, fat, fiber, sugar, satFat, sodium
    // Fats & cholesterol (Phase 2)
    case monoFat, polyFat, transFat, cholesterol
    // Vitamins (Phase 2)
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminK
    case thiamin, riboflavin, niacin, vitaminB6, folate, vitaminB12
    // Minerals (Phase 2)
    case calcium, iron, magnesium, phosphorus, potassium
    case zinc, copper, selenium, manganese

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
        case .monoFat: "Monounsaturated"
        case .polyFat: "Polyunsaturated"
        case .transFat: "Trans Fat"
        case .cholesterol: "Cholesterol"
        case .vitaminA: "Vitamin A"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminE: "Vitamin E"
        case .vitaminK: "Vitamin K"
        case .thiamin: "Thiamin (B1)"
        case .riboflavin: "Riboflavin (B2)"
        case .niacin: "Niacin (B3)"
        case .vitaminB6: "Vitamin B6"
        case .folate: "Folate"
        case .vitaminB12: "Vitamin B12"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .magnesium: "Magnesium"
        case .phosphorus: "Phosphorus"
        case .potassium: "Potassium"
        case .zinc: "Zinc"
        case .copper: "Copper"
        case .selenium: "Selenium"
        case .manganese: "Manganese"
        }
    }

    /// Display unit: kcal, grams, milligrams, or micrograms ("mcg").
    var unit: String {
        switch self {
        case .energy: "kcal"
        case .protein, .carbs, .fat, .fiber, .sugar,
             .satFat, .monoFat, .polyFat, .transFat: "g"
        case .vitaminA, .vitaminD, .vitaminK, .folate, .vitaminB12, .selenium: "mcg"
        default: "mg" // sodium, cholesterol, vitamin C/E, B-vitamins, minerals
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

    // Reused instead of allocating a coder per call — diary totals decode one
    // blob per entry, and seeding encodes ~7,700. Used serially on the main actor.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    func encoded() -> Data { (try? Self.encoder.encode(self)) ?? Data() }
    static func decode(_ data: Data) -> NutrientVector {
        (try? decoder.decode(NutrientVector.self, from: data)) ?? NutrientVector()
    }

    // MARK: Custom foods — per-serving entry ↔ per-100 g storage

    /// Build a per-100 g vector from amounts entered **per serving** (the way a
    /// nutrition label reads), keyed by `Nutrient.rawValue`. Inverse of
    /// `perServing(servingGrams:)`; zero amounts are dropped to keep the bag sparse.
    static func fromPerServing(_ amounts: [String: Double], servingGrams: Double) -> NutrientVector {
        guard servingGrams > 0 else { return NutrientVector([:]) } // truly empty, not zero-filled macros
        let factor = 100 / servingGrams
        return NutrientVector(amounts.compactMapValues { $0 == 0 ? nil : $0 * factor })
    }

    /// The amounts **per serving** of `servingGrams`, keyed by `Nutrient.rawValue`
    /// — used to repopulate the custom-food editor when editing an existing food.
    func perServing(servingGrams: Double) -> [String: Double] {
        guard servingGrams > 0 else { return [:] }
        let factor = servingGrams / 100
        return values.mapValues { $0 * factor }
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

    /// The meal a quick-add most likely belongs to right now.
    static var defaultForNow: Meal {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<11: .breakfast
        case 11..<15: .lunch
        case 15..<21: .dinner
        default: .snacks
        }
    }
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
