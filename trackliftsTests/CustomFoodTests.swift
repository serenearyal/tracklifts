//
//  CustomFoodTests.swift
//  trackliftsTests
//
//  Guards Phase 3 custom foods: the per-serving ↔ per-100 g conversion that the
//  editor uses (nutrition labels read per serving; the catalog stores per 100 g),
//  and that a food built the way EditFoodView.save() builds it is loggable and
//  untouched by the seed dedup/purge passes.
//

import Foundation
import Testing
import SwiftData
@testable import tracklifts

struct CustomFoodConversionTests {

    @Test func perServingScalesToPer100g() {
        // A protein bar label: 190 kcal / 8 g protein per a 45 g serving.
        let per100g = NutrientVector.fromPerServing(["energy": 190, "protein": 8], servingGrams: 45)
        #expect(abs(per100g[.energy] - 190 * 100 / 45) < 1e-6)
        #expect(abs(per100g[.protein] - 8 * 100 / 45) < 1e-6)
    }

    @Test func roundTripIsLossless() {
        let amounts = ["energy": 190.0, "protein": 8, "carbs": 22, "fat": 7, "sodium": 140]
        let per100g = NutrientVector.fromPerServing(amounts, servingGrams: 45)
        let back = per100g.perServing(servingGrams: 45)
        for (key, value) in amounts {
            #expect(abs((back[key] ?? 0) - value) < 1e-6, "\(key) must survive the round trip")
        }
    }

    @Test func hundredGramServingIsIdentity() {
        let per100g = NutrientVector.fromPerServing(["energy": 250, "carbs": 30], servingGrams: 100)
        #expect(per100g[.energy] == 250)
        #expect(per100g[.carbs] == 30)
    }

    @Test func zeroAmountsAreDroppedToStaySparse() {
        let per100g = NutrientVector.fromPerServing(["energy": 190, "fat": 0], servingGrams: 45)
        #expect(per100g.values["fat"] == nil, "a zero entry must not be stored")
        #expect(per100g.values["energy"] != nil)
    }

    @Test func nonPositiveServingGramsYieldsEmpty() {
        #expect(NutrientVector.fromPerServing(["energy": 190], servingGrams: 0).values.isEmpty)
        #expect(NutrientVector(energy: 100).perServing(servingGrams: 0).isEmpty)
    }
}

@MainActor
struct CustomFoodModelTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Builds a food exactly the way `EditFoodView.save()` does, then proves it
    /// logs a correct snapshot and survives the seed dedup/purge passes.
    @Test func customFoodIsLoggableAndSurvivesDedupAndPurge() throws {
        let context = try makeContext()

        let per100g = NutrientVector.fromPerServing(["energy": 190, "protein": 8], servingGrams: 45)
        let food = FoodItem(name: "Protein Bar", brand: "Acme", source: .custom,
                            per100g: per100g, isCustom: true)
        context.insert(food)
        let portion = FoodPortion(label: "1 bar", grams: 45) // to-one side only (iOS 17 rule)
        context.insert(portion)
        portion.food = food
        try context.save()

        #expect(food.isCustom)
        #expect(food.source == .custom)
        #expect(food.fdcId == 0, "customs have no USDA id")
        #expect(food.orderedPortions.map(\.label) == ["1 bar"])

        // Logging one serving (45 g) snapshots the per-serving energy back out.
        let entry = DiaryEntry(date: .now, meal: .snacks, food: food, grams: food.defaultPortion.grams)
        context.insert(entry)
        try context.save()
        #expect(abs(entry.kcal - 190) < 1e-6, "one serving logs the label's per-serving energy")

        // The seed-only passes must never fetch a `.custom` food.
        CloudDedup.dedupeFoods(context)
        CloudDedup.purgeLegacyCurated(context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<FoodItem>()).count == 1,
                "a custom food is never merged or purged")
    }
}
