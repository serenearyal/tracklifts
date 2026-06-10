//
//  CloudSync.swift
//  tracklifts
//
//  Central switchboard for iCloud sync: the CloudKit container id, detection
//  of "hermetic" launches that must never touch the real store or the user's
//  iCloud (UI tests, the unit-test host, previews), and the app's
//  ModelContainer factory.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "serene.tracklifts", category: "cloudsync")

enum CloudSync {
    static let containerID = "iCloud.serene.tracklifts"

    /// How the container actually came up. Surfaced in Settings so a CloudKit
    /// setup failure is visible instead of silently running local-only.
    enum Mode {
        case cloudKit
        case localFallback(String)
        case hermetic
    }

    private(set) static var mode: Mode = .hermetic

    /// Launches that must stay fully isolated: UI-test/screenshot launch args,
    /// the unit-test host app, and SwiftUI previews. These get an in-memory,
    /// non-cloud store — opening the on-disk store with sync off would still
    /// record test-run deletions in its persistent history, which the next
    /// normal launch would export to CloudKit as real deletes.
    static let isHermetic: Bool = {
        let info = ProcessInfo.processInfo
        let flags = ["--reset-store", "--seed-sample", "--show-onboarding", "--local-store"]
        return flags.contains(where: info.arguments.contains)
            || info.environment["XCTestConfigurationFilePath"] != nil
            || info.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }()

    static var isEnabled: Bool { !isHermetic }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            Split.self,
            SplitDay.self,
            SplitItem.self,
            WorkoutSession.self,
            LoggedExercise.self,
            LoggedSet.self,
            BodyWeightEntry.self,
            FoodItem.self,
            FoodPortion.self,
            DiaryEntry.self,
        ])
        if isHermetic {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                            cloudKitDatabase: .none)
            do { return try ModelContainer(for: schema, configurations: [config]) }
            catch { fatalError("Could not create hermetic ModelContainer: \(error)") }
        }
        do {
            let config = ModelConfiguration(schema: schema,
                                            cloudKitDatabase: .private(containerID))
            let container = try ModelContainer(for: schema, configurations: [config])
            mode = .cloudKit
            logger.info("CloudKit-backed container up (\(containerID, privacy: .public))")
            return container
        } catch {
            // Never brick a launch over a CloudKit validation/entitlement
            // failure — reopen the same on-disk store without sync, but
            // record the FULL underlying error (SwiftDataError's
            // localizedDescription hides the actual reason).
            let detail = describe(error)
            mode = .localFallback(detail)
            logger.error("CloudKit container failed, falling back to local: \(detail, privacy: .public)")
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do { return try ModelContainer(for: schema, configurations: [config]) }
            catch { fatalError("Could not create ModelContainer: \(error)") }
        }
    }

    /// Unwraps the underlying NSError chain — SwiftDataError prints as
    /// "error 1" while the real cause sits in userInfo / underlying errors.
    private static func describe(_ error: Error) -> String {
        var parts: [String] = [String(describing: error)]
        var ns: NSError? = error as NSError
        while let current = ns {
            if current.domain != "SwiftData.SwiftDataError" {
                parts.append("\(current.domain)(\(current.code)): \(current.localizedDescription)")
                if let reason = current.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                    parts.append(reason)
                }
            }
            ns = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " | ")
    }
}
