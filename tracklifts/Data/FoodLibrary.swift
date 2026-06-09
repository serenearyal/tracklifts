//
//  FoodLibrary.swift
//  tracklifts
//
//  The bundled food catalog (Phase 1 engine). Curated whole + common foods with
//  per-100 g nutrition, imported once on first launch. The catalog itself lives
//  in FoodLibrary+Core.swift and FoodLibrary+Produce.swift.
//

import Foundation

/// A seeded food with per-100 g nutrition. Import-only.
struct SeedFood {
    let name: String
    let brand: String
    let kcal: Double      // per 100 g
    let protein: Double   // g / 100 g
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let satFat: Double
    let sodium: Double     // mg / 100 g
    let portions: [SeedPortion]

    var per100g: NutrientVector {
        NutrientVector(energy: kcal, protein: protein, carbs: carbs, fat: fat,
                       fiber: fiber, sugar: sugar, satFat: satFat, sodium: sodium)
    }
}

struct SeedPortion {
    let label: String
    let grams: Double
    init(_ label: String, _ grams: Double) { self.label = label; self.grams = grams }
}

enum FoodLibrary {
    /// The full catalog — `coreFoods` + `produceFoods` are generated in
    /// FoodLibrary+Core.swift / FoodLibrary+Produce.swift.
    static let all: [SeedFood] = coreFoods + produceFoods
}
