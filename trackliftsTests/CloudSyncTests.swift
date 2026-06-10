//
//  CloudSyncTests.swift
//  trackliftsTests
//
//  Guards the iCloud-sync support logic: the seed dedup pass (merge rules,
//  re-pointing, idempotency) and the CloudPrefs KVS mirror (fresh-install
//  adoption, monotonic didOnboard, no ping-pong).
//

import Foundation
import Testing
import SwiftData
@testable import tracklifts

// MARK: - Dedup

@MainActor
struct CloudDedupTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func mergesDuplicateSeedExercisesAndRepoints() throws {
        let context = try makeContext()

        let older = Exercise(name: "Pull-Up", muscleGroup: .back, isBodyweight: true)
        context.insert(older)
        older.createdAt = Date(timeIntervalSinceNow: -100)

        let newer = Exercise(name: "Pull-Up", muscleGroup: .back, isFavorite: true, isBodyweight: true)
        context.insert(newer)

        // Referrers point at the copy that will lose (insert first, then wire
        // the to-one side — the repo's iOS 17 rule).
        let item = SplitItem(exercise: newer, order: 0)
        context.insert(item)
        let logged = LoggedExercise(exercise: newer, order: 0)
        context.insert(logged)
        try context.save()

        CloudDedup.dedupeExercises(context)
        try context.save()

        let survivors = try context.fetch(FetchDescriptor<Exercise>())
        #expect(survivors.count == 1)
        let canonical = try #require(survivors.first)
        #expect(canonical.createdAt == older.createdAt)
        #expect(canonical.isFavorite, "favorite from the dupe must survive the merge")
        #expect(item.exercise?.persistentModelID == canonical.persistentModelID)
        #expect(logged.exercise?.persistentModelID == canonical.persistentModelID)
    }

    @Test func respectsExplicitBodyweightUnmark() throws {
        let context = try makeContext()

        // "Pull-Up" defaults to bodyweight in the library; the user unmarked it
        // on one device. The fresh seed copy must not resurrect the default.
        let unmarked = Exercise(name: "Pull-Up", muscleGroup: .back, isBodyweight: false)
        context.insert(unmarked)
        unmarked.createdAt = Date(timeIntervalSinceNow: -100)

        let freshSeed = Exercise(name: "Pull-Up", muscleGroup: .back, isBodyweight: true)
        context.insert(freshSeed)
        try context.save()

        CloudDedup.dedupeExercises(context)
        try context.save()

        let survivors = try context.fetch(FetchDescriptor<Exercise>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.isBodyweight == false,
                "explicit unmark differs from the library default and must win")
    }

    @Test func mergesDuplicateSeedFoodsRepointsDiaryAndCascadesPortions() throws {
        let context = try makeContext()

        func seedOats() -> FoodItem {
            let food = FoodItem(name: "Oats", source: .seed,
                                per100g: NutrientVector(energy: 389, protein: 17, carbs: 66, fat: 7))
            context.insert(food)
            let portion = FoodPortion(label: "100 g", grams: 100, order: 0)
            context.insert(portion)
            portion.food = food
            return food
        }

        let older = seedOats()
        older.createdAt = Date(timeIntervalSinceNow: -100)
        let newer = seedOats()
        newer.isFavorite = true

        let entry = DiaryEntry(date: .now, meal: .breakfast, food: newer, grams: 50)
        context.insert(entry)
        try context.save()
        let kcalBefore = entry.kcal

        CloudDedup.dedupeFoods(context)
        try context.save()

        let foods = try context.fetch(FetchDescriptor<FoodItem>())
        #expect(foods.count == 1)
        let canonical = try #require(foods.first)
        #expect(canonical.createdAt == older.createdAt)
        #expect(canonical.isFavorite)
        #expect(entry.food?.persistentModelID == canonical.persistentModelID)
        #expect(entry.kcal == kcalBefore, "diary snapshot must be untouched by dedup")

        let portions = try context.fetch(FetchDescriptor<FoodPortion>())
        #expect(portions.count == 1, "the dupe's portions must cascade away")
    }

    @Test func dedupIsIdempotent() throws {
        let context = try makeContext()
        for offset in 0..<3 {
            let ex = Exercise(name: "Pull-Up", muscleGroup: .back, isBodyweight: true)
            context.insert(ex)
            ex.createdAt = Date(timeIntervalSinceNow: TimeInterval(-offset))
        }
        try context.save()

        CloudDedup.dedupeExercises(context)
        try context.save()
        let afterFirst = try context.fetch(FetchDescriptor<Exercise>()).count

        CloudDedup.dedupeExercises(context)
        try context.save()
        let afterSecond = try context.fetch(FetchDescriptor<Exercise>()).count

        #expect(afterFirst == 1)
        #expect(afterSecond == 1)
    }
}

