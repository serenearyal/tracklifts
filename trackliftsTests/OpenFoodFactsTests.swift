//
//  OpenFoodFactsTests.swift
//  trackliftsTests
//
//  Guards the Open Food Facts → NutrientVector mapping (Phase 3) against embedded
//  fixtures — no live network. Covers kcal vs kJ→kcal, sodium vs salt→sodium,
//  gram→mg minerals, lenient decoding (unit strings, string serving_quantity),
//  not-found, and search dropping nameless products.
//

import Foundation
import Testing
@testable import tracklifts

private func data(_ s: String) -> Data { s.data(using: .utf8)! }
/// Gram→mg conversions (×1000 of fractions like 0.3) don't land exactly in
/// binary floating point, so compare nutrient amounts with a tolerance.
private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

struct OpenFoodFactsTests {

    // status 1, energy in kcal, sodium direct, comma brands, micros present.
    private let granolaBar = """
    { "status": 1, "code": "0123456789012",
      "product": {
        "product_name": "Crunchy Granola Bar",
        "brands": "Acme, Acme Foods",
        "serving_quantity": 30,
        "nutriments": {
          "energy-kcal_100g": 450, "energy_100g": 1883, "energy_unit": "kcal",
          "proteins_100g": 8.5, "carbohydrates_100g": 60, "fat_100g": 18,
          "fiber_100g": 7, "sugars_100g": 22, "saturated-fat_100g": 3.5,
          "sodium_100g": 0.3, "salt_100g": 0.75,
          "calcium_100g": 0.12, "iron_100g": 0.004, "vitamin-c_100g": 0.02
        }
      } }
    """

    @Test func mapsHeadlineMacrosAndIdentity() throws {
        let food = try #require(OpenFoodFactsProvider.decodeProduct(data(granolaBar), fallbackBarcode: "x"))
        #expect(food.name == "Crunchy Granola Bar")
        #expect(food.brand == "Acme", "first of a comma-separated brand list")
        #expect(food.barcode == "0123456789012")
        #expect(food.servingGrams == 30)
        #expect(close(food.per100g[.energy], 450), "kcal is preferred over the kJ field")
        #expect(close(food.per100g[.protein], 8.5))
        #expect(close(food.per100g[.carbs], 60))
        #expect(close(food.per100g[.fat], 18))
        #expect(close(food.per100g[.fiber], 7))
        #expect(close(food.per100g[.sugar], 22))
        #expect(close(food.per100g[.satFat], 3.5))
        #expect(close(food.per100g[.sodium], 300), "sodium grams → mg, preferred over salt")
        #expect(close(food.per100g[.calcium], 120)) // 0.12 g → mg
        #expect(close(food.per100g[.iron], 4))      // 0.004 g → mg
        #expect(close(food.per100g[.vitaminC], 20)) // 0.02 g → mg
    }

    // No kcal (only kJ), no sodium (only salt), serving_quantity as a string.
    private let kjAndSalt = """
    { "status": 1, "code": "5000112637922",
      "product": {
        "product_name": "Sparkling Water", "brands": "Fizz",
        "serving_quantity": "330",
        "nutriments": { "energy_100g": 1046, "proteins_100g": 0, "carbohydrates_100g": 11, "salt_100g": 1.0 }
      } }
    """

    @Test func fallsBackToKilojoulesAndSalt() throws {
        let food = try #require(OpenFoodFactsProvider.decodeProduct(data(kjAndSalt), fallbackBarcode: "x"))
        #expect(abs(food.per100g[.energy] - 250) < 1e-6, "1046 kJ ÷ 4.184 = 250 kcal")
        #expect(abs(food.per100g[.sodium] - 400) < 1e-6, "1.0 g salt ÷ 2.5 × 1000 = 400 mg sodium")
        #expect(food.servingGrams == 330, "string serving_quantity is parsed")
    }

    @Test func notFoundReturnsNil() {
        let json = data(#"{ "status": 0, "status_verbose": "product not found" }"#)
        #expect(OpenFoodFactsProvider.decodeProduct(json, fallbackBarcode: "x") == nil)
    }

    @Test func usesFallbackBarcodeWhenCodeAbsent() throws {
        let json = data(#"{ "status": 1, "product": { "product_name": "Mystery", "nutriments": {} } }"#)
        let food = try #require(OpenFoodFactsProvider.decodeProduct(json, fallbackBarcode: "999"))
        #expect(food.barcode == "999")
        #expect(food.per100g.values.isEmpty, "no nutriments → empty vector, nothing invented")
    }

    @Test func mapNutrimentsConvertsUnits() {
        let v = OpenFoodFactsProvider.mapNutriments([
            "energy_100g": 1046, "potassium_100g": 0.45, "magnesium_100g": 0.05,
            "zinc_100g": 0.011, "phosphorus_100g": 0.2,
        ])
        #expect(close(v[.energy], 250))
        #expect(close(v[.potassium], 450))
        #expect(close(v[.magnesium], 50))
        #expect(close(v[.zinc], 11))
        #expect(close(v[.phosphorus], 200))
        #expect(v.values["protein"] == nil, "absent nutrients are not stored")
    }

    @Test func searchDecodesAndSkipsNamelessProducts() {
        let json = data("""
        { "products": [
            { "code": "111", "product_name": "Choco Bar", "brands": "Yum",
              "nutriments": { "energy-kcal_100g": 500, "proteins_100g": 6 }, "serving_quantity": 40 },
            { "code": "222", "brands": "NoName", "nutriments": { "energy-kcal_100g": 100 } }
        ] }
        """)
        let foods = OpenFoodFactsProvider.decodeSearch(json)
        #expect(foods.count == 1, "a product with no name is dropped")
        #expect(foods.first?.name == "Choco Bar")
        #expect(foods.first?.barcode == "111")
        #expect(foods.first?.per100g[.energy] == 500)
    }
}
