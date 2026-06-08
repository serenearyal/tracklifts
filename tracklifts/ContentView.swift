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

    var body: some View {
        TabView {
            Tab("Log", systemImage: "square.and.pencil") {
                WorkoutHistoryView()
            }
            Tab("Exercises", systemImage: "dumbbell.fill") {
                ExerciseLibraryView()
            }
            Tab("Splits", systemImage: "rectangle.3.group") {
                SplitsListView()
            }
            Tab("Progress", systemImage: "chart.xyaxis.line") {
                ProgressOverviewView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .task {
            // UI-test hook: start from a clean store for deterministic runs.
            if ProcessInfo.processInfo.arguments.contains("--reset-store") {
                SeedManager.resetAll(context)
            }
            SeedManager.seedIfNeeded(context)
            if ProcessInfo.processInfo.arguments.contains("--seed-sample") {
                SampleData.seedIfNeeded(context)
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
        ], inMemory: true)
}
