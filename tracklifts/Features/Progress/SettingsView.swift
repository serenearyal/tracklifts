//
//  SettingsView.swift
//  tracklifts
//
//  Pushed from the Today tab's gear button (no longer a tab of its own), so
//  it must not own a NavigationStack.
//

import SwiftUI
import CloudKit

struct SettingsView: View {
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    @AppStorage(BodyMetrics.key) private var bodyWeight: Double = 0
    @AppStorage(NutritionGoals.energyKey) private var goalEnergy = NutritionGoals.defaultEnergy
    @AppStorage(NutritionGoals.proteinKey) private var goalProtein = NutritionGoals.defaultProtein
    @AppStorage(NutritionGoals.carbsKey) private var goalCarbs = NutritionGoals.defaultCarbs
    @AppStorage(NutritionGoals.fatKey) private var goalFat = NutritionGoals.defaultFat
    @AppStorage(Profile.goalKey) private var goalRaw = FitnessGoal.maintain.rawValue
    @AppStorage(Profile.didOnboardKey) private var didOnboard = false

    @State private var iCloudStatus: CKAccountStatus?
    @FocusState private var focusedGoal: GoalField?

    private enum GoalField: Hashable { case energy, protein, carbs, fat }

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: focusedGoal) { _, f in
                    proxy.scrollFieldToTop(f)
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                brandLockup

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "iCloud Sync", systemImage: "icloud.fill")
                    HStack {
                        Text(iCloudStatusLabel)
                            .font(.sans(16, .bold))
                            .foregroundStyle(iCloudStatusTint)
                        Spacer()
                        Image(systemName: iCloudStatusSymbol)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(iCloudStatusTint)
                    }
                    Text(iCloudStatusDetail)
                        .font(.sans(12))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .cardStyle(padding: 18)

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
                    goalRow("Energy", value: $goalEnergy, unit: "kcal", focus: .energy)
                    goalRow("Protein", value: $goalProtein, unit: "g", focus: .protein)
                    goalRow("Carbs", value: $goalCarbs, unit: "g", focus: .carbs)
                    goalRow("Fat", value: $goalFat, unit: "g", focus: .fat)
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
        .task { await refreshAccountStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { await refreshAccountStatus() }
        }
    }

    // MARK: - iCloud status

    /// UI tests / previews must not touch CloudKit — they render a static Off.
    private func refreshAccountStatus() async {
        guard CloudSync.isEnabled else { return }
        iCloudStatus = try? await CKContainer(identifier: CloudSync.containerID).accountStatus()
    }

    /// Healthy = the container actually came up CloudKit-backed AND the
    /// account is reachable. `CloudSync.mode` catches setup failures that
    /// account status alone would happily report as "available".
    private var iCloudHealthy: Bool {
        if case .cloudKit = CloudSync.mode, iCloudStatus == .available { return true }
        return false
    }

    private var iCloudStatusLabel: String {
        switch CloudSync.mode {
        case .hermetic: return "Off"
        case .localFallback: return "Error"
        case .cloudKit:
            switch iCloudStatus {
            case .available: return "On"
            case .noAccount: return "Off"
            case nil: return "Checking…"
            default: return "Unavailable"
            }
        }
    }

    private var iCloudStatusSymbol: String {
        if iCloudHealthy { return "checkmark.icloud.fill" }
        if case .localFallback = CloudSync.mode { return "exclamationmark.icloud.fill" }
        return "xmark.icloud"
    }

    private var iCloudStatusTint: Color {
        if iCloudHealthy { return Palette.up }
        if case .localFallback = CloudSync.mode { return Palette.down }
        return Palette.inkSecondary
    }

    private var iCloudStatusDetail: String {
        switch CloudSync.mode {
        case .hermetic:
            return "Sync is disabled for test runs."
        case .localFallback(let reason):
            return "iCloud sync couldn't start: \(reason) Your data stays on this device."
        case .cloudKit:
            switch iCloudStatus {
            case .available:
                let monitor = CloudSyncMonitor.shared
                if let error = monitor.lastError {
                    return "Last sync problem: \(error)"
                }
                if let activity = monitor.lastActivity {
                    return "Synced privately via your iCloud — last activity \(activity.formatted(.relative(presentation: .named)))."
                }
                return "Waiting for the first sync. Keep the app open for a minute; the initial upload covers your whole log."
            case .noAccount:
                return "Sign in to iCloud in the Settings app to back up your logs and sync across devices."
            default:
                return "iCloud isn't reachable right now. Logging keeps working on this device; sync resumes automatically."
            }
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

    private func goalRow(_ label: String, value: Binding<Double>, unit: String, focus: GoalField) -> some View {
        HStack {
            Text(label).font(.sans(15)).foregroundStyle(Palette.ink)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .focused($focusedGoal, equals: focus)
                .multilineTextAlignment(.trailing)
                .font(.sans(16, .bold)).foregroundStyle(Palette.ink)
                .frame(width: 72)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))
            Text(unit).font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                .frame(width: 34, alignment: .leading)
        }
        .id(focus)
    }
}
