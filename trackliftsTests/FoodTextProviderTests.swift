//
//  FoodTextProviderTests.swift
//  trackliftsTests
//
//  Guards the shared Gemini food-estimation decode (used by both the photo and the
//  typed/spoken text providers) against embedded fixtures — no live network. Covers
//  JSON-array decoding (plain + ```json fenced), the TOTAL → per-100 g estimate,
//  gram hints, nameless/zero-energy drops, and the security clamp that rejects
//  out-of-range model values (so they can't poison the store or trap a display Int).
//

import Foundation
import Testing
@testable import tracklifts

private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

struct FoodTextProviderTests {

    // A 50 g espresso (~5 kcal) and a 60 g glazed donut (~250 kcal).
    private let twoItems = """
    [
      {"name": "espresso", "quantity": 1, "unit": "shot", "grams": 50,
       "kcal": 5, "protein": 0.3, "carbs": 0.8, "fat": 0.1,
       "fiber": 0, "sugar": 0, "satFat": 0, "sodium": 8},
      {"name": "glazed donut", "quantity": 1, "unit": "", "grams": 60,
       "kcal": 250, "protein": 3, "carbs": 31, "fat": 13,
       "fiber": 1, "sugar": 12, "satFat": 5, "sodium": 300}
    ]
    """

    @Test func decodesItemsWithEstimatesAndGramHints() throws {
        let items = GeminiFood.decodeItems(from: twoItems)
        #expect(items.count == 2)

        let espresso = items[0]
        #expect(espresso.name == "espresso")
        #expect(espresso.gramsHint == 50)
        let e = try #require(espresso.estimatedPer100g)
        #expect(close(e[.energy], 5.0 / 50 * 100), "5 kcal over 50 g → 10 kcal / 100 g")

        let donut = try #require(items[1].estimatedPer100g)
        #expect(close(donut[.energy], 250.0 / 60 * 100), "TOTAL → per-100 g")
        #expect(close(donut[.fat], 13.0 / 60 * 100))
    }

    @Test func stripsCodeFences() throws {
        let fenced = "```json\n" + twoItems + "\n```"
        let items = GeminiFood.decodeItems(from: fenced)
        #expect(items.count == 2)
        #expect(items[0].name == "espresso")
    }

    @Test func emptyArrayYieldsNoItems() {
        #expect(GeminiFood.decodeItems(from: "[]").isEmpty)
        #expect(GeminiFood.decodeItems(from: "not json at all").isEmpty)
    }

    // A nameless row is dropped; a row with no usable energy keeps no estimate.
    @Test func dropsNamelessAndUnusableEstimates() throws {
        let mixed = """
        [
          {"name": "", "grams": 100, "kcal": 200},
          {"name": "water", "grams": 250, "kcal": 0}
        ]
        """
        let items = GeminiFood.decodeItems(from: mixed)
        #expect(items.count == 1, "the nameless row is dropped")
        #expect(items[0].name == "water")
        #expect(items[0].estimatedPer100g == nil, "kcal 0 → no trustworthy estimate")
    }

    // SECURITY: out-of-range model numbers must not produce an estimate — otherwise a
    // 1e9 kcal value overflows into the stored vector and traps a later display Int.
    @Test func rejectsOutOfRangeValues() throws {
        let huge = """
        [{"name": "mystery", "grams": 100, "kcal": 1000000000, "protein": 5}]
        """
        let items = GeminiFood.decodeItems(from: huge)
        #expect(items.count == 1)
        #expect(items[0].estimatedPer100g == nil, "kcal beyond the cap → estimate rejected")
    }
}
