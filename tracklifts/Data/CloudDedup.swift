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
    /// Seed-food count after the last food dedup pass. When the count is
    /// unchanged, no new duplicate can exist, so the ~7.7k-row fetch+group is
    /// skipped and the pass becomes a single cheap COUNT.
    private static var lastFoodSeedCount = -1
    /// Trailing-debounced pass so a CloudKit import storm (e.g. the first catalog
    /// sync) collapses to ONE dedup pass after it settles, not one per event.
    private static var debouncedPass: Task<Void, Never>?

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
            MainActor.assumeIsolated { scheduleDebouncedPass() }
        }
        runIfDue(context, force: true)
    }

    /// Coalesce an import storm: each import (re)arms a single pass a few seconds
    /// after the last one, instead of a full scan per event.
    private static func scheduleDebouncedPass() {
        debouncedPass?.cancel()
        debouncedPass = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let context = syncedContext else { return }
            runIfDue(context, force: true)
        }
    }

    /// Debounced entry point (also called on scenePhase == .active). `force`
    /// still honors a short floor so an import storm can't thrash.
    static func runIfDue(_ context: ModelContext, force: Bool = false) {
        guard CloudSync.isEnabled else { return }
        let interval: TimeInterval = force ? 5 : 30
        guard Date().timeIntervalSince(lastRun) > interval else { return }
        lastRun = Date()
        dedupeExercises(context)
        purgeLegacyCurated(context)
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
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.sourceRaw == seedRaw })
        // Cheap COUNT first. On a single device the seed set is duplicate-free and
        // never changes, so this skips materializing + grouping ~7.7k rows on
        // every app-foreground / import. Duplicates only appear when another
        // store merges in — which shows up as a changed count.
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count != lastFoodSeedCount else { return }
        let seeds = (try? context.fetch(descriptor)) ?? []
        // Catalog foods key on the stable USDA id (robust to name/punctuation
        // drift across catalog regenerations); customs/legacy (fdcId 0) by name.
        var deleted = 0
        for copies in Dictionary(grouping: seeds, by: {
            $0.fdcId != 0 ? "fdc:\($0.fdcId)" : "\($0.name)|\($0.brand)"
        }).values where copies.count > 1 {
            let sorted = copies.sorted { $0.createdAt < $1.createdAt }
            let canonical = sorted[0]
            for dupe in sorted.dropFirst() {
                canonical.isFavorite = canonical.isFavorite || dupe.isFavorite
                for entry in dupe.diaryEntries ?? [] { entry.food = canonical }
                context.delete(dupe) // the dupe's identical portions cascade away
                deleted += 1
            }
        }
        lastFoodSeedCount = count - deleted // survivors; a later import changes it
    }

    /// Removes the Phase-1 curated catalog — macros-only seed foods with no USDA
    /// id (fdcId 0) — that linger in older private DBs and sync back beside the
    /// USDA catalog as friendly-named, micronutrient-empty duplicates. The app is
    /// single-source (USDA) now. Safe: diary entries snapshot their own nutrients
    /// and FoodItem.diaryEntries nullifies on delete, so logged history survives;
    /// user customs are `.custom` (never matched here) and USDA foods carry a
    /// non-zero fdcId, so neither is touched. Idempotent, and re-running on each
    /// CloudKit import clears synced copies as they arrive (deletes propagate up).
    static func purgeLegacyCurated(_ context: ModelContext) {
        let seedRaw = FoodSource.seed.rawValue // captured for #Predicate
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.sourceRaw == seedRaw && $0.fdcId == 0 })
        // Once the ghosts are gone this is a cheap COUNT(0) — don't materialize.
        guard ((try? context.fetchCount(descriptor)) ?? 0) > 0 else { return }
        let ghosts = (try? context.fetch(descriptor)) ?? []
        for ghost in ghosts { context.delete(ghost) }
    }
}
