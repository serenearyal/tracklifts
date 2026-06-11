//
//  NutritionFactsView.swift
//  tracklifts
//
//  The full nutrient breakdown for a serving — shown in the log + edit sheets so
//  a food's vitamins, minerals & fats are visible before you commit it (the macro
//  hero `MacroPreview` only shows energy + P/C/F). Values scale with the serving;
//  the %-column is share of the user's daily target (DRI / limit).
//

import SwiftUI

struct NutritionFactsView: View {
    let nutrients: NutrientVector
    private let sex = Profile.sex
    private let age = Profile.age

    /// Already shown by MacroPreview, so omitted here to avoid duplication.
    private static let heroMacros: Set<Nutrient> = [.energy, .protein, .carbs, .fat]

    private func rows(_ group: NutrientGroup) -> [Nutrient] {
        Nutrient.allCases.filter {
            $0.group == group && !Self.heroMacros.contains($0) && nutrients[$0] > 0
        }
    }

    var body: some View {
        let groups = NutrientGroup.allCases.filter { !rows($0).isEmpty }
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Nutrition Facts", systemImage: "list.bullet.clipboard")
            if groups.isEmpty {
                Text("No additional nutrient data for this food.")
                    .font(.sans(13)).foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(group.label.uppercased())
                            .font(.sans(10, .bold)).tracking(1).foregroundStyle(Palette.inkTertiary)
                        ForEach(rows(group)) { n in factRow(n) }
                    }
                }
            }
        }
        .cardStyle(padding: 16)
    }

    private func factRow(_ n: Nutrient) -> some View {
        let amount = nutrients[n]
        let target = n.target(sex: sex, age: age) ?? 0
        let pct = target > 0 ? Int((amount / target * 100).rounded()) : nil
        return HStack(spacing: 8) {
            Text(n.label).font(.sans(14)).foregroundStyle(Palette.ink)
            Spacer()
            Text("\(fmt(amount)) \(n.unit)")
                .font(.sans(14, .semibold)).foregroundStyle(Palette.ink)
            Text(pct.map { "\($0)%" } ?? "")
                .font(.sans(12, .bold)).foregroundStyle(Palette.ember)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func fmt(_ v: Double) -> String {
        if v >= 10 { return String(Int(v.rounded())) }
        if v >= 1 { return String(format: "%.1f", v) }
        if v > 0 { return String(format: "%.2f", v) }
        return "0"
    }
}
