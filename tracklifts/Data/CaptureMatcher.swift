//
//  CaptureMatcher.swift
//  tracklifts
//
//  Phase 4 — resolve parsed meal items against the catalog. Each `ParsedItem`
//  (from text/voice heuristic or the photo model) becomes a `CaptureMatch`: the
//  best `FoodItem` from `FoodSearch`, the gram amount to log, and a readable
//  portion label. Nutrition always comes from the matched catalog food — the
//  parser never invents numbers. The confirm sheet renders these and lets the
//  user fix the match / amount before committing.
//

import Foundation
import SwiftData

/// A parsed item resolved to a (possibly nil) catalog food + the grams we'll log.
/// `isEstimated` is true when `food` is an AI-estimated custom food built from the
/// photo model's nutrition (not yet in the store) — the confirm sheet badges it and
/// inserts it on commit.
struct CaptureMatch: Identifiable {
    let id = UUID()
    var parsed: ParsedItem
    var food: FoodItem?
    var grams: Double
    var portionLabel: String
    var isEstimated: Bool = false

    var isMatched: Bool { food != nil }
}

enum CaptureMatcher {
    /// Match every parsed item to the catalog (best `FoodSearch` hit) and resolve
    /// grams. When there's no catalog hit but the photo model estimated nutrition,
    /// fall back to a custom food built from that estimate so the item is still
    /// loggable — a glazed donut that isn't in the catalog still gets full macros.
    @MainActor
    static func match(_ items: [ParsedItem], in context: ModelContext) -> [CaptureMatch] {
        items.map { item in
            if let food = FoodSearch.run(item.name, in: context, limit: 8).first {
                let resolved = resolveGrams(item, food: food)
                return CaptureMatch(parsed: item, food: food, grams: resolved.grams, portionLabel: resolved.label)
            }
            if let estimate = item.estimatedPer100g {
                let food = estimatedFood(named: item.name, per100g: estimate)
                let resolved = resolveGrams(item, food: food)
                return CaptureMatch(parsed: item, food: food, grams: resolved.grams,
                                    portionLabel: resolved.label, isEstimated: true)
            }
            let resolved = resolveGrams(item, food: nil)
            return CaptureMatch(parsed: item, food: nil, grams: resolved.grams, portionLabel: resolved.label)
        }
    }

    /// An un-inserted custom `FoodItem` carrying the model's per-100 g estimate.
    /// It's only inserted into the store at commit (`CaptureConfirmList.commit`), so
    /// a cancelled review leaves nothing behind. Deliberately given no portions here
    /// — appending to a to-many on an un-inserted model is the iOS-17 hazard; the
    /// commit attaches a portion after insert. `resolveGrams` uses the item's
    /// `gramsHint` (always set alongside an estimate), so it never reads `portions`.
    @MainActor
    static func estimatedFood(named name: String, per100g: NutrientVector) -> FoodItem {
        FoodItem(name: name, source: .custom, per100g: per100g, isCustom: true)
    }

    /// Grams for a parsed item, in priority order: an explicit hint (photo model),
    /// then a direct mass/volume unit conversion, then a portion on the matched
    /// food whose label mentions the unit, then the food's default portion × qty,
    /// then a bare 100 g × qty so an unmatched row still shows a sane number.
    /// Pure (no SwiftData) so it unit-tests without a container.
    static func resolveGrams(_ item: ParsedItem, food: FoodItem?) -> (grams: Double, label: String) {
        let qty = item.quantity > 0 ? item.quantity : 1

        if let hint = item.gramsHint, hint > 0 {
            return (hint, gramLabel(hint))
        }

        // Universal mass/volume units convert without needing a portion.
        if let perUnit = unitGrams[item.unit] {
            let grams = perUnit * qty
            return (grams, "\(fmt(qty)) \(item.unit)")
        }

        if let food {
            // A descriptive unit ("slice", "cup") that the food defines a portion for.
            if !item.unit.isEmpty,
               let portion = food.orderedPortions.first(where: { $0.label.lowercased().contains(item.unit) }) {
                return (portion.grams * qty, multiplied(qty, portion.label))
            }
            // Bare count ("2 eggs") → default serving × quantity.
            let portion = food.defaultPortion
            return (portion.grams * qty, multiplied(qty, portion.label))
        }

        let grams = 100 * qty
        return (grams, gramLabel(grams))
    }

    /// Grams per one unit. Volumes use common cooking densities (water-ish); the
    /// confirm sheet lets the user correct anything off. Descriptive units
    /// (slice/medium/…) are intentionally absent — they resolve via food portions.
    static let unitGrams: [String: Double] = [
        "g": 1, "kg": 1000, "mg": 0.001,
        "oz": 28.35, "lb": 453.6,
        "ml": 1, "l": 1000,
        "cup": 240, "tbsp": 15, "tsp": 5,
    ]

    // MARK: Labels

    private static func gramLabel(_ grams: Double) -> String { "\(Int(grams.rounded())) g" }

    private static func multiplied(_ qty: Double, _ portionLabel: String) -> String {
        qty == 1 ? portionLabel : "\(fmt(qty))× \(portionLabel)"
    }

    private static func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}
