//
//  WaterTests.swift
//  trackliftsTests
//
//  Guards Phase 3 water tracking: the display-unit ↔ milliliter conversion the
//  diary card + settings use, that a logged entry normalizes to the start of its
//  day, and that a day's total sums only that day's rows.
//

import Foundation
import Testing
import SwiftData
@testable import tracklifts

struct WaterUnitTests {

    @Test func unitConversionsAreCorrect() {
        #expect(WaterUnit.ml.milliliters == 1)
        #expect(abs(WaterUnit.oz.milliliters - 29.5735) < 1e-6)
        #expect(WaterUnit.cup.milliliters == 240)
    }

    @Test func roundTripsThroughMilliliters() {
        for unit in WaterUnit.allCases {
            let amount = 3.0
            let ml = amount * unit.milliliters     // enter "amount" of this unit
            #expect(abs(ml / unit.milliliters - amount) < 1e-9) // display reads it back
        }
    }
}

@MainActor
struct WaterModelTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self, FoodItem.self, FoodPortion.self, DiaryEntry.self,
            WaterEntry.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                        cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func entryNormalizesToStartOfDay() throws {
        let context = try makeContext()
        let noon = Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now)!
        let entry = WaterEntry(date: noon, amountMl: 250)
        context.insert(entry)
        try context.save()
        #expect(entry.date == Calendar.current.startOfDay(for: noon))
    }

    @Test func dayTotalSumsOnlyThatDay() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        context.insert(WaterEntry(date: today, amountMl: 250))
        context.insert(WaterEntry(date: today, amountMl: 500))
        context.insert(WaterEntry(date: yesterday, amountMl: 1000))
        try context.save()

        let all = try context.fetch(FetchDescriptor<WaterEntry>())
        let todayMl = all
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.amountMl }
        #expect(todayMl == 750, "only today's two entries should sum")
    }
}
