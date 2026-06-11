//
//  OpenFoodFacts.swift
//  tracklifts
//
//  `FoodProvider` backed by Open Food Facts (public, ODbL). Barcode + text-search
//  lookups over HTTPS; the nutriment → `NutrientVector` mapping is pure and unit-
//  tested (kcal/kJ, salt→sodium, gram→mg minerals). OFF micro coverage is spotty,
//  so only present values are mapped — nutrients are never invented.
//
//  Attribution: foods sourced here are tagged `.openFoodFacts` and surfaced with
//  an ODbL credit in the UI.
//

import Foundation

struct OpenFoodFactsProvider: FoodProvider {
    /// OFF asks for a descriptive User-Agent identifying the app + a contact.
    private static let userAgent = "TrackLifts/1.0 (serene.aryal24@gmail.com)"
    private static let host = "https://world.openfoodfacts.org"
    private static let fields = "code,product_name,brands,nutriments,serving_quantity"

    func lookup(barcode: String) async -> RemoteFood? {
        let gtin = barcode.filter(\.isNumber)
        guard gtin.count >= 8 else { return nil }
        var c = URLComponents(string: "\(Self.host)/api/v2/product/\(gtin).json")!
        c.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        guard let data = await Self.get(c.url) else { return nil }
        return Self.decodeProduct(data, fallbackBarcode: gtin)
    }

    func search(_ query: String) async -> [RemoteFood] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        var c = URLComponents(string: "\(Self.host)/cgi/search.pl")!
        c.queryItems = [
            URLQueryItem(name: "search_terms", value: q),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: Self.fields),
        ]
        guard let data = await Self.get(c.url) else { return [] }
        return Self.decodeSearch(data)
    }

    // MARK: - Networking

    private static func get(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil // offline / timeout — caller shows "not found"
        }
    }

    // MARK: - Decoding (internal for hermetic tests — no live network)

    static func decodeProduct(_ data: Data, fallbackBarcode: String) -> RemoteFood? {
        guard let resp = try? JSONDecoder().decode(OFFProductResponse.self, from: data),
              resp.status == 1, let product = resp.product else { return nil }
        // The v2 product endpoint returns the canonical `code` at the top level
        // (the `product` object often omits it); prefer it over the scanned GTIN.
        return remoteFood(from: product, fallbackBarcode: resp.code ?? fallbackBarcode)
    }

    static func decodeSearch(_ data: Data) -> [RemoteFood] {
        guard let resp = try? JSONDecoder().decode(OFFSearchResponse.self, from: data) else { return [] }
        return resp.products
            .compactMap { remoteFood(from: $0, fallbackBarcode: $0.code ?? "") }
            .filter { !$0.barcode.isEmpty }
    }

    private static func remoteFood(from p: OFFProduct, fallbackBarcode: String) -> RemoteFood? {
        let name = (p.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil } // a product with no name isn't loggable
        // Drop unit/string entries (e.g. "energy_unit": "kcal") — keep only numbers.
        let numeric = (p.nutriments ?? [:]).compactMapValues(\.value)
        // OFF lists multiple brands comma-separated; take the first.
        let brand = (p.brands ?? "").split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return RemoteFood(name: name, brand: brand,
                          barcode: p.code ?? fallbackBarcode,
                          per100g: mapNutriments(numeric),
                          servingGrams: max(0, p.servingQuantity?.value ?? 0))
    }

    /// Pure: OFF per-100 g nutriments → our `NutrientVector`. Unit-tested.
    /// Only maps values actually present (never invents a nutrient).
    static func mapNutriments(_ n: [String: Double]) -> NutrientVector {
        var v: [String: Double] = [:]
        func set(_ nutrient: Nutrient, _ key: String, scale: Double = 1) {
            if let x = n[key] { v[nutrient.rawValue] = x * scale }
        }
        // Energy: prefer kcal; otherwise convert kJ (1 kcal = 4.184 kJ).
        if let kcal = n["energy-kcal_100g"] { v[Nutrient.energy.rawValue] = kcal }
        else if let kj = n["energy_100g"] { v[Nutrient.energy.rawValue] = kj / 4.184 }
        // Macros — OFF reports these in grams per 100 g already.
        set(.protein, "proteins_100g")
        set(.carbs, "carbohydrates_100g")
        set(.fat, "fat_100g")
        set(.fiber, "fiber_100g")
        set(.sugar, "sugars_100g")
        set(.satFat, "saturated-fat_100g")
        set(.monoFat, "monounsaturated-fat_100g")
        set(.polyFat, "polyunsaturated-fat_100g")
        set(.transFat, "trans-fat_100g")
        // Sodium: OFF in grams → our mg. Fall back to salt (salt = sodium × 2.5).
        if let sodium = n["sodium_100g"] { v[Nutrient.sodium.rawValue] = sodium * 1000 }
        else if let salt = n["salt_100g"] { v[Nutrient.sodium.rawValue] = salt / 2.5 * 1000 }
        // Cholesterol + minerals + vitamin C: OFF in grams → our mg. Best-effort.
        set(.cholesterol, "cholesterol_100g", scale: 1000)
        set(.calcium, "calcium_100g", scale: 1000)
        set(.iron, "iron_100g", scale: 1000)
        set(.magnesium, "magnesium_100g", scale: 1000)
        set(.phosphorus, "phosphorus_100g", scale: 1000)
        set(.potassium, "potassium_100g", scale: 1000)
        set(.zinc, "zinc_100g", scale: 1000)
        set(.vitaminC, "vitamin-c_100g", scale: 1000)
        return NutrientVector(v)
    }
}

// MARK: - OFF JSON shapes (private)

private struct OFFProductResponse: Decodable {
    let status: Int
    let code: String?       // top-level canonical barcode (product object often omits it)
    let product: OFFProduct?
}

private struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]
}

private struct OFFProduct: Decodable {
    let code: String?
    let name: String?
    let brands: String?
    let nutriments: [String: FlexibleDouble]?
    let servingQuantity: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments
        case name = "product_name"
        case servingQuantity = "serving_quantity"
    }
}

/// OFF's nutriments dict mixes numbers, numeric strings, and unit strings — and
/// `serving_quantity` is sometimes a string. Decode leniently: a non-numeric
/// value becomes nil and is dropped before mapping.
private struct FlexibleDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}
