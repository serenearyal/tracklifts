//
//  SettingsView.swift
//  tracklifts
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    @AppStorage(BodyMetrics.key) private var bodyWeight: Double = 0
    @FocusState private var bodyWeightFocused: Bool

    var body: some View {
        NavigationStack {
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

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Body Weight", systemImage: "figure")
                        HStack(spacing: 10) {
                            TextField("0", value: $bodyWeight, format: .number)
                                .keyboardType(.decimalPad)
                                .focused($bodyWeightFocused)
                                .multilineTextAlignment(.center)
                                .font(.sans(20, .bold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 96)
                                .padding(.vertical, 10)
                                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 12))
                            Text(unit.label.uppercased())
                                .font(.sans(13, .bold)).tracking(1)
                                .foregroundStyle(Palette.inkSecondary)
                            Spacer()
                            if bodyWeightFocused {
                                Button("Done") { bodyWeightFocused = false }
                                    .font(.sans(15, .semibold))
                                    .foregroundStyle(Palette.ember)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                        }
                        .animation(.snappy, value: bodyWeightFocused)
                        Text("Used to score bodyweight lifts (pull-ups, dips…) as your body weight plus any added weight. Leave at 0 to track those by reps instead.")
                            .font(.sans(12))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .cardStyle(padding: 18)

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "About", systemImage: "info.circle.fill")
                        row("Version", "1.0")
                    }
                    .cardStyle(padding: 18)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
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
}
