//
//  FoodVisionProvider.swift
//  tracklifts
//
//  Phase 4 — AI meal capture (decision D2). Two providers turn a meal into the same
//  `[ParsedItem]` the on-device parser produces, so both flow through the identical
//  match → confirm → log path:
//    • `FoodVisionProvider` — a meal *photo* → items (cloud Gemini).
//    • `FoodTextProvider`   — a typed/spoken *description* → items (cloud Gemini).
//  Both leave the device, so they sit behind an explicit opt-in in the UI. The model
//  only proposes food names + portion/gram + nutrition *estimates*; a confident
//  catalog match still overrides the estimate downstream (see `CaptureMatcher`).
//  The protocols keep the vendor swappable, mirroring `FoodProvider`.
//

import Foundation

// MARK: - Protocols

protocol FoodVisionProvider {
    /// Identify the foods in a JPEG image. `note` is optional free-text context the
    /// photographer added (e.g. hidden add-ins the camera can't see) — folded into
    /// the request. Throws on misconfiguration / network / decode failure so the UI
    /// can show a precise message.
    func recognize(_ jpeg: Data, note: String?) async throws -> [ParsedItem]
}

protocol FoodTextProvider {
    /// Estimate the foods + nutrition in a free-text meal description ("a large coffee
    /// with whole milk and 2 sugars"). Same output shape as the photo path — each item
    /// carries an AI per-100 g estimate + gram hint — so it flows through the identical
    /// match → confirm → log path. Throws on misconfiguration / network / decode failure.
    func estimate(description: String) async throws -> [ParsedItem]
}

enum FoodVision {
    static let shared: FoodVisionProvider = GeminiFoodVision()
}

enum FoodText {
    static let shared: FoodTextProvider = GeminiFoodText()
}

enum FoodVisionError: LocalizedError {
    case notConfigured, badResponse, empty

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Add your Gemini API key to enable AI estimation."
        case .badResponse:   "Couldn’t read that — try again or be more specific."
        case .empty:         "No foods found."
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

// MARK: - Shared Gemini plumbing

/// The networking + decode shared by the photo and text providers, which differ only
/// in the prompt and the request payload (an image part vs. text-only).
enum GeminiFood {
    /// The JSON-schema instructions both prompts share — defines the wire shape the
    /// model must return. Worded neutrally ("for that item") so it reads for a photo
    /// ("as shown") or a description ("as described").
    static let schemaInstructions = """
    Return ONLY a JSON array. Each element must be:
    {"name": string, "quantity": number, "unit": string, "grams": number,
     "kcal": number, "protein": number, "carbs": number, "fat": number,
     "fiber": number, "sugar": number, "satFat": number, "sodium": number}
    - name: the common food name, singular, no brand (e.g. "scrambled eggs", "white rice", "glazed donut").
    - quantity + unit: a natural portion if obvious (e.g. 2 "slice", 1 "cup"); otherwise quantity 1 and unit "".
    - grams: your best estimate of the TOTAL edible weight in grams for that item.
    - kcal, protein, carbs, fat, fiber, sugar, satFat (all grams except kcal), sodium (milligrams):
      your best estimate of the TOTAL nutrition for that item — NOT per 100 g. Always fill
      these in from your nutrition knowledge, even for foods that are in no database (e.g. a glazed
      donut). Never use null or 0 for kcal — give a real numeric estimate.
    If you cannot identify any food, return [].
    """

