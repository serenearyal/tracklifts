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
import OSLog  // OSSignposter begin/endInterval used directly in the async seed loop

enum FoodSeedManager {
    /// Imports the bundled catalog (~7,700 foods, ~20k inserts) on first launch.
    /// Async + cooperative: it `await`s `Task.yield()` between batches so the main
    /// run loop can present frames instead of freezing for the whole import.
    ///
    /// (We stay on the caller's main-actor `ModelContext` rather than a background
    /// one because the `@Model` inits — `FoodItem`/`FoodPortion`/`NutrientVector` —
    /// are MainActor-isolated under this target's default isolation, so a detached
    /// background context can't build them without changing those shared model APIs.
    /// Yielding keeps the import off the critical frame path while preserving the
    /// iOS-17 `insertPortions` discipline.)
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) async {
        // Cheap guard first: skip the decode + inserts entirely once foods exist.
        let count = (try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        guard count == 0 else { return }

        // Single source of truth: the USDA panel. If the bundled catalog is
        // missing (e.g. a checkout without the untracked JSON) seed nothing
        // rather than the macros-only curated set — that legacy catalog produced
        // friendly-named, micronutrient-empty duplicates that never reconciled
        // with the USDA foods. FoodLibrary now survives only as the offline
        // source for the friendly-name overlay (applied at seed time later).
        guard let records = catalogJSON() else { return }
        // Let the decode's frame land before the insert loop begins.
        await Task.yield()
        await seed(records, into: context)
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
    private static func seed(_ records: [CatalogRecord], into context: ModelContext) async {
        // Bracket the whole insert loop in a signpost interval so the first-launch
        // seed is a measurable interval in Instruments and its main-thread hang
        // lines up with it (Hangs / Time Profiler). Manual begin/end — the loop
        // `await`s, so it can't go through the synchronous `Perf.interval` closure.
        let signpostState = Perf.signposter.beginInterval("SeedCatalog")
        defer { Perf.signposter.endInterval("SeedCatalog", signpostState) }
        for (i, rec) in records.enumerated() {
            insert(rec, into: context)
            // Keep a few-thousand-row first launch off one giant transaction.
            if i % 500 == 499 { try? context.save() }
            // Surface the run loop periodically so the UI isn't frozen through the
            // whole multi-thousand-row import.
            if i % 200 == 199 { await Task.yield() }
        }
        try? context.save()
    }

    /// One record → a FoodItem plus its portions. Shared by the async `seed` and
    /// the synchronous `benchmarkSeed` so both run the exact same build+insert.
    @MainActor
    private static func insert(_ rec: CatalogRecord, into context: ModelContext) {
        let item = FoodItem(name: rec.name, brand: rec.brand, source: .seed,
                            per100g: NutrientVector(rec.nutrients), fdcId: rec.fdcId)
        context.insert(item)
        insertPortions(rec.portions.map { ($0.label, $0.grams) }, for: item, into: context)
    }

    // Benchmark-only: a synchronous twin of `seed` that runs the SAME per-record
    // build+insert loop (FoodItem + insertPortions) with the SAME periodic save
    // every 500 + a final save, but with NO `await`/`Task.yield()`. It exists purely
    // to measure raw insert throughput from a perf test; it is NOT used by the app's
    // first-launch path (which stays cooperative via `seed`). Cross-agent contract:
    // the name/signature below must not change.
    @MainActor
    static func benchmarkSeed(_ records: [CatalogRecord], into context: ModelContext) {
        for (i, rec) in records.enumerated() {
            insert(rec, into: context)
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
