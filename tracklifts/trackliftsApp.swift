//
//  trackliftsApp.swift
//  tracklifts
//
//  Created by Serene Aryal on 5/31/26.
//

import SwiftUI
import SwiftData

@main
struct trackliftsApp: App {
    /// One shared container for every SwiftData model in the app.
    let container: ModelContainer = {
        let schema = Schema([
            Exercise.self,
            Split.self,
            SplitDay.self,
            SplitItem.self,
            WorkoutSession.self,
            LoggedExercise.self,
            LoggedSet.self,
            BodyWeightEntry.self,
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        AppFonts.register()
        Appearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Palette.ember)
        }
        .modelContainer(container)
    }
}
