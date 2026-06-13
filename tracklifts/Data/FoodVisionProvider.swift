//
//  FoodVisionProvider.swift
//  tracklifts
//
//  Phase 4 — photo capture (decision D2). A `FoodVisionProvider` turns a meal
//  photo into the same `[ParsedItem]` the on-device text/voice parser produces, so
//  it flows through the identical match → confirm → log path. This is the one
//  capture mode that may leave the device (cloud Gemini), so it sits behind an
//  explicit opt-in in the UI. The model only proposes food names + portion/gram
//  estimates; nutrients always come from the matched catalog food (Principle 2).
//  The protocol keeps the vendor swappable, mirroring `FoodProvider`.
//

import Foundation

protocol FoodVisionProvider {
    /// Identify the foods in a JPEG image. Throws on misconfiguration / network /
    /// decode failure so the UI can show a precise message.
    func recognize(_ jpeg: Data) async throws -> [ParsedItem]
}

enum FoodVision {
    static let shared: FoodVisionProvider = GeminiFoodVision()
}

enum FoodVisionError: LocalizedError {
    case notConfigured, badResponse, empty

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Add your Gemini API key to enable photo recognition."
        case .badResponse:   "Couldn’t read the photo — try again or use a clearer shot."
        case .empty:         "No foods found in that photo."
        }
    }
}

/// Reads the Gemini key + model name. The key is kept out of the binary for dev:
/// a `GEMINI_API_KEY` scheme env var (simulator), else a gitignored `Secrets.plist`
/// (`GeminiAPIKey`). A shipped build should proxy through a backend instead.
enum GeminiConfig {
    /// Best-value multimodal model: frontier-class accuracy at a budget price
    /// ($0.25/$1.50 per 1M tok as of 2026-06). Swap freely — any stable Gemini
    /// Developer API model id works here (e.g. "gemini-2.5-flash-lite" is cheaper,
    /// "gemini-3.5-flash" is more accurate).
    static let model = "gemini-3.1-flash-lite"

    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !env.isEmpty { return env }
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict["GeminiAPIKey"] as? String, !key.isEmpty {
            return key
        }
        return nil
    }

    static var isConfigured: Bool { apiKey != nil }
}

struct GeminiFoodVision: FoodVisionProvider {

    private static let prompt = """
    You are a nutrition assistant. Identify each distinct food or drink in this meal photo.
    Return ONLY a JSON array. Each element must be:
    {"name": string, "quantity": number, "unit": string, "grams": number,
     "kcal": number, "protein": number, "carbs": number, "fat": number,
     "fiber": number, "sugar": number, "satFat": number, "sodium": number}
    - name: the common food name, singular, no brand (e.g. "scrambled eggs", "white rice", "glazed donut").
    - quantity + unit: a natural portion if obvious (e.g. 2 "slice", 1 "cup"); otherwise quantity 1 and unit "".
    - grams: your best estimate of the TOTAL edible weight in grams for that item as shown.
    - kcal, protein, carbs, fat, fiber, sugar, satFat (all grams except kcal), sodium (milligrams):
      your best estimate of the TOTAL nutrition for that item as shown — NOT per 100 g. Always fill
      these in from your nutrition knowledge, even for foods that are in no database (e.g. a glazed
      donut). Never use null or 0 for kcal — give a real numeric estimate.
    If you cannot identify any food, return [].
    """

    func recognize(_ jpeg: Data) async throws -> [ParsedItem] {
        guard let key = GeminiConfig.apiKey else { throw FoodVisionError.notConfigured }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiConfig.model):generateContent?key=\(key)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(GeminiRequest(prompt: Self.prompt, jpeg: jpeg))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FoodVisionError.badResponse
        }

        guard let text = (try? JSONDecoder().decode(GeminiResponse.self, from: data))?.firstText else {
            throw FoodVisionError.badResponse
        }
        let items = Self.decodeItems(from: text)
        guard !items.isEmpty else { throw FoodVisionError.empty }
        return items
    }

    /// The model returns a JSON array as text (occasionally fenced) — strip any
    /// ``` fences, decode, and normalize into `ParsedItem`s (grams as a hint).
    private static func decodeItems(from text: String) -> [ParsedItem] {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            json = json.replacingOccurrences(of: "```json", with: "")
                       .replacingOccurrences(of: "```", with: "")
                       .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let raw = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([VisionItem].self, from: raw) else { return [] }

        return decoded.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let unit = item.unit.flatMap { MealTextParser.canonicalUnit($0) ?? ($0.isEmpty ? nil : $0.lowercased()) } ?? ""
            return ParsedItem(name: name, quantity: item.quantity ?? 1, unit: unit,
                              gramsHint: item.grams, estimatedPer100g: estimate(from: item))
        }
    }

    /// Turn the model's TOTAL nutrition for the item-as-shown into a per-100 g
    /// vector (the form the catalog stores). Returns nil unless we have both a
    /// positive weight and positive energy — without those the estimate isn't
    /// trustworthy enough to log, so the row falls back to a plain "no match".
    /// Reuses `NutrientVector.fromPerServing`, the same per-serving → per-100 g
    /// conversion the custom-food editor uses.
    private static func estimate(from item: VisionItem) -> NutrientVector? {
        guard let grams = item.grams, grams > 0, let kcal = item.kcal, kcal > 0 else { return nil }
        let totals: [String: Double] = [
            Nutrient.energy.rawValue:  kcal,
            Nutrient.protein.rawValue: item.protein ?? 0,
            Nutrient.carbs.rawValue:   item.carbs ?? 0,
            Nutrient.fat.rawValue:     item.fat ?? 0,
            Nutrient.fiber.rawValue:   item.fiber ?? 0,
            Nutrient.sugar.rawValue:   item.sugar ?? 0,
            Nutrient.satFat.rawValue:  item.satFat ?? 0,
            Nutrient.sodium.rawValue:  item.sodium ?? 0,
        ]
        return NutrientVector.fromPerServing(totals, servingGrams: grams)
    }
}

// MARK: - Wire formats

private struct VisionItem: Decodable {
    let name: String
    let quantity: Double?
    let unit: String?
    let grams: Double?
    // Total nutrition for the item as shown (kcal + grams, sodium in mg). Optional
    // so a model that omits any field still decodes; missing → 0 in the estimate.
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fiber: Double?
    let sugar: Double?
    let satFat: Double?
    let sodium: Double?
}

private struct GeminiRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig

    init(prompt: String, jpeg: Data) {
        contents = [Content(parts: [
            Part(text: prompt, inlineData: nil),
            Part(text: nil, inlineData: InlineData(mimeType: "image/jpeg", data: jpeg.base64EncodedString())),
        ])]
        generationConfig = GenerationConfig()
    }

    struct Content: Encodable { let parts: [Part] }
    struct Part: Encodable {
        let text: String?
        let inlineData: InlineData?
        enum CodingKeys: String, CodingKey { case text; case inlineData = "inline_data" }
    }
    struct InlineData: Encodable {
        let mimeType: String
        let data: String
        enum CodingKeys: String, CodingKey { case mimeType = "mime_type"; case data }
    }
    struct GenerationConfig: Encodable {
        let responseMimeType = "application/json"
        let temperature = 0.2
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]?

    /// Concatenated text of the first candidate's parts.
    var firstText: String? {
        guard let parts = candidates?.first?.content?.parts else { return nil }
        let joined = parts.compactMap(\.text).joined()
        return joined.isEmpty ? nil : joined
    }

    struct Candidate: Decodable { let content: Content? }
    struct Content: Decodable { let parts: [Part]? }
    struct Part: Decodable { let text: String? }
}
