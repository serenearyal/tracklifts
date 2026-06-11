//
//  Food.swift
//  tracklifts
//
//  SwiftData models for the food log (Phase 1): the canonical food catalog,
//  serving portions, and the daily diary. Diary entries snapshot their
//  nutrients so history never changes if the source food is edited or deleted.
//

import Foundation
import SwiftData

@Model
final class FoodItem {
    var name: String = ""
    var brand: String = ""
    var sourceRaw: String = FoodSource.custom.rawValue
    var barcode: String = ""
    /// Energy per 100 g — a promoted column for fast sort / quick reads.
    var kcalPer100g: Double = 0
    /// Encoded `NutrientVector` per 100 g.
    var nutrientData: Data = Data()
    var isCustom: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    /// USDA FoodData Central id (0 = custom / no source). Stable identity for dedup + re-log.
    var fdcId: Int = 0

    // Optional because CloudKit requires every relationship to be optional.
    @Relationship(deleteRule: .cascade, inverse: \FoodPortion.food)
    var portions: [FoodPortion]? = []

    // CloudKit-required inverse of DiaryEntry.food. Deleting a food nullifies
    // the diary's back-reference; entries keep their nutrient snapshots.
    @Relationship(deleteRule: .nullify, inverse: \DiaryEntry.food)
    var diaryEntries: [DiaryEntry]? = []

    init(name: String, brand: String = "", source: FoodSource = .seed,
         per100g: NutrientVector, barcode: String = "", isCustom: Bool = false, fdcId: Int = 0) {
        self.name = name
        self.brand = brand
        self.sourceRaw = source.rawValue
        self.barcode = barcode
        self.nutrientData = per100g.encoded()
        self.kcalPer100g = per100g.energy
        self.isCustom = isCustom
        self.fdcId = fdcId
        self.createdAt = Date()
    }

    var per100g: NutrientVector {
        get { NutrientVector.decode(nutrientData) }
        set { nutrientData = newValue.encoded(); kcalPer100g = newValue.energy }
    }

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .custom }

    var orderedPortions: [FoodPortion] {
        (portions ?? []).sorted { $0.order < $1.order }
    }

    /// Default serving — the first portion, falling back to a 100 g serving.
    var defaultPortion: FoodPortion {
        orderedPortions.first ?? FoodPortion(label: "100 g", grams: 100)
    }

    /// Nutrients for an arbitrary gram amount.
    func nutrients(forGrams grams: Double) -> NutrientVector {
        per100g.scaled(by: grams / 100)
    }
}

@Model
final class FoodPortion {
    var label: String = ""
    var grams: Double = 0
    var order: Int = 0
    var food: FoodItem?

    init(label: String, grams: Double, order: Int = 0) {
        self.label = label
        self.grams = grams
        self.order = order
    }
}

@Model
final class DiaryEntry {
    /// Start of the day this entry belongs to.
    var date: Date = Date()
    var mealRaw: String = Meal.breakfast.rawValue
    var grams: Double = 0
    var portionLabel: String = ""
    /// Snapshots — so diary history is immutable w.r.t. later food edits/deletes.
    var foodName: String = ""
    var brand: String = ""
    var kcal: Double = 0
    var nutrientData: Data = Data()
    var order: Int = 0
    var createdAt: Date = Date()
    /// USDA FoodData Central id snapshotted from the source food (0 = custom).
    var fdcId: Int = 0
    /// Reference to the source food. Nullified (not cascaded) when the food is
    /// deleted — the rule lives on the inverse, `FoodItem.diaryEntries`.
    var food: FoodItem?

    init(date: Date, meal: Meal, food: FoodItem, grams: Double, portionLabel: String = "", order: Int = 0) {
        self.date = Calendar.current.startOfDay(for: date)
        self.mealRaw = meal.rawValue
        self.grams = grams
        self.portionLabel = portionLabel
        self.foodName = food.name
        self.brand = food.brand
        let scaled = food.nutrients(forGrams: grams)
        self.nutrientData = scaled.encoded()
        self.kcal = scaled.energy
        self.food = food
        self.fdcId = food.fdcId
        self.order = order
        self.createdAt = Date()
    }

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .breakfast }
        set { mealRaw = newValue.rawValue }
    }

    var nutrients: NutrientVector { NutrientVector.decode(nutrientData) }

    /// Human serving text, e.g. "1 cup (240 g)" or "150 g".
    var servingText: String {
        portionLabel.isEmpty ? "\(grams.asGrams) g" : portionLabel
    }

    /// Re-price this entry to a new gram amount + meal, refreshing the snapshot
    /// from the source food (or scaling the existing snapshot if the food was
    /// since deleted). Used by the edit sheet.
    func restate(grams newGrams: Double, meal newMeal: Meal) {
        let scaled: NutrientVector
        if let food {
            scaled = food.nutrients(forGrams: newGrams)
        } else if grams > 0 {
            scaled = nutrients.scaled(by: newGrams / grams)
        } else {
            scaled = NutrientVector()
        }
        grams = newGrams
        meal = newMeal
        kcal = scaled.energy
        nutrientData = scaled.encoded()
        portionLabel = "\(Int(newGrams.rounded())) g"
    }
}

// MARK: - Daily aggregation

enum DiaryMath {
    /// Sum the nutrient vectors of a set of diary entries.
    static func total(_ entries: [DiaryEntry]) -> NutrientVector {
        entries.reduce(NutrientVector()) { $0 + $1.nutrients }
    }
}

/// User macro/energy goals, stored in UserDefaults via `@AppStorage`.
enum NutritionGoals {
    static let energyKey = "goalEnergy"
    static let proteinKey = "goalProtein"
    static let carbsKey = "goalCarbs"
    static let fatKey = "goalFat"

    static let defaultEnergy: Double = 2000
    static let defaultProtein: Double = 150
    static let defaultCarbs: Double = 220
    static let defaultFat: Double = 65

    // MARK: Phase 2 — per-nutrient micronutrient targets

    /// UserDefaults key for a nutrient's daily target — distinct from the macro
    /// keys above. Read via `@AppStorage`; mirrored through iCloud.
    static func key(for n: Nutrient) -> String { "goal_" + n.rawValue }

    /// Auto target for a nutrient given the user's stats — the DRI for adequacy
    /// nutrients, the recommended limit for "stay-under" nutrients, else 0.
    static func defaultTarget(_ n: Nutrient, sex: Sex, age: Int) -> Double {
        n.target(sex: sex, age: age) ?? 0
    }

    /// Nutrients that receive a personalized target (vitamins, minerals, key
    /// fats, fiber) — drives onboarding writes, the iCloud mirror, and the editor.
    static let targetable: [Nutrient] =
        Nutrient.allCases.filter { $0.target(sex: .male, age: 30) != nil }
}
