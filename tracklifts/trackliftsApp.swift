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
    /// One shared container for every SwiftData model in the app — CloudKit-
    /// backed for real launches, hermetic in-memory for tests and previews.
    let container: ModelContainer = CloudSync.makeContainer()

    init() {
        AppFonts.register()
        Appearance.configure()
        CloudPrefs.shared.start()
        CloudSyncMonitor.shared.start()
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
