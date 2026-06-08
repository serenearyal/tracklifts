//
//  SampleData.swift
//  tracklifts
//
//  Deterministic demo history used only when the app is launched with the
//  "--seed-sample" argument (UI tests / screenshots). Never runs in normal use.
//

import Foundation
import SwiftData

enum SampleData {
    /// Eight weekly sessions of progressive overload on four favorited lifts.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        guard existing == 0 else { return }

        let names = ["Barbell Bench Press", "Barbell Back Squat", "Deadlift", "Lat Pulldown"]
        let baseWeights: [Double] = [60, 80, 90, 45]

        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let targets = names.compactMap { name in all.first { $0.name == name } }
        guard !targets.isEmpty else { return }
        // Favorite a couple so the Favorites scope has content, while leaving the
        // rest to demonstrate that progress shows without favoriting.
        targets.prefix(2).forEach { $0.isFavorite = true }

        let calendar = Calendar.current
        let weeks = 8
        for week in 0..<weeks {
            // Oldest first; one session per week leading up to today.
            let daysAgo = 7 * (weeks - 1 - week)
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now)

            let session = WorkoutSession(date: date, title: week.isMultiple(of: 2) ? "Push" : "Pull")
            session.createdAt = date
            context.insert(session)

            for (index, exercise) in targets.enumerated() {
                let entry = LoggedExercise(exercise: exercise, order: index)
                entry.session = session
                context.insert(entry)

                let weight = baseWeights[index] + Double(week) * 2.5 // steady progression
                for setIndex in 0..<3 {
                    let set = LoggedSet(reps: 8, weight: weight, order: setIndex)
                    set.loggedExercise = entry
                    context.insert(set)
                }
            }
        }

        // A Push / Pull / Legs split using the same lifts, so split progress is
        // visible immediately — no favoriting required.
        let split = Split(name: "Push Pull Legs")
        context.insert(split)
        let dayDefs: [(String, [Int])] = [("Push", [0]), ("Pull", [3]), ("Legs", [1, 2])]
        for (dayIndex, def) in dayDefs.enumerated() {
            let day = SplitDay(name: def.0, order: dayIndex)
            day.split = split
            context.insert(day)
            for (order, exIndex) in def.1.enumerated() where exIndex < targets.count {
                let item = SplitItem(exercise: targets[exIndex], order: order)
                item.day = day
                context.insert(item)
            }
        }

        try? context.save()
    }
}
