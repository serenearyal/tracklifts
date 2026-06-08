//
//  Split.swift
//  tracklifts
//
//  A "split" is a training routine made of days (e.g. Push / Pull / Legs),
//  each day holding an ordered list of exercises.
//

import Foundation
import SwiftData

@Model
final class Split {
    var name: String = ""
    var order: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SplitDay.split)
    var days: [SplitDay] = []

    init(name: String, order: Int = 0) {
        self.name = name
        self.order = order
        self.createdAt = Date()
    }

    var orderedDays: [SplitDay] {
        days.sorted { $0.order < $1.order }
    }
}

@Model
final class SplitDay {
    var name: String = ""
    var order: Int = 0
    var split: Split?

    @Relationship(deleteRule: .cascade, inverse: \SplitItem.day)
    var items: [SplitItem] = []

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }

    var orderedItems: [SplitItem] {
        items.sorted { $0.order < $1.order }
    }

    var exercises: [Exercise] {
        orderedItems.compactMap(\.exercise)
    }
}

/// Join object linking a `SplitDay` to an `Exercise` while preserving order.
@Model
final class SplitItem {
    var order: Int = 0
    var day: SplitDay?
    var exercise: Exercise?

    init(exercise: Exercise, order: Int) {
        self.exercise = exercise
        self.order = order
    }
}
