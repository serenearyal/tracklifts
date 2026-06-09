//
//  ContentView.swift
//  tracklifts
//
//  Created by Serene Aryal on 5/31/26.
//
//  RootView hosts the app's four tabs and seeds the exercise library on first run.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Profile.didOnboardKey) private var didOnboard = false

    var body: some View {
        TabView {
            WorkoutHistoryView()
                .tabItem { Label("Log", systemImage: "square.and.pencil") }
            FoodDiaryView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.3d.up.fill") }
            ProgressOverviewView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .task {
            // UI-test hook: start from a clean store for deterministic runs.
            if ProcessInfo.processInfo.arguments.contains("--reset-store") {
                SeedManager.resetAll(context)
            }
            SeedManager.seedIfNeeded(context)
            SeedManager.seedBodyWeightIfNeeded(context)
            FoodSeedManager.seedIfNeeded(context)
            if ProcessInfo.processInfo.arguments.contains("--seed-sample") {
                SampleData.seedIfNeeded(context)
            }
            // UI-test hook: force a clean first-run of onboarding (for screenshots).
            if ProcessInfo.processInfo.arguments.contains("--show-onboarding") {
                Profile.reset()
                BodyMetrics.current = 0
                didOnboard = false
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !didOnboard }, set: { didOnboard = !$0 })) {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self,
            FoodItem.self, FoodPortion.self, DiaryEntry.self,
        ], inMemory: true)
}
