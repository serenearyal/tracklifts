//
//  CatalogPerformanceTests.swift
//  trackliftsTests
//
//  XCTest PERFORMANCE benchmarks for the two food-catalog hot paths. All numbers
//  are machine-relative — use them as before/after deltas and as regression
//  baselines (Xcode stores a per-device baseline per `measure*` method), never as
//  absolute targets.
//
//  What each test measures:
//
//  • testCatalogSeedThroughput — the CPU/throughput cost of the first-launch seed
//    (PERF-1): building ~5,000 `FoodItem`s + their `FoodPortion`s and committing
//    them in batched saves at roughly production scale (prod ships ~7,756 USDA
//    foods → ~20k inserts). Each iteration WRITES, so it builds a FRESH in-memory
//    container and only measures the insert loop (manual start/stop).
//    IMPORTANT: this is the throughput number only. PERF-1's actual user-facing
//    win — keeping the main thread responsive so first launch doesn't freeze — is
//    achieved by the async/`Task.yield()` cooperative seed in `FoodSeedManager`
//    and is an Instruments "Hangs"/main-thread observation, NOT something this
//    synchronous throughput measure can capture.
//
//  • testFoodSearchRun — the per-keystroke search path (`FoodSearch.run`): a
//    SQLite predicate fetch (capped at `limit`) plus the in-memory relevance rank,
//    over the ~5,000-food seeded catalog.
//
//  • testConfidentMatchRanking — the photo-capture AI-match ranking path
//    (PERF-11): `CaptureMatcher.confidentMatch` fetches up to 200 candidates and
//    runs the per-candidate tokenize + name-coverage + density gate over them.
//
//  Search/match tests seed ONCE into a persistent in-memory context in `setUp`,
//  then run read-only `measure {}` blocks.
//
//  The seed is driven through `FoodSeedManager.benchmarkSeed(_:into:)` — a
//  synchronous twin of the app's async seed loop, exposed specifically so this
//  throughput benchmark can run it inside `measure` (the production first-launch
//  seed is async/cooperative and can't be driven synchronously inside `measure`).
//

import XCTest
import SwiftData
@testable import tracklifts

@MainActor
final class CatalogPerformanceTests: XCTestCase {

    /// Synthetic catalog size. Close to production scale (~7,756 foods) while
    /// keeping the seed-throughput iterations (which each rebuild a container and
    /// re-insert everything) tractable for repeated `measureMetrics` runs.
    private static let syntheticFoodCount = 5_000

    /// Records reused across the whole class — generated once (deterministic) so the
    /// seed-throughput iterations and the seeded search/match contexts all measure
    /// the same realistic data.
    private static let records: [CatalogRecord] = makeSyntheticRecords(count: syntheticFoodCount)

