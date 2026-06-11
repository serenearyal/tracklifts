//
//  SavedMealTests.swift
//  trackliftsTests
//
//  Guards Phase 3 saved meals: snapshotting a group of foods, that logging the
//  meal writes one DiaryEntry per item (right grams/portion/meal/day, re-priced
//  from the live food), and that an item whose source food was deleted is skipped.
//

import Foundation
import Testing
import SwiftData
@testable import tracklifts

@MainActor
struct SavedMealTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
            WaterEntry.self, SavedMeal.self, SavedMealItem.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func makeFood(_ name: String, kcalPer100g: Double, into context: ModelContext) -> FoodItem {
        let food = FoodItem(name: name, source: .seed, per100g: NutrientVector(energy: kcalPer100g))
        context.insert(food)
        return food
    }

    /// Builds a saved meal the way SaveMealSheet does, then logs it.
    private func makeBreakfast(in context: ModelContext) throws -> (SavedMeal, FoodItem, FoodItem) {
        let oats = makeFood("Oats", kcalPer100g: 380, into: context)
        let milk = makeFood("Milk", kcalPer100g: 60, into: context)
        let saved = SavedMeal(name: "Breakfast")
        context.insert(saved)
        let i1 = SavedMealItem(food: oats, grams: 80, portionLabel: "80 g", order: 0)
        let i2 = SavedMealItem(food: milk, grams: 200, portionLabel: "200 g", order: 1)
        context.insert(i1); i1.meal = saved   // to-one side after insert (iOS 17 rule)
        context.insert(i2); i2.meal = saved
        try context.save()
        return (saved, oats, milk)
    }

    @Test func savedMealLogsOneEntryPerItem() throws {
        let context = try makeContext()
        let (saved, _, _) = try makeBreakfast(in: context)

        #expect(saved.orderedItems.count == 2)
        // snapshot total: 380*0.8 + 60*2.0 = 304 + 120 = 424
        #expect(abs(saved.totalKcal - 424) < 1e-6)

        let day = Calendar.current.startOfDay(for: .now)
        for item in saved.orderedItems {
            guard let food = item.food else { continue }
            context.insert(DiaryEntry(date: day, meal: .lunch, food: food,
                                      grams: item.grams, portionLabel: item.portionLabel))
        }
        try context.save()

        let entries = try context.fetch(FetchDescriptor<DiaryEntry>())
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.meal == .lunch })
        #expect(entries.allSatisfy { Calendar.current.isDate($0.date, inSameDayAs: day) })
        #expect(abs(entries.reduce(0) { $0 + $1.kcal } - 424) < 1e-6)
        // portion labels carry over
        #expect(Set(entries.map(\.portionLabel)) == ["80 g", "200 g"])
    }

    @Test func deletedFoodItemIsSkippedOnLog() throws {
        let context = try makeContext()
        let (saved, _, milk) = try makeBreakfast(in: context)

        context.delete(milk) // nullifies the milk item's food via the inverse rule
        try context.save()

        let day = Calendar.current.startOfDay(for: .now)
        var logged = 0
        for item in saved.orderedItems {
            guard let food = item.food else { continue }
            context.insert(DiaryEntry(date: day, meal: .dinner, food: food,
                                      grams: item.grams, portionLabel: item.portionLabel))
            logged += 1
        }
        try context.save()

        #expect(logged == 1, "the item whose source food was deleted is skipped")
        #expect(try context.fetch(FetchDescriptor<DiaryEntry>()).count == 1)
        #expect(saved.orderedItems.count == 2, "the saved meal keeps both items; only logging skips the orphan")
    }
}
