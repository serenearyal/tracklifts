//
//  MuscleGroup.swift
//  tracklifts
//

import SwiftUI

/// The muscle groups exercises are organized under.
/// Stored on `Exercise` as a raw string for robust SwiftData querying.
enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case legs
    case core

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .legs: "Legs"
        case .core: "Core"
        }
    }

    /// SF Symbol used as the group's glyph throughout the app.
    var symbol: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .shoulders: "figure.arms.open"
        case .biceps: "dumbbell.fill"
        case .triceps: "figure.boxing"
        case .forearms: "hand.raised.fill"
        case .legs: "figure.walk"
        case .core: "figure.core.training"
        }
    }

    /// Tuned to glow on the dark FORGE canvas.
    var color: Color {
        switch self {
        case .chest: Color(hex: 0xFF6B6B)      // coral red
        case .back: Color(hex: 0x4DA8FF)       // electric blue
        case .shoulders: Color(hex: 0xFFC247)  // amber
        case .biceps: Color(hex: 0x9B7BFF)     // violet
        case .triceps: Color(hex: 0x39E0C8)    // teal
        case .forearms: Color(hex: 0xFF8C42)   // orange
        case .legs: Color(hex: 0x68D45B)       // green
        case .core: Color(hex: 0xFF7BC2)       // pink
        }
    }
}

// MARK: - MuscleTag (built-in or custom)

/// A muscle group reference that resolves display attributes for **either** a
/// built-in `MuscleGroup` or a user-defined custom group. `Exercise.muscleGroupRaw`
/// already stores a free-form string, so custom groups need no schema change —
/// `MuscleTag` is the lens the UI uses to render and group by any stored value.
struct MuscleTag: Identifiable, Hashable {
    /// The exact string stored on `Exercise.muscleGroupRaw`.
    let raw: String

    init(raw: String) { self.raw = raw }
    init(_ group: MuscleGroup) { self.raw = group.rawValue }

    var id: String { raw }

    /// The built-in case this resolves to, if any (matched case-insensitively).
    var builtIn: MuscleGroup? { MuscleGroup(rawValue: raw.lowercased()) }
    var isCustom: Bool { builtIn == nil }

    /// Built-ins use their canonical name; custom groups display the user's text verbatim.
    var displayName: String { builtIn?.displayName ?? raw }

    var symbol: String { builtIn?.symbol ?? "figure.strengthtraining.functional" }

    var color: Color {
        if let builtIn { return builtIn.color }
        let palette = MuscleTag.customPalette
        return palette[MuscleTag.stableIndex(for: raw, modulo: palette.count)]
    }

    /// Custom-group colors. Distinct from the built-in hues so a custom group never
    /// masquerades as a built-in one.
    private static let customPalette: [Color] = [
        Color(hex: 0x5AC8FA), // sky
        Color(hex: 0xC792EA), // lavender
        Color(hex: 0x8BD450), // lime
        Color(hex: 0xF7768E), // rose
        Color(hex: 0xE0AF68), // sand
        Color(hex: 0x7AA2F7), // periwinkle
    ]

    /// Deterministic FNV-1a hash → palette index. Unlike `String.hashValue` (seeded
    /// per process) this is stable across launches, so a custom group keeps its color.
    private static func stableIndex(for string: String, modulo count: Int) -> Int {
        var hash: UInt64 = 14695981039346656037
        for byte in string.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash % UInt64(count))
    }

    /// Canonical raw for a user-typed group name: collapses to a built-in's `rawValue`
    /// when it matches one (by raw value or display name, case-insensitively) so typing
    /// "chest" / "Forearms" reuses the built-in instead of fragmenting; otherwise returns
    /// the trimmed input as the custom group's stored value. Returns nil for blank input.
    static func canonicalRaw(forInput input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let builtIn = MuscleGroup(rawValue: trimmed.lowercased()) { return builtIn.rawValue }
        if let builtIn = MuscleGroup.allCases.first(where: {
            $0.displayName.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) { return builtIn.rawValue }
        return trimmed
    }
}

extension Collection where Element == Exercise {
    /// The distinct muscle groups actually present in this collection — built-ins in
    /// canonical order first, then custom groups A–Z. Drives data-driven sections and
    /// filter chips so custom groups appear automatically.
    var muscleTagsPresent: [MuscleTag] {
        let raws = Set(map(\.muscleGroupRaw))
        let builtIns = MuscleGroup.allCases
            .filter { raws.contains($0.rawValue) }
            .map { MuscleTag($0) }
        let customs = raws
            .map { MuscleTag(raw: $0) }
            .filter(\.isCustom)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return builtIns + customs
    }
}