    /// Persistent in-memory context, seeded ONCE in `setUp`, for the read-only
    /// search/match benchmarks.
    private var seededContext: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        seededContext = try Self.makeInMemoryContext()
        FoodSeedManager.benchmarkSeed(Self.records, into: seededContext)
    }

    override func tearDownWithError() throws {
        seededContext = nil
        try super.tearDownWithError()
    }

    // MARK: - PERF-1: catalog seed throughput

    /// Throughput of seeding ~5,000 synthetic foods (≈ prod scale of 7,756) into a
    /// fresh in-memory store. Each iteration WRITES, so we build a brand-new
    /// container/context per iteration and only the insert loop is timed.
    ///
    /// This is the CPU/throughput figure. It does NOT capture PERF-1's real win
    /// (main-thread responsiveness / no first-launch freeze) — that comes from the
    /// async cooperative `Task.yield()` seed in `FoodSeedManager` and is an
    /// Instruments / Hangs observation, not a wall-clock throughput number.
    func testCatalogSeedThroughput() {
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            // Fresh store per iteration so rows don't accumulate across runs and so
            // every iteration starts from an empty catalog like a real first launch.
            let context: ModelContext
            do {
                context = try Self.makeInMemoryContext()
            } catch {
                XCTFail("Failed to build in-memory container: \(error)")
                return
            }

            startMeasuring()
            FoodSeedManager.benchmarkSeed(Self.records, into: context)
            stopMeasuring()
        }

        // Same workload, with a CLI-visible per-iteration average. Each iteration
        // builds its OWN fresh container inside the closure so rows don't carry
        // over and every run seeds an empty catalog (the container build itself is
        // cheap relative to the ~5,000-food insert loop being timed).
        benchMillis("Catalog.seed5000", iterations: 3) {
            guard let context = try? Self.makeInMemoryContext() else {
                XCTFail("Failed to build in-memory container")
                return
            }
            FoodSeedManager.benchmarkSeed(Self.records, into: context)
        }
    }

    // MARK: - Search hot path

    /// Per-keystroke catalog search over the ~5,000-food seeded store: a SQLite
    /// predicate fetch (capped) plus the in-memory relevance rank. Two common
    /// terms so the predicate selectivity isn't a single-query artifact.
    func testFoodSearchRun() {
        measure {
            _ = FoodSearch.run("chicken", in: seededContext)
            _ = FoodSearch.run("rice", in: seededContext)
        }

        // Same workload, with a CLI-visible per-iteration average.
        benchMillis("Catalog.searchRun") {
            _ = FoodSearch.run("chicken", in: seededContext)
            _ = FoodSearch.run("rice", in: seededContext)
        }
    }

    // MARK: - PERF-11: AI-match ranking hot path

    /// The photo-capture confident-match path: fetch up to 200 candidates and run
    /// the per-candidate tokenize + name-coverage + density gate. Uses a
    /// representative parsed item + per-100 g estimate over the seeded catalog.
    func testConfidentMatchRanking() {
        let item = ParsedItem(name: "grilled chicken breast", quantity: 1, unit: "",
                              gramsHint: 140)
        // ~165 kcal/100 g, the density a photo model would estimate for chicken
        // breast — close enough to pass the density gate against the synthetic
        // "chicken" rows, exercising the full coverage + density comparison.
        let estimate = NutrientVector(energy: 165, protein: 31, carbs: 0, fat: 4)

        measure {
            _ = CaptureMatcher.confidentMatch(for: item, estimate: estimate, in: seededContext)
        }

        // Same workload, with a CLI-visible per-iteration average.
        benchMillis("Catalog.confidentMatch") {
            _ = CaptureMatcher.confidentMatch(for: item, estimate: estimate, in: seededContext)
        }
    }

    // MARK: - In-memory container (mirrors CaptureMatcherTests' schema)

    private static func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
            WaterEntry.self, SavedMeal.self, SavedMealItem.self,
            Recipe.self, RecipeIngredient.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    // MARK: - Synthetic catalog

    /// Builds `count` deterministic `CatalogRecord`s with varied multi-word names
    /// (so search has realistic substring/prefix work), a real per-100 g
    /// `NutrientVector`, and 2–3 portions each. Names are seeded from common food
    /// bases so terms like "chicken"/"rice" actually hit a meaningful slice.
    private static func makeSyntheticRecords(count: Int) -> [CatalogRecord] {
        // Bases chosen so the benchmark search terms ("chicken", "rice") match a
        // realistic fraction, and qualifiers make names long & USDA-like.
        let bases = [
            "Chicken breast", "Chicken thigh", "Rice white", "Rice brown",
            "Beef ground", "Salmon fillet", "Broccoli", "Banana",
            "Egg whole", "Bread whole wheat", "Cheese cheddar", "Yogurt plain",
            "Oats rolled", "Almonds", "Spinach", "Potato",
            "Apple", "Pasta", "Lentils", "Tofu",
        ]
        let qualifiers = [
            "raw", "cooked", "roasted", "grilled", "boiled", "steamed",
            "baked", "fried", "canned", "frozen",
        ]

        var records: [CatalogRecord] = []
        records.reserveCapacity(count)
        for i in 0..<count {
            let base = bases[i % bases.count]
            let qualifier = qualifiers[(i / bases.count) % qualifiers.count]
            // Suffix index keeps names unique past the base×qualifier grid so the
            // predicate can't collapse them all to a few distinct strings.
            let name = "\(base), \(qualifier), variant \(i % 97)"

            // A real, varied per-100 g vector (deterministic but not constant).
            let kcal = Double(80 + (i % 320))            // 80…399 kcal/100 g
            let protein = Double(2 + (i % 28))
            let carbs = Double(i % 60)
            let fat = Double(i % 22)
            let nutrients = NutrientVector(energy: kcal, protein: protein, carbs: carbs,
                                           fat: fat, fiber: Double(i % 8),
                                           sugar: Double(i % 15), satFat: Double(i % 6),
                                           sodium: Double(i % 400))

            // 2–3 portions; the seed helper guarantees a 100 g portion anyway.
            var portions = [
                CatalogPortion(label: "1 serving (\(85 + i % 80) g)", grams: Double(85 + i % 80)),
                CatalogPortion(label: "1 cup (\(120 + i % 130) g)", grams: Double(120 + i % 130)),
            ]
            if i % 2 == 0 {
                portions.append(CatalogPortion(label: "1 piece (\(40 + i % 60) g)", grams: Double(40 + i % 60)))
            }

            records.append(CatalogRecord(name: name, brand: "", fdcId: 900_000 + i,
                                         nutrients: nutrients.values, portions: portions))
        }
        return records
    }

}
