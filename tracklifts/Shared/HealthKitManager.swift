//
//  HealthKitManager.swift
//  tracklifts
//
//  Phase 2 Apple Health bridge. READS body mass + active energy; WRITES the
//  day's dietary energy + macros. The read set {bodyMass, activeEnergy} and the
//  write set {dietary*} are DISJOINT, which structurally prevents a write→read
//  feedback loop — we never read a type we write. Day totals are written keyed
//  per (day, nutrient) via HKMetadataKeySync*, so re-syncing a day REPLACES its
//  samples instead of duplicating them (idempotent across edits/deletes).
//

import Foundation
import Combine
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    /// Drives the Settings card. Set true after a successful authorization
    /// request or, on launch, if the user has connected before.
    @Published private(set) var isAuthorized = false

    static let connectedKey = "healthKitConnected"
    var isConnected: Bool { UserDefaults.standard.bool(forKey: Self.connectedKey) }

    /// HealthKit is unavailable on this hardware, or we're in a hermetic
    /// (UI-test / preview) launch — never prompt or touch Health there.
    var isAvailable: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable() && !CloudSync.isHermetic
        #else
        false
        #endif
    }

    #if canImport(HealthKit)
    private let store = HKHealthStore()

    /// (our Nutrient, HK dietary type, HK unit) for the day-summary writes.
    private static let writeMap: [(Nutrient, HKQuantityTypeIdentifier, HKUnit)] = [
        (.energy, .dietaryEnergyConsumed, .kilocalorie()),
        (.protein, .dietaryProtein, .gram()),
        (.carbs, .dietaryCarbohydrates, .gram()),
        (.fat, .dietaryFatTotal, .gram()),
        (.fiber, .dietaryFiber, .gram()),
        (.sodium, .dietarySodium, .gramUnit(with: .milli)),
        (.satFat, .dietaryFatSaturated, .gram()),
    ]

    private var writeTypes: Set<HKSampleType> {
        Set(Self.writeMap.compactMap { HKQuantityType.quantityType(forIdentifier: $0.1) })
    }
    private var readTypes: Set<HKObjectType> {
        Set([HKQuantityTypeIdentifier.bodyMass, .activeEnergyBurned]
            .compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }
    #endif

    // MARK: - Authorization

    func requestAuthorization() async {
        #if canImport(HealthKit)
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            UserDefaults.standard.set(true, forKey: Self.connectedKey)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
        #endif
    }

    // MARK: - Launch sync

    /// Called once from RootView. If Health was connected before, adopt the
    /// flag, pull the latest weigh-in, and (re)write today's diary totals.
    func syncOnLaunch(context: ModelContext) {
        #if canImport(HealthKit)
        guard isAvailable, isConnected else { return }
        isAuthorized = true
        importLatestBodyMass(context: context)
        syncDay(.now, context: context)
        #endif
    }

    // MARK: - Read body mass

    /// Pull the most recent body-mass sample from Health into a `BodyWeightEntry`
    /// (the existing weight funnel), converted to the user's unit, de-duped by day.
    func importLatestBodyMass(context: ModelContext) {
        #if canImport(HealthKit)
        guard isAvailable, isConnected,
              let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        // Async descriptor (iOS 17) keeps everything MainActor-isolated, so the
        // non-Sendable ModelContext is never captured in a @Sendable HK closure.
        Task { @MainActor in
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1)
            guard let sample = try? await descriptor.result(for: store).first else { return }
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            let day = Calendar.current.startOfDay(for: sample.endDate)
            Self.ingestBodyMass(kg: kg, day: day, context: context)
        }
        #endif
    }

    private static func ingestBodyMass(kg: Double, day: Date, context: ModelContext) {
        let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit") ?? "kg") ?? .kg
        let value = unit == .lb ? kg / 0.453592 : kg
        guard value > 0 else { return }
        let existing = (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []
        if existing.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: day) && abs($0.weight - value) < 0.05
        }) { return }
        context.insert(BodyWeightEntry(date: day, weight: value))
        try? context.save()
        BodyMetrics.current = value
    }

    // MARK: - Write dietary day totals

    /// Recompute a day's diary totals and (re)write them to Health. Same-day
    /// re-syncs replace prior samples via the sync identifier/version, so edits
    /// and deletes update Health without duplicating.
    func syncDay(_ day: Date, context: ModelContext) {
        #if canImport(HealthKit)
        guard isAvailable, isConnected else { return }
        // Defer off the caller's run-loop turn so adding/editing/deleting a food
        // dismisses the sheet instantly; the fetch + day re-total + Health writes
        // run after. Idempotent (sync identifier/version), so order doesn't matter.
        Task { @MainActor in
            let start = Calendar.current.startOfDay(for: day)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            let entries = (try? context.fetch(
                FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.date == start }))) ?? []
            let total = DiaryMath.total(entries)
            let dayKey = Self.dayKey(start)
            let version = Int(Date().timeIntervalSince1970 * 1000)

            var toSave: [HKQuantitySample] = []
            for (nutrient, typeID, unit) in Self.writeMap {
                guard let type = HKQuantityType.quantityType(forIdentifier: typeID) else { continue }
                let id = "tl-\(dayKey)-\(nutrient.rawValue)"
                let value = total[nutrient]
                if value > 0 {
                    let sample = HKQuantitySample(
                        type: type,
                        quantity: HKQuantity(unit: unit, doubleValue: value),
                        start: start, end: end,
                        metadata: [HKMetadataKeySyncIdentifier: id, HKMetadataKeySyncVersion: version])
                    toSave.append(sample)
                } else {
                    // The day's total for this nutrient is now zero — remove any prior sample.
                    let pred = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                           allowedValues: [id])
                    _ = try? await store.deleteObjects(of: type, predicate: pred)
                }
            }
            if !toSave.isEmpty { try? await store.save(toSave) }
        }
        #endif
    }

    #if canImport(HealthKit)
    private static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    #endif
}
