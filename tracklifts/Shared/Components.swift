//
//  Components.swift
//  tracklifts
//
//  Reusable UI built in the FORGE language: glass cards, ember accents,
//  condensed display numerals.
//

import SwiftUI

// MARK: - Cards & surfaces

/// Frosted glass card with a hairline edge and soft depth.
struct ForgeCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Palette.surface, in: .rect(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
    }
}

extension View {
    /// Standard glass-card chrome for ad-hoc content.
    func cardStyle(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(Palette.surface, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.30), radius: 14, x: 0, y: 8)
    }
}

/// Legacy alias kept for existing call sites.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ForgeCard { content } }
}

// MARK: - Typographic helpers

/// Small tracked label that sits above titles.
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.ember
    var body: some View {
        Text(text.uppercased())
            .font(.sans(12, .bold))
            .tracking(2.5)
            .foregroundStyle(color)
    }
}

/// Big screen header: ember eyebrow + condensed display title.
struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: eyebrow)
            Text(title.uppercased())
                .font(.display(46))
                .foregroundStyle(Palette.ink)
                .tracking(0.5)
        }
    }
}

/// In-content section label with an ember-tinted icon.
struct SectionLabel: View {
    let title: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.ember)
            Text(title.uppercased())
                .font(.sans(14, .bold))
                .tracking(1.5)
                .foregroundStyle(Palette.ink)
        }
    }
}

// MARK: - Muscle badge & chips

struct MuscleGlyph: View {
    let group: MuscleGroup
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: group.symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(group.color)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [group.color.opacity(0.28), group.color.opacity(0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: size * 0.30)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.30)
                    .strokeBorder(group.color.opacity(0.35), lineWidth: 1)
            )
    }
}

struct TagChip: View {
    let text: String
    var color: Color = Palette.ember
    var filled: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.sans(11, .bold))
            .tracking(1)
            .foregroundStyle(filled ? Color.black : color)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                if filled {
                    Capsule().fill(color)
                } else {
                    Capsule().fill(color.opacity(0.16))
                        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
                }
            }
    }
}

/// A compact, tappable pill that toggles whether an exercise is logged by body
/// weight. Green/filled when on, gray/outlined when off — a visible control,
/// never buried in a menu. Doubles as the "bodyweight" tag.
struct BodyweightToggleChip: View {
    let isOn: Bool
    var label: String = "BW"
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.system(size: 8, weight: .black))
                Text(label)
                    .font(.sans(10, .bold)).tracking(0.5)
            }
            .foregroundStyle(isOn ? Color.black : Palette.inkSecondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background {
                if isOn {
                    Capsule().fill(Palette.up)
                } else {
                    Capsule().fill(Palette.surfaceRaised)
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                }
            }
        }
        .buttonStyle(.borderless)
        .animation(.snappy, value: isOn)
        .accessibilityLabel("Bodyweight")
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// Up/down percentage chip.
struct TrendChip: View {
    let percent: Double
    var body: some View {
        let positive = percent >= 0
        let color = positive ? Palette.up : Palette.down
        return HStack(spacing: 3) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .black))
            Text(String(format: "%+.0f%%", percent))
                .font(.sans(12, .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Stats

/// Compact stat: big condensed number over a tracked label.
struct StatPill: View {
    let value: String
    let label: String
    var tint: Color = Palette.ink

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.display(30))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.sans(10, .semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Glass stat tile with icon, used in grids.
struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    var tint: Color = Palette.ember

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.display(34))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.sans(10, .semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Buttons

/// Primary ember call-to-action.
struct EmberButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .bold))
                }
                Text(title.uppercased())
                    .font(.sans(15, .bold))
                    .tracking(1)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Grad.ember, in: .rect(cornerRadius: 16))
            .shadow(color: Palette.ember.opacity(0.45), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Palette.ember)
                .frame(width: 76, height: 76)
                .background(Palette.ember.opacity(0.14), in: .circle)
                .overlay(Circle().strokeBorder(Palette.ember.opacity(0.30), lineWidth: 1))
            VStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.display(28))
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(.sans(15))
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Staggered appear

/// Fades + lifts content in, staggered by index, for page-load delight.
struct AppearLift: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                withAnimation(.smooth(duration: 0.5).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

extension View {
    func appearLift(_ index: Int) -> some View { modifier(AppearLift(index: index)) }
}
