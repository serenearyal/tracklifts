//
//  Recipe.swift
//  tracklifts
//
//  Phase 3 recipes: compose ingredients into one new per-serving food. A Recipe
//  owns its ingredient list + servings (the source of truth) and a single derived,
//  loggable FoodItem (source .recipe) recomputed on every save. That food flows
//  through search → LogFoodView → DiaryEntry like any food, so micros, the nutrient
//  panel, and the completeness score all work with no special-casing.
//

import Foundation
import SwiftData

@Model
final class Recipe {
    var name: String = ""
    var servings: Double = 1
    var notes: String = ""
    var createdAt: Date = Date()

    // Optional because CloudKit requires every relationship to be optional.
    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]? = []

    /// The derived, loggable food, recomputed on every save. Cascade: deleting the
    /// recipe deletes this food; past diary entries keep their snapshot because
    /// `FoodItem.diaryEntries` is nullify (history is immutable).
    @Relationship(deleteRule: .cascade, inverse: \FoodItem.recipe)
    var food: FoodItem?

    init(name: String, servings: Double = 1, notes: String = "") {
        self.name = name
        self.servings = servings
        self.notes = notes
        self.createdAt = Date()
    }

    var orderedIngredients: [RecipeIngredient] {
        (ingredients ?? []).sorted { $0.order < $1.order }
    }
}

@Model
final class RecipeIngredient {
    var grams: Double = 0
    var order: Int = 0
    /// Snapshot for display if the source food is later deleted.
    var foodName: String = ""
    var recipe: Recipe?
    /// Source food, read for nutrients when the recipe is (re)computed. Nullified
    /// when the food is deleted (rule on the inverse, `FoodItem.recipeIngredients`).
    var food: FoodItem?

    init(food: FoodItem, grams: Double, order: Int = 0) {
        self.food = food
        self.grams = grams
        self.foodName = food.name
        self.order = order
    }
}
