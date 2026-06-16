//
//  DiaryPerformanceTests.swift
//  trackliftsTests
//
//  PERFORMANCE benchmark for the diary-aggregation hot path that PERF-3/6/7/8
//  optimized. The Food tab re-runs this aggregation on every render (date change,
//  swipe-delete, water tap, sheet dismiss), so its cost is felt directly.
//
//  Two `measure {}` blocks bracket the same workload:
//
//    • `testDiaryDayAggregation_Optimized` — the CURRENT FoodDiaryView body:
//        one `$0.date == startOfDay` filter over the table, ONE `DiaryMath.total`
//        decode pass, and a single `Dictionary(grouping:by: \.meal)`.
//
//    • `testDiaryDayAggregation_Naive` — a faithful reproduction of the OLD render:
//        four per-meal `Calendar.current.isDate(_:inSameDayAs:)` filters over ALL
//        entries (+ sort), a `previousDayEntries` full scan, and `DiaryMath.total`
//        recomputed once per meal section. That is ~5–6 full passes over the whole
//        diary table, each pass paying a per-entry `Calendar.isDate` calendar
//        computation AND (for the totals) a per-entry JSON decode.
//
//  Read together, the two times demonstrate the ~5–6× per-render work reduction
//  PERF-3/6/7/8 achieved on this path. Absolute `measure` numbers are
//  MACHINE-RELATIVE — they're meaningful as a before/after comparison and as a
//  regression baseline on the SAME machine (Xcode stores a per-device baseline),
//  not as a portable constant.
//

import XCTest
import SwiftData
@testable import tracklifts

// The whole app target is @MainActor-isolated, so constructing `@Model` types
// (and exercising the view's aggregation closures) must happen on the main actor.
@MainActor
final class DiaryPerformanceTests: XCTestCase {

    // MARK: Synthetic scale

    /// Distinct synthetic foods the entries cycle through — each with a real
    /// `NutrientVector` so the blob decode inside `DiaryMath.total` is exercised.
    private let foodCount = 12
    /// Days of history. Large enough that the all-time table dwarfs any one day,
    /// which is exactly the shape that punishes the naive full-table scans.
    private let dayCount = 180
    /// Entries per day. ~20 keeps a single target day realistically busy.
    private let entriesPerDay = 22
    // → ~180 × 22 ≈ 3,960 DiaryEntry total; ~22 on the target day.