    /// POST a prepared request to Gemini and decode it into `ParsedItem`s. Throws on
    /// misconfiguration / network / decode failure so the caller can react precisely.
    static func send(_ request: GeminiRequest) async throws -> [ParsedItem] {
        guard let key = GeminiConfig.apiKey else { throw FoodVisionError.notConfigured }

        // Key goes in the `x-goog-api-key` header, not the URL query string, so it
        // can't leak into proxy/server URL logs. (A shipped build should still proxy
        // this through a backend so no key ships in the binary at all.)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiConfig.model):generateContent")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONEncoder().encode(request)

        // One bounded retry with a short backoff on transient server errors
        // (overload / 5xx); any other non-2xx surfaces as `.badResponse` as before.
        var (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, [429, 500, 502, 503].contains(http.statusCode) {
            try await Task.sleep(for: .milliseconds(600))
            (data, response) = try await URLSession.shared.data(for: req)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FoodVisionError.badResponse
        }
        guard let text = (try? JSONDecoder().decode(GeminiResponse.self, from: data))?.firstText else {
            throw FoodVisionError.badResponse
        }
        let items = decodeItems(from: text)
        guard !items.isEmpty else { throw FoodVisionError.empty }
        return items
    }

    /// The model returns a JSON array as text (occasionally fenced) — strip any
    /// ``` fences, decode, and normalize into `ParsedItem`s (grams as a hint).
    /// Internal (not private) so it's hermetically testable without the network.
    static func decodeItems(from text: String) -> [ParsedItem] {
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
        // The model's numbers are untrusted: bound grams + energy and drop any
        // non-finite / negative macro so a bad response can't poison the stored
        // food or trap a later `Int(...)` display conversion. `fromPerServing`
        // applies a final per-100 g cap as a backstop.
        func clean(_ v: Double?) -> Double {
            guard let v, v.isFinite, v >= 0 else { return 0 }
            return min(v, 100_000)
        }
        guard let grams = item.grams, grams.isFinite, grams > 0, grams <= 10_000,
              let kcal = item.kcal, kcal.isFinite, kcal > 0, kcal <= 100_000 else { return nil }
        let totals: [String: Double] = [
            Nutrient.energy.rawValue:  kcal,
            Nutrient.protein.rawValue: clean(item.protein),
            Nutrient.carbs.rawValue:   clean(item.carbs),
            Nutrient.fat.rawValue:     clean(item.fat),
            Nutrient.fiber.rawValue:   clean(item.fiber),
            Nutrient.sugar.rawValue:   clean(item.sugar),
            Nutrient.satFat.rawValue:  clean(item.satFat),
            Nutrient.sodium.rawValue:  clean(item.sodium),
        ]
        return NutrientVector.fromPerServing(totals, servingGrams: grams)
    }
}

// MARK: - Photo provider

struct GeminiFoodVision: FoodVisionProvider {

    private static let intro =
        "You are a nutrition assistant. Identify each distinct food or drink in this meal photo."

    /// Full prompt for one request. A non-empty `note` is the photographer's own
    /// context (e.g. add-ins a camera can't see) — folded in as authoritative, then
    /// we reaffirm JSON-only so the response format stays intact regardless of it.
    private static func prompt(note: String?) -> String {
        var p = intro + "\n" + GeminiFood.schemaInstructions
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            p += """


            Additional context from the person who took the photo — treat it as
            authoritative. Incorporate it into your answer: add any foods, toppings, or
            extras they mention even if they are not clearly visible, and adjust portions
            or preparation to match:
            "\(note)"

            Return ONLY the JSON array described above.
            """
        }
        return p
    }

    func recognize(_ jpeg: Data, note: String?) async throws -> [ParsedItem] {
        try await GeminiFood.send(GeminiRequest(prompt: Self.prompt(note: note), jpeg: jpeg))
    }
}

// MARK: - Text provider

struct GeminiFoodText: FoodTextProvider {

    /// The description is the authoritative input (like the photo note): use exactly
    /// the foods, brands, quantities and preparation stated, then reaffirm JSON-only.
    private static func prompt(description: String) -> String {
        """
        You are a nutrition assistant. Identify each distinct food or drink in the meal the
        person describes below, and estimate its nutrition. Treat the description as
        authoritative — use the foods, brands, quantities, and preparation they state; only
        fill gaps with typical assumptions.
        \(GeminiFood.schemaInstructions)

        Meal description:
        "\(description)"

        Return ONLY the JSON array described above.
        """
    }

    func estimate(description: String) async throws -> [ParsedItem] {
        let desc = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        guard !desc.isEmpty else { throw FoodVisionError.empty }
        return try await GeminiFood.send(GeminiRequest(prompt: Self.prompt(description: desc)))
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

struct GeminiRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig

    /// Photo request: a text prompt + an inline JPEG part.
    init(prompt: String, jpeg: Data) {
        contents = [Content(parts: [
            Part(text: prompt, inlineData: nil),
            Part(text: nil, inlineData: InlineData(mimeType: "image/jpeg", data: jpeg.base64EncodedString())),
        ])]
        generationConfig = GenerationConfig()
    }

    /// Text request: a single text prompt part, no image.
    init(prompt: String) {
        contents = [Content(parts: [Part(text: prompt, inlineData: nil)])]
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
