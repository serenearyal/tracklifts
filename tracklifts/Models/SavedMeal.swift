//
//  SavedMeal.swift
//  tracklifts
//
//  Phase 3 saved meals: a named, reusable group of foods (e.g. "My Breakfast")
//  that logs every item in one tap. Distinct from a Recipe — a saved meal writes
//  one DiaryEntry per item (re-priced from the live food), rather than collapsing
//  into a single per-serving food. Items snapshot a name + kcal for display so the
//  meal still reads correctly if a source food is later edited or deleted.
//

import Foundation
import SwiftData

@Model
final class SavedMeal {
    var name: String = ""
    var createdAt: Date = Date()

    // Optional because CloudKit requires every relationship to be optional.
    @Relationship(deleteRule: .cascade, inverse: \SavedMealItem.meal)
    var items: [SavedMealItem]? = []

    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }

    var orderedItems: [SavedMealItem] {
        (items ?? []).sorted { $0.order < $1.order }
    }

    /// Snapshot energy across items — the row subtitle in search.
    var totalKcal: Double {
        orderedItems.reduce(0) { $0 + $1.kcal }
    }
}

@Model
final class SavedMealItem {
    var grams: Double = 0
    var portionLabel: String = ""
    var order: Int = 0
    /// Snapshots for display/totals if the source food is later edited/deleted.
    var foodName: String = ""
    var kcal: Double = 0
    var meal: SavedMeal?
    /// Source food, re-priced when the meal is logged. Nullified when the food is
    /// deleted (rule on the inverse, `FoodItem.savedMealItems`) — a nil-food item
    /// is then skipped at log time.
    var food: FoodItem?

    init(food: FoodItem, grams: Double, portionLabel: String, order: Int = 0) {
        self.food = food
        self.grams = grams
        self.portionLabel = portionLabel
        self.foodName = food.name
        self.kcal = food.nutrients(forGrams: grams).energy
        self.order = order
    }
}
