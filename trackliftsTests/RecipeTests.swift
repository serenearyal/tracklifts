//
//  RecipeTests.swift
//  trackliftsTests
//
//  Guards Phase 3 recipes: the pure ingredient→per-serving aggregation, that the
//  derived food logs (total nutrients ÷ servings) for one serving, and that
//  deleting a recipe removes its food + ingredients while logged history keeps its
//  immutable snapshot.
//

import Foundation
import Testing
import SwiftData
@testable import tracklifts

struct RecipeMathTests {

    @Test func aggregatesPerServingAcrossIngredients() {
        let a = NutrientVector(energy: 200, protein: 20)   // per 100 g
        let b = NutrientVector(energy: 100, protein: 5)
        // 100 g of a + 100 g of b over 2 servings.
        let agg = RecipeMath.aggregate([(a, 100), (b, 100)], servings: 2)
        // total = 300 kcal / 200 g → 150 kcal per 100 g; serving = 100 g.
        #expect(abs(agg.per100g[.energy] - 150) < 1e-6)
        #expect(abs(agg.per100g[.protein] - 12.5) < 1e-6) // (20+5) over 200 g
        #expect(abs(agg.servingGrams - 100) < 1e-6)
        // one serving = total ÷ servings = 300 / 2 = 150 kcal.
        let serving = agg.per100g.scaled(by: agg.servingGrams / 100)
        #expect(abs(serving[.energy] - 150) < 1e-6)
    }

    @Test func emptyOrZeroIsSafe() {
        let (v, g) = RecipeMath.aggregate([], servings: 4)
        #expect(v.values.isEmpty)
        #expect(g == 0)
        // zero servings is treated as 1 — no divide-by-zero.
        let (_, g2) = RecipeMath.aggregate([(NutrientVector(energy: 100), 50)], servings: 0)
        #expect(g2 == 50)
    }
}

@MainActor
struct RecipeModelTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
            WaterEntry.self, SavedMeal.self, SavedMealItem.self,
            Recipe.self, RecipeIngredient.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func makeFood(_ name: String, kcal: Double, into c: ModelContext) -> FoodItem {
        let f = FoodItem(name: name, source: .seed, per100g: NutrientVector(energy: kcal))
        c.insert(f)
        return f
    }

    /// Builds a recipe the way RecipeEditorView.save() does, then logs one serving.
    private func buildOatmeal(in context: ModelContext) throws -> (Recipe, FoodItem) {
        let oats = makeFood("Oats", kcal: 380, into: context)
        let milk = makeFood("Milk", kcal: 60, into: context)
        let agg = RecipeMath.aggregate([(oats.per100g, 80), (milk.per100g, 200)], servings: 2)

        let recipe = Recipe(name: "Oatmeal", servings: 2)
        context.insert(recipe)
        let i1 = RecipeIngredient(food: oats, grams: 80, order: 0)
        context.insert(i1); i1.recipe = recipe       // to-one side after insert (iOS 17 rule)
        let i2 = RecipeIngredient(food: milk, grams: 200, order: 1)
        context.insert(i2); i2.recipe = recipe

        let food = FoodItem(name: "Oatmeal", source: .recipe, per100g: agg.per100g, isCustom: true)
        context.insert(food)
        let portion = FoodPortion(label: "1 serving", grams: agg.servingGrams)
        context.insert(portion); portion.food = food
        recipe.food = food                            // one-to-one, both inserted
        try context.save()
        return (recipe, food)
    }

    @Test func recipeServingLogsTotalDividedByServings() throws {
        let context = try makeContext()
        let (recipe, food) = try buildOatmeal(in: context)

        #expect(food.source == .recipe)
        #expect(recipe.food === food)

        // total = 380*0.8 + 60*2 = 424 kcal; one of 2 servings = 212.
        let entry = DiaryEntry(date: .now, meal: .breakfast, food: food, grams: food.defaultPortion.grams)
        context.insert(entry)
        try context.save()
        #expect(abs(entry.kcal - 212) < 1e-6)
    }

    @Test func deletingRecipeKeepsLoggedHistory() throws {
        let context = try makeContext()
        let (recipe, food) = try buildOatmeal(in: context)

        let entry = DiaryEntry(date: .now, meal: .breakfast, food: food, grams: food.defaultPortion.grams)
        context.insert(entry)
        try context.save()
        let loggedKcal = entry.kcal

        context.delete(recipe) // cascades to ingredients + the derived food
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecipeIngredient>()).isEmpty)
        let recipeFoods = try context.fetch(FetchDescriptor<FoodItem>()).filter { $0.source == .recipe }
        #expect(recipeFoods.isEmpty, "the derived food is cascade-deleted with the recipe")

        let entries = try context.fetch(FetchDescriptor<DiaryEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].food == nil, "diary keeps its snapshot; the food ref is nullified")
        #expect(abs(entries[0].kcal - loggedKcal) < 1e-6)
        // the plain ingredient foods (oats/milk) are untouched.
        #expect(try context.fetch(FetchDescriptor<FoodItem>()).count == 2)
    }
}
