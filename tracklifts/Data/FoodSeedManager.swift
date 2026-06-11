//
//  FoodSeedManager.swift
//  tracklifts
//
//  Imports the bundled food catalog into SwiftData on first launch. The catalog
//  is the generated USDA panel (Resources/FoodCatalog.json — full
//  micronutrients, produced by tools/usda-import.swift) and is the single source
//  of truth. No-op once foods exist. Mirrors the exercise SeedManager.
//

import Foundation
import SwiftData

enum FoodSeedManager {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        guard count == 0 else { return }

        // Single source of truth: the USDA panel. If the bundled catalog is
        // missing (e.g. a checkout without the untracked JSON) seed nothing
        // rather than the macros-only curated set — that legacy catalog produced
        // friendly-named, micronutrient-empty duplicates that never reconciled
        // with the USDA foods. FoodLibrary now survives only as the offline
        // source for the friendly-name overlay (applied at seed time later).
        guard let records = catalogJSON() else { return }
        seed(records, into: context)
    }

    // MARK: - Bundled USDA panel (Phase 2)

    private static func catalogJSON() -> [CatalogRecord]? {
        guard let url = Bundle.main.url(forResource: "FoodCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([CatalogRecord].self, from: data),
              !records.isEmpty else { return nil }
        return records
    }

    @MainActor
    private static func seed(_ records: [CatalogRecord], into context: ModelContext) {
        for (i, rec) in records.enumerated() {
            let item = FoodItem(name: rec.name, brand: rec.brand, source: .seed,
                                per100g: NutrientVector(rec.nutrients), fdcId: rec.fdcId)
            context.insert(item)
            insertPortions(rec.portions.map { ($0.label, $0.grams) }, for: item, into: context)
            // Keep a few-thousand-row first launch off one giant transaction.
            if i % 500 == 499 { try? context.save() }
        }
        try? context.save()
    }

    // MARK: - Shared portion wiring

    /// Builds portions from the to-one side only, after the food is inserted —
    /// appending to the to-many getter on a freshly built model crashes SwiftData
    /// on iOS 17.0. Always guarantees a plain 100 g serving.
    @MainActor
    private static func insertPortions(_ portions: [(label: String, grams: Double)],
                                       for item: FoodItem, into context: ModelContext) {
        var list = portions
        if !list.contains(where: { abs($0.grams - 100) < 0.001 }) {
            list.append((label: "100 g", grams: 100))
        }
        for (index, p) in list.enumerated() {
            let portion = FoodPortion(label: p.label, grams: p.grams, order: index)
            context.insert(portion)
            portion.food = item
        }
    }
}

// MARK: - Bundled catalog decoding

/// One record in Resources/FoodCatalog.json, produced by tools/usda-import.swift.
/// `nutrients` is keyed by `Nutrient.rawValue` (per 100 g).
struct CatalogRecord: Codable {
    let name: String
    let brand: String
    let fdcId: Int
    let nutrients: [String: Double]
    let portions: [CatalogPortion]
}

struct CatalogPortion: Codable { let label: String; let grams: Double }
