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

/// The app's top-level destinations. Today holds the selection binding so its
/// cards can jump straight to a sibling tab.
enum AppTab: Hashable {
    case today, train, food, progress
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Profile.didOnboardKey) private var didOnboard = false
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(selectedTab: $selectedTab)
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(AppTab.today)
            TrainView()
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }
                .tag(AppTab.train)
            FoodDiaryView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
                .tag(AppTab.food)
            ProgressOverviewView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
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
