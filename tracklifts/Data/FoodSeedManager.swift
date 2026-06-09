//
//  FoodSeedManager.swift
//  tracklifts
//
//  Imports the bundled food catalog into SwiftData on first launch. Mirrors the
//  exercise SeedManager: a no-op once foods exist.
//

import Foundation
import SwiftData

enum FoodSeedManager {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        guard count == 0 else { return }

        for seed in FoodLibrary.all {
            let item = FoodItem(name: seed.name, brand: seed.brand, source: .seed, per100g: seed.per100g)
            context.insert(item)

            var seedPortions = seed.portions
            // Always offer a plain 100 g serving.
            if !seedPortions.contains(where: { abs($0.grams - 100) < 0.001 }) {
                seedPortions.append(SeedPortion("100 g", 100))
            }
            // Build the relationship from the to-one side only (and after both
            // models are inserted) — appending to the to-many getter on a freshly
            // built model crashes SwiftData on iOS 17.0.
            for (index, sp) in seedPortions.enumerated() {
                let portion = FoodPortion(label: sp.label, grams: sp.grams, order: index)
                context.insert(portion)
                portion.food = item
            }
        }
        try? context.save()
    }
}
