//
//  SettingsView.swift
//  tracklifts
//
//  Pushed from the Today tab's gear button (no longer a tab of its own), so
//  it must not own a NavigationStack.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    @AppStorage(BodyMetrics.key) private var bodyWeight: Double = 0
    @AppStorage(NutritionGoals.energyKey) private var goalEnergy = NutritionGoals.defaultEnergy
    @AppStorage(NutritionGoals.proteinKey) private var goalProtein = NutritionGoals.defaultProtein
    @AppStorage(NutritionGoals.carbsKey) private var goalCarbs = NutritionGoals.defaultCarbs
    @AppStorage(NutritionGoals.fatKey) private var goalFat = NutritionGoals.defaultFat
    @AppStorage(Profile.goalKey) private var goalRaw = FitnessGoal.maintain.rawValue
    @AppStorage(Profile.didOnboardKey) private var didOnboard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                brandLockup

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Units", systemImage: "scalemass.fill")
                    Picker("Weight Unit", selection: $unit) {
                        ForEach(WeightUnit.allCases) { u in
                            Text(u.label.uppercased()).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Changing units relabels values; it does not convert previously logged weights.")
                        .font(.sans(12))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .cardStyle(padding: 18)

                NavigationLink {
                    BodyWeightView()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Body Weight", systemImage: "figure")
                        HStack(alignment: .firstTextBaseline) {
                            if bodyWeight > 0 {
                                Text(bodyWeight.trimmedWeight)
                                    .font(.display(30))
                                    .foregroundStyle(Palette.ink)
                                Text(unit.label.uppercased())
                                    .font(.sans(12, .bold)).tracking(1)
                                    .foregroundStyle(Palette.inkSecondary)
                            } else {
                                Text("Not set yet")
                                    .font(.sans(16, .semibold))
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer()
                            Text("Open log")
                                .font(.sans(12, .bold)).tracking(1)
                                .foregroundStyle(Palette.ember)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.inkTertiary)
                        }
                        Text("Logged over time to chart your trend — and to score bodyweight lifts (pull-ups, dips…) as body weight plus any added load.")
                            .font(.sans(12))
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(padding: 18)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Daily Targets", systemImage: "target")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GOAL").font(.sans(10, .bold)).tracking(1.2).foregroundStyle(Palette.inkSecondary)
                            Text(FitnessGoal(rawValue: goalRaw)?.label ?? "Maintain")
                                .font(.sans(16, .bold)).foregroundStyle(Palette.ember)
                        }
                        Spacer()
                        Button { didOnboard = false } label: {
                            Text("Recalculate")
                                .font(.sans(13, .bold)).foregroundStyle(Palette.ember)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Palette.ember.opacity(0.14), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                    goalRow("Energy", value: $goalEnergy, unit: "kcal")
                    goalRow("Protein", value: $goalProtein, unit: "g")
                    goalRow("Carbs", value: $goalCarbs, unit: "g")
                    goalRow("Fat", value: $goalFat, unit: "g")
                    Text("Set from your goal during setup. Recalculate to redo it, or fine-tune any value.")
                        .font(.sans(12))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .cardStyle(padding: 18)

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "About", systemImage: "info.circle.fill")
                    row("Version", "1.0")
                }
                .cardStyle(padding: 18)

                #if DEBUG
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Developer", systemImage: "ladybug.fill")
                    Button {
                        Profile.reset()
                        didOnboard = false
                    } label: {
                        HStack {
                            Text("Restart Onboarding")
                                .font(.sans(15, .semibold)).foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.ember)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Clears your saved profile and replays the first-run onboarding. Debug builds only.")
                        .font(.sans(12)).foregroundStyle(Palette.inkSecondary)
                }
                .cardStyle(padding: 18)
                #endif
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Brand lockup: the ember mark over the condensed wordmark + tagline.
    private var brandLockup: some View {
        VStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .shadow(color: Palette.ember.opacity(0.45), radius: 16, y: 6)
            Text("TRACKLIFTS")
                .font(.display(40))
                .foregroundStyle(Palette.ink)
                .tracking(1)
            Text("Train. Track. Repeat.")
                .font(.sans(13, .semibold)).tracking(1.5)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.sans(15)).foregroundStyle(Palette.ink)
            Spacer()
            Text(value).font(.sans(15, .semibold)).foregroundStyle(Palette.inkSecondary)
        }
    }

    private func goalRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label).font(.sans(15)).foregroundStyle(Palette.ink)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.sans(16, .bold)).foregroundStyle(Palette.ink)
                .frame(width: 72)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))
            Text(unit).font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                .frame(width: 34, alignment: .leading)
        }
    }
}
