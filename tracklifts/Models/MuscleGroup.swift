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
        case .legs: Color(hex: 0x68D45B)       // green
        case .core: Color(hex: 0xFF7BC2)       // pink
        }
    }
}
