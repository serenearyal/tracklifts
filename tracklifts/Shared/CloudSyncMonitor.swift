//
//  CloudSyncMonitor.swift
//  tracklifts
//
//  Observes the CloudKit mirroring events SwiftData's underlying
//  NSPersistentCloudKitContainer posts, so the app can show *actual* sync
//  health (last export/import, last error) instead of just account status —
//  and so failures show up in the console/Console.app during device runs.
//

import Foundation
import CoreData
import Observation
import os

private let logger = Logger(subsystem: "serene.tracklifts", category: "cloudsync")

@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    private(set) var lastExport: Date?
    private(set) var lastImport: Date?
    private(set) var lastError: String?

    /// Most recent successful traffic in either direction.
    var lastActivity: Date? {
        switch (lastExport, lastImport) {
        case (nil, nil): nil
        case (let e?, nil): e
        case (nil, let i?): i
        case (let e?, let i?): max(e, i)
        }
    }

    @ObservationIgnored private var observer: NSObjectProtocol?

    func start() {
        guard CloudSync.isEnabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            MainActor.assumeIsolated { CloudSyncMonitor.shared.record(event) }
        }
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        let kind = label(for: event.type)
        if let error = event.error {
            lastError = error.localizedDescription
            logger.error("CloudKit \(kind) failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard event.succeeded else { return }
        switch event.type {
        case .export: lastExport = event.endDate
        case .import: lastImport = event.endDate
        case .setup: lastError = nil // a clean setup clears stale errors
        @unknown default: break
        }
        logger.info("CloudKit \(kind) succeeded")
    }

    private func label(for type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: "setup"
        case .export: "export"
        case .import: "import"
        @unknown default: "event"
        }
    }
}
