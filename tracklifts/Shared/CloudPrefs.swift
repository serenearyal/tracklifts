//
//  CloudPrefs.swift
//  tracklifts
//
//  Mirrors the onboarding/goals/unit preferences through iCloud key-value
//  storage so a reinstall (or a second device) restores them without accounts.
//  SwiftData+CloudKit carries the logs; this carries the 14 UserDefaults
//  scalars the app reads via @AppStorage.
//

import Foundation

@MainActor
final class CloudPrefs {
    static let shared = CloudPrefs()

    /// The symmetric mirror whitelist (last writer wins in steady state).
    /// `didOnboard` is NOT here — it's handled monotonically below, because
    /// "Recalculate" / "Restart Onboarding" deliberately set it false on one
    /// device and that must never re-onboard the others. Also excluded:
    /// `bodyWeight` (self-heals from synced BodyWeightEntry rows) and the
    /// device-local backfill flag.
    private static let mirrored: [String] = [
        Profile.sexKey, Profile.ageKey, Profile.heightKey, Profile.activityKey,
        Profile.goalKey, Profile.paceKey, Profile.customRateKey, Profile.targetWeightKey,
        NutritionGoals.energyKey, NutritionGoals.proteinKey,
        NutritionGoals.carbsKey, NutritionGoals.fatKey,
        "weightUnit",
    ] + NutritionGoals.targetable.map(NutritionGoals.key(for:)) // + per-nutrient targets

    private let defaults: UserDefaults
    private let store: NSUbiquitousKeyValueStore
    private var isApplyingRemote = false
    private var observers: [NSObjectProtocol] = []

    /// Injectable for tests (UserDefaults(suiteName:) + a dictionary-backed
    /// NSUbiquitousKeyValueStore subclass).
    init(defaults: UserDefaults = .standard, store: NSUbiquitousKeyValueStore = .default) {
        self.defaults = defaults
        self.store = store
    }

    /// True when some device finished onboarding under this iCloud account.
    var remoteSaysOnboarded: Bool { store.bool(forKey: Profile.didOnboardKey) }

    func start() {
        guard CloudSync.isEnabled, observers.isEmpty else { return }
        store.synchronize() // flush local + request a pull
        adoptRemoteIfFreshInstall()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.applyRemote(note) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushLocal() }
        })
        pushLocal() // upload an established user's values once
    }

    /// Fresh-install restore: only when this device hasn't onboarded but the
    /// account has. Copies every whitelisted KVS value over local defaults,
    /// then adopts onboarding completion (the monotonic true transition).
    func adoptRemoteIfFreshInstall() {
        guard !defaults.bool(forKey: Profile.didOnboardKey), remoteSaysOnboarded else { return }
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        for key in Self.mirrored {
            if let remote = store.object(forKey: key) {
                defaults.set(remote, forKey: key)
            }
        }
        defaults.set(true, forKey: Profile.didOnboardKey)
    }

    private func applyRemote(_ note: Notification) {
        guard let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              reason == NSUbiquitousKeyValueStoreServerChange
                || reason == NSUbiquitousKeyValueStoreInitialSyncChange,
              let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else { return }
        adoptRemoteIfFreshInstall() // the initial pull may land after start()
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        for key in Self.mirrored where changed.contains(key) {
            guard let remote = store.object(forKey: key),
                  !valuesEqual(remote, defaults.object(forKey: key)) else { continue }
            defaults.set(remote, forKey: key) // steady state: last writer wins
        }
    }

    func pushLocal() {
        guard !isApplyingRemote else { return }
        var dirty = false
        // didOnboard: push only the true transition, never false.
        if defaults.bool(forKey: Profile.didOnboardKey), !store.bool(forKey: Profile.didOnboardKey) {
            store.set(true, forKey: Profile.didOnboardKey)
            dirty = true
        }
        for key in Self.mirrored {
            // Only keys the user actually set — never blast missing-value
            // defaults over real cloud values on a fresh install.
            guard let local = defaults.object(forKey: key),
                  !valuesEqual(local, store.object(forKey: key)) else { continue }
            store.set(local, forKey: key)
            dirty = true
        }
        if dirty { store.synchronize() }
    }

    /// Loop guard: applying remote writes defaults → didChangeNotification →
    /// pushLocal compares, finds equality, writes nothing → cycle ends.
    /// NSObject equality works because plist scalars bridge to NSNumber /
    /// NSString, and NSNumber compares by value across Bool/Int/Double.
    private func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x as NSObject, y as NSObject): return x.isEqual(y)
        default: return false
        }
    }
}
