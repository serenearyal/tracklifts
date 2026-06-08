//
//  DesignSystem.swift
//  tracklifts
//
//  "FORGE" — a dark, athletic design language. Warm-charcoal canvas, molten
//  ember accent, oversized condensed display type (the numbers are the hero).
//  This file holds the core tokens: color, gradient, and typography.
//

import SwiftUI
import CoreText

// MARK: - Color tokens

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Palette {
    /// Page background gradient stops (warm near-black → black).
    static let bgTop = Color(hex: 0x17150F)
    static let bgBottom = Color(hex: 0x0B0A09)

    /// Card / surface fills.
    static let surface = Color(hex: 0x1B1D22)
    static let surfaceRaised = Color(hex: 0x23262D)
    static let hairline = Color.white.opacity(0.08)

    /// Signature ember accent.
    static let ember = Color(hex: 0xFF7A33)
    static let emberHi = Color(hex: 0xFFB23E)
    static let emberLo = Color(hex: 0xF24E1E)

    /// Text.
    static let ink = Color(hex: 0xF5F2EA)
    static let inkSecondary = Color(hex: 0x9CA0A8)
    static let inkTertiary = Color(hex: 0x676A72)

    /// Semantics.
    static let up = Color(hex: 0x53D08A)
    static let down = Color(hex: 0xFF6361)
    static let gold = Color(hex: 0xF7C948)
}

enum Grad {
    static let ember = LinearGradient(
        colors: [Palette.emberHi, Palette.ember, Palette.emberLo],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let emberSoft = LinearGradient(
        colors: [Palette.ember.opacity(0.9), Palette.emberLo.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func glow(_ color: Color) -> RadialGradient {
        RadialGradient(colors: [color.opacity(0.45), .clear],
                       center: .center, startRadius: 2, endRadius: 160)
    }
}

// MARK: - Typography

/// Registers bundled fonts once, at launch.
enum AppFonts {
    static func register() {
        let names = [
            "BebasNeue-Regular",
            "Archivo-Regular", "Archivo-Medium", "Archivo-SemiBold", "Archivo-Bold",
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Bebas Neue — tall condensed caps for headlines and hero numbers.
    static func display(_ size: CGFloat, relativeTo style: TextStyle = .largeTitle) -> Font {
        .custom("BebasNeue-Regular", size: size, relativeTo: style)
    }

    /// Archivo body family by weight.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Archivo-Bold"
        case .semibold: name = "Archivo-SemiBold"
        case .medium: name = "Archivo-Medium"
        default: name = "Archivo-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}
