//
//  FoodSearch.swift
//  tracklifts
//
//  Shared catalog search so the diary's add-food sheet and the recipe ingredient
//  picker rank results identically. Filtering runs in SQLite (predicate + fetch
//  limit); relevance ranking (favorites first; name-prefix > word-prefix >
//  anywhere) is applied to the capped set so "kiwi" surfaces "Kiwifruit, raw"
//  above "Beverages, … Kiwi" without scanning the whole catalog on each keystroke.
//

import Foundation
import SwiftData

enum FoodSearch {
    @MainActor
    static func run(_ term: String, in context: ModelContext, limit: Int = 60) -> [FoodItem] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate {
                $0.name.localizedStandardContains(q) || $0.brand.localizedStandardContains(q)
            },
            sortBy: [SortDescriptor(\.name)]) // favorites-first applied in the in-memory rank below
        descriptor.fetchLimit = limit
        let fetched = (try? context.fetch(descriptor)) ?? []
        return fetched.sorted {
            ($0.isFavorite ? 0 : 1, matchRank($0.name, query: q), $0.name)
                < ($1.isFavorite ? 0 : 1, matchRank($1.name, query: q), $1.name)
        }
    }

    /// 0 = name starts with the query, 1 = some word starts with it, 2 = elsewhere.
    static func matchRank(_ name: String, query: String) -> Int {
        let lname = name.lowercased(), lq = query.lowercased()
        if lname.hasPrefix(lq) { return 0 }
        if lname.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(lq) }) {
            return 1
        }
        return 2
    }
}