// MARK: - CloudPrefs

/// Dictionary-backed stand-in so tests never touch real iCloud KVS.
private final class FakeKVS: NSUbiquitousKeyValueStore {
    var dict: [String: Any] = [:]
    var writeCount = 0

    override func object(forKey aKey: String) -> Any? { dict[aKey] }
    override func bool(forKey aKey: String) -> Bool { dict[aKey] as? Bool ?? false }
    override func set(_ anObject: Any?, forKey aKey: String) {
        dict[aKey] = anObject
        writeCount += 1
    }
    override func set(_ value: Bool, forKey aKey: String) {
        dict[aKey] = value
        writeCount += 1
    }
    override func synchronize() -> Bool { true }
}

@MainActor
struct CloudPrefsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "CloudPrefsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func freshInstallAdoptsRemoteValues() {
        let defaults = makeDefaults()
        let kvs = FakeKVS()
        kvs.dict = [Profile.didOnboardKey: true, NutritionGoals.energyKey: 2500.0, "weightUnit": "lb"]

        let prefs = CloudPrefs(defaults: defaults, store: kvs)
        prefs.adoptRemoteIfFreshInstall()

        #expect(defaults.bool(forKey: Profile.didOnboardKey))
        #expect(defaults.double(forKey: NutritionGoals.energyKey) == 2500)
        #expect(defaults.string(forKey: "weightUnit") == "lb")
    }

    @Test func onboardedDeviceDoesNotAdoptRemoteValues() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: Profile.didOnboardKey)
        defaults.set(1800.0, forKey: NutritionGoals.energyKey)
        let kvs = FakeKVS()
        kvs.dict = [Profile.didOnboardKey: true, NutritionGoals.energyKey: 2500.0]

        let prefs = CloudPrefs(defaults: defaults, store: kvs)
        prefs.adoptRemoteIfFreshInstall()

        #expect(defaults.double(forKey: NutritionGoals.energyKey) == 1800,
                "an already-onboarded device keeps its local values")
    }

    @Test func didOnboardFalseIsNeverPushed() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: Profile.didOnboardKey) // e.g. after "Recalculate"
        let kvs = FakeKVS()
        kvs.dict = [Profile.didOnboardKey: true]

        let prefs = CloudPrefs(defaults: defaults, store: kvs)
        prefs.pushLocal()

        #expect(kvs.bool(forKey: Profile.didOnboardKey),
                "the monotonic flag must never propagate false to other devices")
    }

    @Test func didOnboardTrueIsPushed() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: Profile.didOnboardKey)
        let kvs = FakeKVS()

        let prefs = CloudPrefs(defaults: defaults, store: kvs)
        prefs.pushLocal()

        #expect(kvs.bool(forKey: Profile.didOnboardKey))
    }

    @Test func pushIsIdempotentNoPingPong() {
        let defaults = makeDefaults()
        defaults.set(2000.0, forKey: NutritionGoals.energyKey)
        let kvs = FakeKVS()

        let prefs = CloudPrefs(defaults: defaults, store: kvs)
        prefs.pushLocal()
        let writesAfterFirst = kvs.writeCount
        prefs.pushLocal()

        #expect(kvs.dict[NutritionGoals.energyKey] as? Double == 2000)
        #expect(kvs.writeCount == writesAfterFirst,
                "an unchanged value must not be re-written (loop guard)")
    }

    @Test func unsetLocalKeysAreNotPushed() {
        let defaults = makeDefaults()
        let kvs = FakeKVS()
        kvs.dict = [NutritionGoals.energyKey: 2500.0]

        let prefs = CloudPrefs(defaults: defaults, store: kvs)
        prefs.pushLocal()

        #expect(kvs.dict[NutritionGoals.energyKey] as? Double == 2500,
                "missing local values must never clobber real cloud values")
        #expect(kvs.writeCount == 0)
    }
}
