//
//  CaptureMatcherTests.swift
//  trackliftsTests
//
//  Guards Phase 4 matching: parsed items resolve to catalog foods, and grams are
//  derived sensibly (explicit hint > mass/volume unit > food portion > default).
//

import Foundation
import Testing
import SwiftData
@testable import tracklifts

/// Pure gram resolution — no SwiftData needed.
struct CaptureMatcherGramsTests {

    @Test func explicitGramHintWins() {
        let item = ParsedItem(name: "anything", quantity: 3, unit: "cup", gramsHint: 150)
        #expect(CaptureMatcher.resolveGrams(item, food: nil).grams == 150)
    }

    @Test func massAndVolumeUnitsConvertWithoutAFood() {
        #expect(CaptureMatcher.resolveGrams(ParsedItem(name: "chicken", quantity: 200, unit: "g"), food: nil).grams == 200)
        #expect(CaptureMatcher.resolveGrams(ParsedItem(name: "rice", quantity: 2, unit: "cup"), food: nil).grams == 480)
        let oz = CaptureMatcher.resolveGrams(ParsedItem(name: "steak", quantity: 1, unit: "oz"), food: nil).grams
        #expect(abs(oz - 28.35) < 1e-6)
    }

    @Test func unmatchedBareCountFallsBackTo100gEach() {
        let r = CaptureMatcher.resolveGrams(ParsedItem(name: "mystery", quantity: 2, unit: ""), food: nil)
        #expect(r.grams == 200)
    }
}

@MainActor
struct CaptureMatcherMatchTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
            WaterEntry.self, SavedMeal.self, SavedMealItem.self,
            Recipe.self, RecipeIngredient.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @discardableResult
    private func makeFood(_ name: String, kcal: Double, portion: (String, Double)?,
                          into c: ModelContext) -> FoodItem {
        let f = FoodItem(name: name, source: .seed, per100g: NutrientVector(energy: kcal))
        c.insert(f)
        if let portion {
            let p = FoodPortion(label: portion.0, grams: portion.1)
            c.insert(p); p.food = f          // to-one side after insert (iOS 17 rule)
        }
        return f
    }

    @Test func resolvesNameToCatalogFoodAndUsesDefaultPortionForBareCounts() throws {
        let context = try makeContext()
        makeFood("Egg", kcal: 143, portion: ("1 large (50 g)", 50), into: context)
        try context.save()

        let matches = CaptureMatcher.match([ParsedItem(name: "egg", quantity: 2, unit: "")], in: context)
        #expect(matches.count == 1)
        #expect(matches[0].food?.name == "Egg")
        #expect(matches[0].grams == 100)            // default portion 50 g × 2
    }

    @Test func descriptiveUnitUsesAMatchingFoodPortion() throws {
        let context = try makeContext()
        makeFood("Bread", kcal: 265, portion: ("1 slice (28 g)", 28), into: context)
        try context.save()

        let matches = CaptureMatcher.match([ParsedItem(name: "bread", quantity: 2, unit: "slice")], in: context)
        #expect(matches[0].food?.name == "Bread")
        #expect(matches[0].grams == 56)             // portion labeled "slice" 28 g × 2
    }

    @Test func unknownFoodStaysUnmatchedButStillHasGrams() throws {
        let context = try makeContext()
        makeFood("Apple", kcal: 52, portion: nil, into: context)
        try context.save()

        let matches = CaptureMatcher.match([ParsedItem(name: "zzznotreal", quantity: 1, unit: "")], in: context)
        #expect(matches[0].food == nil)
        #expect(matches[0].isMatched == false)
        #expect(matches[0].grams == 100)            // 100 g × 1 fallback
    }

    @Test func photoEstimateWithoutCatalogMatchBecomesLoggableFood() throws {
        let context = try makeContext()
        makeFood("Apple", kcal: 52, portion: nil, into: context)   // unrelated catalog food
        try context.save()

        // A glazed donut isn't in the catalog; the photo model's TOTAL estimate for
        // the ~60 g item, converted to per-100 g exactly as the provider does.
        let estimate = NutrientVector.fromPerServing(
            [Nutrient.energy.rawValue: 260, Nutrient.protein.rawValue: 3,
             Nutrient.carbs.rawValue: 31, Nutrient.fat.rawValue: 14], servingGrams: 60)
        let item = ParsedItem(name: "glazed donut", quantity: 1, unit: "",
                              gramsHint: 60, estimatedPer100g: estimate)

        let matches = CaptureMatcher.match([item], in: context)
        #expect(matches.count == 1)
        #expect(matches[0].food != nil)             // the estimate gives it a (custom) food
        #expect(matches[0].isEstimated == true)
        #expect(matches[0].food?.name == "glazed donut")
        #expect(matches[0].grams == 60)             // gramsHint wins
        // Nutrition round-trips: per-100 g scaled back to 60 g ≈ the model's totals.
        let logged = matches[0].food!.nutrients(forGrams: matches[0].grams)
        #expect(abs(logged.energy - 260) < 1e-6)
        #expect(abs(logged.protein - 3) < 1e-6)
    }

    @Test func catalogMatchWinsOverPhotoEstimate() throws {
        let context = try makeContext()
        makeFood("Glazed Donut", kcal: 400, portion: nil, into: context)
        try context.save()

        let estimate = NutrientVector.fromPerServing([Nutrient.energy.rawValue: 260], servingGrams: 60)
        let item = ParsedItem(name: "glazed donut", quantity: 1, unit: "",
                              gramsHint: 60, estimatedPer100g: estimate)

        let matches = CaptureMatcher.match([item], in: context)
        #expect(matches[0].food?.name == "Glazed Donut")   // the catalog food, not the estimate
        #expect(matches[0].isEstimated == false)
        #expect(matches[0].food?.kcalPer100g == 400)       // nutrition comes from the catalog
    }
}
