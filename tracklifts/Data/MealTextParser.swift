//
//  MealTextParser.swift
//  tracklifts
//
//  Phase 4 — on-device natural-language meal parsing. Turns a free-text meal
//  description ("2 eggs, a cup of oatmeal with blueberries, 200g chicken") into a
//  list of `{name, quantity, unit}` references. There is NO nutrition here — the
//  parser only proposes a query + portion against the catalog (Principle 2); the
//  matched `FoodItem` supplies the nutrients (see `CaptureMatcher`). Pure +
//  synchronous so it runs fully offline on any iOS version and is trivially tested.
//

import Foundation

/// One parsed food reference. `gramsHint` is non-nil only when the source already
/// knows a gram weight (the photo model returns grams); the heuristic leaves it
/// nil and lets `CaptureMatcher` resolve grams from the matched food's portions.
/// `estimatedPer100g` is non-nil only when the photo model also estimated the
/// item's nutrition — it lets `CaptureMatcher` log a food that isn't in the
/// catalog (e.g. a glazed donut). The on-device heuristic never sets it.
struct ParsedItem: Equatable {
    var name: String
    var quantity: Double
    var unit: String          // canonical token ("cup", "g", …); "" = bare count
    var gramsHint: Double?
    var estimatedPer100g: NutrientVector?

    init(name: String, quantity: Double = 1, unit: String = "",
         gramsHint: Double? = nil, estimatedPer100g: NutrientVector? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.gramsHint = gramsHint
        self.estimatedPer100g = estimatedPer100g
    }
}

enum MealTextParser {
    /// Split a free-text meal into parsed items. Empty/whitespace → `[]`.
    static func parse(_ text: String) -> [ParsedItem] {
        segments(of: text).compactMap { parseSegment($0) }
    }

    // MARK: Segmentation

