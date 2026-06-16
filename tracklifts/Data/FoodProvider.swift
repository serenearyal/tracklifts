//
//  FoodProvider.swift
//  tracklifts
//
//  The seam between an online food database and the SwiftData catalog (Phase 3).
//  A `FoodProvider` resolves a barcode or a text query to plain `RemoteFood`
//  values; callers (FoodSearchView) upsert those into `FoodItem`s. The protocol
//  keeps the source swappable — Open Food Facts now, a paid API later — without
//  touching the UI or the model.
//

import Foundation

/// A branded/packaged food resolved from a remote source, normalized to the same
/// per-100 g shape the catalog stores. No SwiftData here — this is the boundary.
struct RemoteFood: Equatable, Identifiable {
    var name: String
    var brand: String
    var barcode: String
    var per100g: NutrientVector
    /// Grams in one labelled serving (0 = unknown).
    var servingGrams: Double

    /// Stable identity for `ForEach` — the GTIN when present, else a name+brand
    /// composite (results without a barcode still get a deterministic key).
    var id: String { barcode.isEmpty ? "\(name)|\(brand)" : barcode }
}

protocol FoodProvider {
    /// Resolve a scanned GTIN to a product, or nil if not found / offline.
    func lookup(barcode: String) async -> RemoteFood?
    /// Branded text search; empty on miss / offline.
    func search(_ query: String) async -> [RemoteFood]
}

/// The app's default provider. One indirection so views don't hardcode a vendor.
enum FoodProviders {
    static let shared: FoodProvider = OpenFoodFactsProvider()
}
