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
            // Photo item: the model already estimated this food's nutrition. Trust that
            // by default — a fuzzy catalog hit on a USDA name is unreliable (plain "coffee"
            // substring-matches a coffee *liqueur*). Only override the estimate with a
            // catalog food we're confident is the same food (right name AND comparable
            // energy density); otherwise log the estimate as before.
            if let estimate = item.estimatedPer100g {
                if let food = confidentMatch(for: item, estimate: estimate, in: context) {
                    let resolved = resolveGrams(item, food: food)
                    return CaptureMatch(parsed: item, food: food, grams: resolved.grams, portionLabel: resolved.label)
                }
                let food = estimatedFood(named: item.name, per100g: estimate)
                let resolved = resolveGrams(item, food: food)
                return CaptureMatch(parsed: item, food: food, grams: resolved.grams,
                                    portionLabel: resolved.label, isEstimated: true)
            }

            // Text/voice item: no estimate to fall back on — take the best catalog hit,
            // else an unmatched row that still carries sane grams.
            if let food = FoodSearch.run(item.name, in: context, limit: 8).first {
                let resolved = resolveGrams(item, food: food)
                return CaptureMatch(parsed: item, food: food, grams: resolved.grams, portionLabel: resolved.label)
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

    // MARK: Confident catalog match (photo items)

    /// A catalog food we trust enough to override the photo model's own estimate. Two
    /// gates, both required, because USDA names defeat plain text search ("coffee"
    /// substring-matches a coffee *liqueur*):
    ///  • the name must plausibly BE the queried food (`nameMatchCoverage`), and
    ///  • its energy density must sit near the model's estimate (`densitiesClose`) —
    ///    which cleanly rejects the liqueur (336 kcal/100 g vs a ~50 kcal/100 g coffee).
    /// Returns nil → the caller keeps the AI estimate. The candidate set is generous;
    /// `match` runs once per capture on a handful of items, so the cost is trivial.
    @MainActor
    static func confidentMatch(for item: ParsedItem, estimate: NutrientVector,
                               in context: ModelContext) -> FoodItem? {
        FoodSearch.run(item.name, in: context, limit: 200).first { food in
            guard let coverage = nameMatchCoverage(food.name, query: item.name), coverage >= 0.5
            else { return false }
            return densitiesClose(food.kcalPer100g, estimate.energy)
        }
    }

    /// How much of a catalog name the query accounts for, or nil if the query isn't
    /// fully present. Both sides are tokenized (lowercased, split on non-alphanumerics,
    /// 2+ chars); every query token must prefix-match a name token in either direction,
    /// so "banana"≈"Bananas" and "egg"≈"Eggs". Coverage = queryTokens / nameTokens, so a
    /// short query buried in a long, qualifier-heavy name (the liqueur) scores low.
    static func nameMatchCoverage(_ name: String, query: String) -> Double? {
        let nameTokens = tokenize(name)
        let queryTokens = tokenize(query)
        guard !nameTokens.isEmpty, !queryTokens.isEmpty else { return nil }
        let allPresent = queryTokens.allSatisfy { q in
            nameTokens.contains { $0.hasPrefix(q) || q.hasPrefix($0) }
        }
        guard allPresent else { return nil }
        return Double(queryTokens.count) / Double(nameTokens.count)
    }

    /// Two per-100 g energies are "close" when both are positive and the larger is at
    /// most `maxRatio`× the smaller — a coarse same-food sanity check on the AI estimate.
    static func densitiesClose(_ a: Double, _ b: Double, maxRatio: Double = 2.0) -> Bool {
        guard a > 0, b > 0 else { return false }
        return max(a, b) / min(a, b) <= maxRatio
    }

    private static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
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
