//
//  CloudDedup.swift
//  tracklifts
//
//  Collapses duplicate *seed-origin* records created when two stores that each
//  ran first-launch seeding merge through CloudKit (every fresh install seeds
//  69 exercises + 258 foods before the first import lands). Idempotent, and
//  the canonical pick is deterministic (oldest createdAt — synced state), so
//  concurrent passes on two devices converge on the same survivor.
//

import Foundation
import CoreData // NSPersistentCloudKitContainer event notifications
import SwiftData

@MainActor
enum CloudDedup {
    private static var lastRun: Date = .distantPast
    private static var importObserver: NSObjectProtocol?
    /// Held in MainActor-isolated state (not captured by the observer closure)
    /// because ModelContext is non-Sendable. It's RootView's environment
    /// context — the container's mainContext, alive for the app's lifetime.
    private static var syncedContext: ModelContext?

    /// Call once from RootView's launch task. Runs an initial pass and re-runs
    /// whenever a CloudKit import finishes (SwiftData's underlying
    /// NSPersistentCloudKitContainer posts the event — best-effort hint; the
    /// scenePhase hook is the guaranteed fallback).
    static func start(context: ModelContext) {
        guard CloudSync.isEnabled, importObserver == nil else { return }
        syncedContext = context
        importObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil else { return }
            MainActor.assumeIsolated {
                if let context = syncedContext { runIfDue(context, force: true) }
            }
        }
        runIfDue(context, force: true)
    }

    /// Debounced entry point (also called on scenePhase == .active). `force`
    /// still honors a short floor so an import storm can't thrash.
    static func runIfDue(_ context: ModelContext, force: Bool = false) {
        guard CloudSync.isEnabled else { return }
        let interval: TimeInterval = force ? 5 : 30
        guard Date().timeIntervalSince(lastRun) > interval else { return }
        lastRun = Date()
        dedupeExercises(context)
        dedupeFoods(context)
        try? context.save()
    }

    /// Internal (not private) so the logic tests can drive a pass directly.
    static func dedupeExercises(_ context: ModelContext) {
        let seeds = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom == false }))) ?? []
        for copies in Dictionary(grouping: seeds, by: \.name).values where copies.count > 1 {
            let sorted = copies.sorted { $0.createdAt < $1.createdAt }
            let canonical = sorted[0]
            let libraryDefault = ExerciseLibrary.isBodyweight(canonical.name)
            for dupe in sorted.dropFirst() {
                canonical.isFavorite = canonical.isFavorite || dupe.isFavorite
                // A copy that differs from the library default carries explicit
                // user intent; a plain OR would resurrect an unmarked flag.
                if dupe.isBodyweight != libraryDefault { canonical.isBodyweight = dupe.isBodyweight }
                if canonical.notes.isEmpty { canonical.notes = dupe.notes }
                // Re-point referrers from the to-one side only, snapshotting the
                // inverse arrays first — assignment mutates them mid-iteration,
                // and to-many access on fresh models crashes iOS 17.0.
                for item in dupe.splitItems ?? [] { item.exercise = canonical }
                for logged in dupe.loggedExercises ?? [] { logged.exercise = canonical }
                context.delete(dupe) // refs already moved; nullify hits nothing
            }
        }
    }

    static func dedupeFoods(_ context: ModelContext) {
        let seedRaw = FoodSource.seed.rawValue // captured for #Predicate
        let seeds = (try? context.fetch(
            FetchDescriptor<FoodItem>(predicate: #Predicate { $0.sourceRaw == seedRaw }))) ?? []
        for copies in Dictionary(grouping: seeds, by: { "\($0.name)|\($0.brand)" }).values
        where copies.count > 1 {
            let sorted = copies.sorted { $0.createdAt < $1.createdAt }
            let canonical = sorted[0]
            for dupe in sorted.dropFirst() {
                canonical.isFavorite = canonical.isFavorite || dupe.isFavorite
                for entry in dupe.diaryEntries ?? [] { entry.food = canonical }
                context.delete(dupe) // the dupe's identical portions cascade away
            }
        }
    }
}
