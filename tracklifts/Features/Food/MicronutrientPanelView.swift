//
//  MicronutrientPanelView.swift
//  tracklifts
//
//  Phase 2: the day's full nutrient breakdown vs. personalized targets, grouped
//  into vitamins / minerals / fats (+ fiber). "Stay-under" nutrients (sodium,
//  saturated fat…) read as a share of their limit and flip to a caution color
//  once exceeded. Reads the same per-nutrient targets the editor + onboarding set.
//

import SwiftUI
import SwiftData

struct MicronutrientPanelView: View {
    let day: Date

    @Query(sort: \DiaryEntry.createdAt) private var allEntries: [DiaryEntry]
    private let sex = Profile.sex
    private let age = Profile.age

    private var total: NutrientVector {
        DiaryMath.total(allEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) })
    }

    private var completenessHeader: some View {
        let score = Completeness.score(total: total, sex: sex, age: age)
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Completeness")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(score.rounded()))").font(.display(48)).foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text("/ 100").font(.sans(14, .semibold)).foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer()
                Image(systemName: scoreSymbol(score)).font(.system(size: 30, weight: .bold))
                    .foregroundStyle(scoreColor(score))
            }
            MacroProgressBar(value: score, goal: 100, color: scoreColor(score))
            Text("How much of your vitamin & mineral targets today's food covers.")
                .font(.sans(11)).foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle(padding: 18)
    }

    private var trendsLink: some View {
        NavigationLink {
            NutrientTrendView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.ember)
                Text("Nutrient trends over time").font(.sans(15, .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkTertiary)
            }
            .cardStyle(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func scoreColor(_ s: Double) -> Color {
        s >= 80 ? Palette.up : (s >= 50 ? Palette.gold : Palette.down)
    }
    private func scoreSymbol(_ s: Double) -> String {
        s >= 80 ? "checkmark.seal.fill" : (s >= 50 ? "chart.pie.fill" : "exclamationmark.triangle.fill")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                completenessHeader
                ForEach(NutrientGroup.allCases) { group in
                    let nutrients = group.targetable
                    if !nutrients.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: group.label, systemImage: group.symbol)
                            VStack(spacing: 14) {
                                ForEach(nutrients) { n in
                                    MicroPanelRow(nutrient: n, amount: total[n], sex: sex, age: age)
                                }
                            }
                            .cardStyle(padding: 16)
                        }
                    }
                }
                trendsLink
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("Micronutrients")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar) // diary hides its bar; show ours on push
    }
}

/// One nutrient row: amount vs. target with a progress bar. The target is read
/// reactively via `@AppStorage`, defaulting to the DRI so it works before the
/// user has ever opened the targets editor.
private struct MicroPanelRow: View {
    let nutrient: Nutrient
    let amount: Double
    @AppStorage private var target: Double

    init(nutrient: Nutrient, amount: Double, sex: Sex, age: Int) {
        self.nutrient = nutrient
        self.amount = amount
        _target = AppStorage(wrappedValue: nutrient.target(sex: sex, age: age) ?? 0,
                             NutritionGoals.key(for: nutrient))
    }

    private var stayUnder: Bool { nutrient.limitKind == .stayUnder }
    private var pct: Double { target > 0 ? amount / target : 0 }
    private var barColor: Color {
        stayUnder ? (pct > 1 ? Palette.down : Palette.up)
                  : (pct >= 1 ? Palette.up : Palette.ember)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(nutrient.label).font(.sans(14, .medium)).foregroundStyle(Palette.ink)
                if stayUnder {
                    Text("LIMIT").font(.sans(8, .bold)).tracking(0.8)
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Palette.surfaceRaised, in: .capsule)
                }
                Spacer()
                Text("\(fmt(amount)) / \(fmt(target)) \(nutrient.unit)")
                    .font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                Text("\(Int((pct * 100).rounded()))%")
                    .font(.sans(12, .bold)).foregroundStyle(barColor)
                    .frame(width: 44, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            MacroProgressBar(value: amount, goal: max(target, 0.0001), color: barColor)
        }
    }

    private func fmt(_ v: Double) -> String {
        if v >= 10 { return String(Int(v.rounded())) }
        if v >= 1 { return String(format: "%.1f", v) }
        if v > 0 { return String(format: "%.2f", v) }
        return "0"
    }
}