    private var context: ModelContext!
    /// All entries, fetched once, mirroring `@Query`'s in-memory array.
    private var allEntries: [DiaryEntry] = []
    /// A target day that is guaranteed to have entries (start-of-day normalized).
    private var targetDay: Date!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Same in-memory container pattern as CaptureMatcherTests / SavedMealTests.
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
            WaterEntry.self, SavedMeal.self, SavedMealItem.self,
            Recipe.self, RecipeIngredient.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: [config]))

        // A handful of foods with varied, realistic per-100 g nutrient vectors.
        // Inserted (and saved) before any DiaryEntry references them — the entry
        // initializer reads `food.nutrients(forGrams:)` to snapshot its blob.
        var foods: [FoodItem] = []
        for i in 0..<foodCount {
            let f = FoodItem(
                name: "Food \(i)",
                source: .seed,
                per100g: NutrientVector(
                    energy: 80 + Double(i) * 15,
                    protein: 4 + Double(i),
                    carbs: 10 + Double(i) * 2,
                    fat: 2 + Double(i),
                    fiber: 1 + Double(i % 4),
                    sugar: Double(i % 6),
                    satFat: 0.5 + Double(i % 3),
                    sodium: 30 + Double(i) * 5
                )
            )
            ctx.insert(f)
            foods.append(f)
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let meals = Meal.allCases

        for d in 0..<dayCount {
            // d == 0 is today; spread the rest backwards day by day.
            let day = cal.date(byAdding: .day, value: -d, to: today) ?? today
            for e in 0..<entriesPerDay {
                let food = foods[(d * entriesPerDay + e) % foodCount]
                let meal = meals[e % meals.count]
                let grams = 50 + Double((d + e) % 10) * 25  // 50…275 g
                // food is already inserted+resident; the entry holds a to-one
                // reference set in its initializer — no to-many append on an
                // un-inserted model.
                let entry = DiaryEntry(date: day, meal: meal, food: food,
                                       grams: grams, portionLabel: "", order: e)
                ctx.insert(entry)
            }
        }
        try ctx.save()

        self.context = ctx
        // Pick a target day in the middle of the range that definitely has entries.
        self.targetDay = cal.date(byAdding: .day, value: -(dayCount / 2), to: today) ?? today
        // Fetch once, like @Query feeding the view its in-memory snapshot.
        self.allEntries = try ctx.fetch(FetchDescriptor<DiaryEntry>())

        // Guard the fixture so a measured run can't silently benchmark empty work.
        XCTAssertGreaterThan(allEntries.count, dayCount * entriesPerDay / 2,
                             "synthetic diary should be large")
        let startOfTarget = cal.startOfDay(for: targetDay)
        XCTAssertFalse(allEntries.filter { $0.date == startOfTarget }.isEmpty,
                       "target day must have entries")
    }

    override func tearDownWithError() throws {
        context = nil
        allEntries = []
        targetDay = nil
        try super.tearDownWithError()
    }

    // MARK: Optimized path — the current FoodDiaryView body

    /// One filter, one `DiaryMath.total` decode pass, one grouping — the shape
    /// the live view renders today. This is the "after".
    func testDiaryDayAggregation_Optimized() {
        let all = allEntries
        let startOfDay = Calendar.current.startOfDay(for: targetDay)

        measure {
            // `DiaryEntry.date` is already start-of-day, so equality matches the
            // old `isDate(_:inSameDayAs:)` while scanning the table just once.
            let dayEntries = all.filter { $0.date == startOfDay }
            // One decode pass per render, shared by the summary + micro cards.
            let total = DiaryMath.total(dayEntries)
            // Group once; each meal section reads its slice from this map.
            let byMeal = Dictionary(grouping: dayEntries, by: { $0.meal })

            // Touch the results so the optimizer can't drop the work.
            blackhole(total.energy)
            blackhole(byMeal.count)
            for meal in Meal.allCases {
                blackhole((byMeal[meal] ?? []).count)
            }
        }

        // Same workload, with a CLI-visible per-iteration average.
        benchMillis("Diary.optimized") {
            let dayEntries = all.filter { $0.date == startOfDay }
            let total = DiaryMath.total(dayEntries)
            let byMeal = Dictionary(grouping: dayEntries, by: { $0.meal })

            blackhole(total.energy)
            blackhole(byMeal.count)
            for meal in Meal.allCases {
                blackhole((byMeal[meal] ?? []).count)
            }
        }
    }

    // MARK: Naive path — a faithful reproduction of the OLD render

    /// Reproduces the pre-optimization render cost: a per-meal full-table
    /// `Calendar.isDate` filter (+ sort) for each of the four meals, a separate
    /// `previousDayEntries` full scan, and `DiaryMath.total` recomputed per meal
    /// section — i.e. ~5–6 full passes with per-entry calendar math + JSON decode.
    func testDiaryDayAggregation_Naive() {
        let all = allEntries
        let day = targetDay!

        measure {
            let cal = Calendar.current

            // (1) Day-total recomputed up front from a full-table isDate filter.
            let dayEntriesForTotal = all.filter { cal.isDate($0.date, inSameDayAs: day) }
            let dayTotal = DiaryMath.total(dayEntriesForTotal)
            blackhole(dayTotal.energy)

            // (2) Each meal section re-filters ALL entries with isDate, then by
            //     meal, then sorts — and recomputes that section's total.
            for meal in Meal.allCases {
                let items = all
                    .filter { cal.isDate($0.date, inSameDayAs: day) }
                    .filter { $0.meal == meal }
                    .sorted { $0.createdAt < $1.createdAt }
                let sectionTotal = DiaryMath.total(items)   // redundant decode pass
                blackhole(sectionTotal.energy)
                blackhole(items.count)
            }

            // (3) The "copy previous day" affordance scanned the whole table again.
            let prev = cal.date(byAdding: .day, value: -1, to: day) ?? day
            let previousDayEntries = all.filter { cal.isDate($0.date, inSameDayAs: prev) }
            blackhole(previousDayEntries.count)
        }

        // Same workload, with a CLI-visible per-iteration average.
        benchMillis("Diary.naive") {
            let cal = Calendar.current

            let dayEntriesForTotal = all.filter { cal.isDate($0.date, inSameDayAs: day) }
            let dayTotal = DiaryMath.total(dayEntriesForTotal)
            blackhole(dayTotal.energy)

            for meal in Meal.allCases {
                let items = all
                    .filter { cal.isDate($0.date, inSameDayAs: day) }
                    .filter { $0.meal == meal }
                    .sorted { $0.createdAt < $1.createdAt }
                let sectionTotal = DiaryMath.total(items)
                blackhole(sectionTotal.energy)
                blackhole(items.count)
            }

            let prev = cal.date(byAdding: .day, value: -1, to: day) ?? day
            let previousDayEntries = all.filter { cal.isDate($0.date, inSameDayAs: prev) }
            blackhole(previousDayEntries.count)
        }
    }

    // MARK: Helpers

    /// Defeats dead-code elimination so `measure` times the real work.
    @inline(never)
    private func blackhole<T>(_ value: T) {
        _ = withExtendedLifetime(value) { }
    }
}