    /// One control char stands in for every separator, then we split on it. Word
    /// separators ("and"/"with"/"plus") require surrounding spaces so "sandwich"
    /// and "kiwi" never split mid-word.
    private static func segments(of text: String) -> [String] {
        let sep = "\u{1}"
        // Built locally (a `(?i)`-prefixed regex literal confuses the parser, and a
        // non-Sendable static `Regex` trips strict-concurrency checks). Compiling a
        // ~40-char pattern on a user-initiated parse is free.
        let joined: String
        if let regex = try? Regex(#"(?i)\s+(?:and|with|plus)\s+|[,\n+&]+"#) {
            joined = text.replacing(regex, with: sep)
        } else {
            joined = text.replacing(",", with: sep)
        }
        return joined
            .split(separator: Character(sep))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: Per-segment

    private static func parseSegment(_ raw: String) -> ParsedItem? {
        var tokens = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var quantity = 1.0
        var unit = ""

        // 1) Fused number+unit as the first token, e.g. "200g", "8oz", "250ml".
        if let fused = splitFusedQuantity(tokens[0]) {
            quantity = fused.quantity
            unit = fused.unit
            if let rest = fused.rest { tokens[0] = rest } else { tokens.removeFirst() }
        } else if let number = numberWord(tokens[0]) {
            // 2) Standalone leading number / written word / fraction ("2", "a", "1/2").
            quantity = number
            tokens.removeFirst()
            // An article between the number and the unit: "half *a* cup of rice".
            if let first = tokens.first?.lowercased(), first == "a" || first == "an" {
                tokens.removeFirst()
            }
            // 3) A unit token right after the number, e.g. "2 cups".
            if let first = tokens.first, let u = canonicalUnit(first) {
                unit = u
                tokens.removeFirst()
            }
        }

        // 4) Drop a leading filler word: "a cup *of* oatmeal", "*some* rice".
        if let first = tokens.first?.lowercased(), fillers.contains(first) {
            tokens.removeFirst()
        }

        let name = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return ParsedItem(name: name, quantity: quantity, unit: unit)
    }

    // MARK: Quantity parsing

    /// "200g" → (200, "g", nil); "8oz" → (8, "oz", nil); non-numeric lead or an
    /// unknown-unit suffix → nil so the caller treats the token as a plain name.
    private static func splitFusedQuantity(_ token: String) -> (quantity: Double, unit: String, rest: String?)? {
        // Leading numeric run (digits + at most one dot).
        var i = token.startIndex
        var sawDot = false
        while i < token.endIndex, token[i].isNumber || (token[i] == "." && !sawDot) {
            if token[i] == "." { sawDot = true }
            i = token.index(after: i)
        }
        guard i > token.startIndex else { return nil }                  // no leading digit
        let numberPart = token[token.startIndex..<i]

        // Immediately-following letters are the candidate unit.
        var u = i
        while u < token.endIndex, token[u].isLetter { u = token.index(after: u) }
        guard u > i, let unit = canonicalUnit(String(token[i..<u])) else { return nil }

        let quantity = Double(numberPart) ?? 1
        let rest = String(token[u...])
        return (quantity, unit, rest.isEmpty ? nil : rest)
    }

    /// A leading number as a digit ("2", "1.5"), fraction ("1/2", "½", "1½"), or
    /// written word ("a", "two", "half", "dozen"). Returns nil if not a number.
    private static func numberWord(_ token: String) -> Double? {
        let t = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        if let d = Double(t) { return d }
        if t.contains("/") {
            let parts = t.split(separator: "/")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        }
        if let frac = unicodeFractions[t] { return frac }
        if let last = t.last, let frac = unicodeFractions[String(last)], let whole = Double(t.dropLast()) {
            return whole + frac          // mixed like "1½"
        }
        return writtenNumbers[t]
    }

    // MARK: Units

    /// Normalize a unit token to its canonical form, or nil if it isn't a unit.
    static func canonicalUnit(_ token: String) -> String? {
        let t = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,()"))
        return unitSynonyms[t]
    }

    private static let fillers: Set<String> = ["of", "some", "the"]

    private static let unicodeFractions: [String: Double] = [
        "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125,
    ]

    private static let writtenNumbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "half": 0.5, "quarter": 0.25, "couple": 2, "dozen": 12,
    ]

    /// Synonym/plural → canonical unit token. Canonical tokens that name a real
    /// mass/volume convert directly (see `CaptureMatcher.unitGrams`); descriptive
    /// ones (slice/medium/bowl…) resolve against the matched food's portions.
    static let unitSynonyms: [String: String] = {
        let groups: [String: [String]] = [
            "g":       ["g", "gram", "grams", "gm", "gms"],
            "kg":      ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"],
            "mg":      ["mg", "milligram", "milligrams"],
            "oz":      ["oz", "ounce", "ounces"],
            "lb":      ["lb", "lbs", "pound", "pounds"],
            "ml":      ["ml", "milliliter", "milliliters", "millilitre", "millilitres"],
            "l":       ["l", "liter", "liters", "litre", "litres"],
            "cup":     ["cup", "cups"],
            "tbsp":    ["tbsp", "tbs", "tablespoon", "tablespoons"],
            "tsp":     ["tsp", "teaspoon", "teaspoons"],
            "slice":   ["slice", "slices"],
            "piece":   ["piece", "pieces", "pcs", "pc"],
            "medium":  ["medium", "med"],
            "large":   ["large", "lg"],
            "small":   ["small", "sm"],
            "bowl":    ["bowl", "bowls"],
            "glass":   ["glass", "glasses"],
            "can":     ["can", "cans"],
            "bottle":  ["bottle", "bottles"],
            "scoop":   ["scoop", "scoops"],
            "handful": ["handful", "handfuls"],
            "serving": ["serving", "servings", "serve"],
            "clove":   ["clove", "cloves"],
            "stick":   ["stick", "sticks"],
        ]
        var map: [String: String] = [:]
        for (canonical, synonyms) in groups {
            for s in synonyms { map[s] = canonical }
        }
        return map
    }()
}
