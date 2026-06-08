//
//  WeightUnit.swift
//  tracklifts
//

import Foundation

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg
    case lb

    var id: String { rawValue }
    var label: String { rawValue }
}

extension Double {
    /// Formats a weight value without trailing ".0" but keeping useful decimals.
    var trimmedWeight: String {
        if self == rounded() {
            return String(format: "%.0f", self)
        }
        return String(format: "%.1f", self)
    }
}
