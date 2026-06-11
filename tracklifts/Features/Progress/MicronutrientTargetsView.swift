//
//  MicronutrientTargetsView.swift
//  tracklifts
//
//  Settings sub-screen (pushed from "Daily Targets"): per-nutrient daily targets,
//  auto-set from the user's stats via Dietary Reference Intakes and editable.
//  Each row binds straight to the same UserDefaults key the panel + completeness
//  score read — so an edit is live everywhere and mirrors through iCloud.
//

import SwiftUI

struct MicronutrientTargetsView: View {
    private let sex = Profile.sex
    private let age = Profile.age

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Auto-set from your age, sex & weight using Dietary Reference Intakes. Fine-tune any value; Recalculate in Settings resets them.")
                    .font(.sans(13)).foregroundStyle(Palette.inkSecondary)

                ForEach(NutrientGroup.allCases) { group in
                    let nutrients = group.targetable
                    if !nutrients.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(title: group.label, systemImage: group.symbol)
                            VStack(spacing: 4) {
                                ForEach(nutrients) { n in
                                    NutrientTargetRow(nutrient: n, sex: sex, age: age)
                                }
                            }
                            .cardStyle(padding: 10)
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle("Nutrient Targets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One editable target row. The `@AppStorage` key is built dynamically from the
/// nutrient, defaulting to the DRI so an un-customized nutrient shows its auto value.
private struct NutrientTargetRow: View {
    let nutrient: Nutrient
    @AppStorage private var value: Double

    init(nutrient: Nutrient, sex: Sex, age: Int) {
        self.nutrient = nutrient
        _value = AppStorage(wrappedValue: nutrient.target(sex: sex, age: age) ?? 0,
                            NutritionGoals.key(for: nutrient))
    }

    var body: some View {
        HStack {
            Text(nutrient.label).font(.sans(15)).foregroundStyle(Palette.ink)
            if nutrient.limitKind == .stayUnder {
                Text("LIMIT").font(.sans(9, .bold)).tracking(1)
                    .foregroundStyle(Palette.inkTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Palette.surfaceRaised, in: .capsule)
            }
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.sans(16, .bold)).foregroundStyle(Palette.ink)
                .frame(width: 72)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))
            Text(nutrient.unit).font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                .frame(width: 38, alignment: .leading)
        }
    }
}
