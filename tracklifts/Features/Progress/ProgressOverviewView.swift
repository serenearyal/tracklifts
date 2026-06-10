//
//  ProgressOverviewView.swift
//  tracklifts
//
//  The "Progress" tab — the app's showcase. Total volume hero, headline stats,
//  recent records, and a scope selector to view progress by everything you've
//  tracked, your favorites, or any split (grouped by day).
//

import SwiftUI
import SwiftData
import Charts

/// What the progress list is currently showing.
enum ProgressScope: Hashable {
    case tracked
    case favorites
    case split(PersistentIdentifier)
}

struct ProgressOverviewView: View {
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    @AppStorage(BodyMetrics.key) private var bodyWeight: Double = 0

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(filter: #Predicate<Exercise> { $0.isFavorite }, sort: \Exercise.name)
    private var favorites: [Exercise]
    @Query(sort: [SortDescriptor(\Split.order), SortDescriptor(\Split.createdAt)])
    private var splits: [Split]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]

    @State private var scope: ProgressScope = .tracked

    var body: some View {
        NavigationStack {
            ScrollView {
                if sessions.isEmpty {
                    VStack(spacing: 28) {
                        header
                        EmptyStateView(symbol: "chart.xyaxis.line",
                                       title: "No Progress Yet",
                                       message: "Log a few sessions and your strength trends appear here.")
                            .cardStyle(padding: 28)
                    }
                    .padding(20)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        header.appearLift(0)
                        heroCard.appearLift(1)
                        statsRow.appearLift(2)
                        bodyWeightCard.appearLift(3)
                        recordsSection.appearLift(4)
                        trackSection.appearLift(5)
                    }
                    .padding(20)
                    .padding(.bottom, 36)
                }
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header

    private var header: some View {
        ScreenHeader(eyebrow: "Your strength journey", title: "Progress")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero

    private var totalVolume: Double { sessions.reduce(0) { $0 + $1.totalVolume } }

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 130, weight: .black))
                .foregroundStyle(.black.opacity(0.10))
                .rotationEffect(.degrees(-20))
                .offset(x: 30, y: 6)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Total volume lifted", color: .black.opacity(0.65))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Int(totalVolume).formatted())
                        .font(.display(72))
                        .foregroundStyle(.black)
                    Text(unit.label.uppercased())
                        .font(.display(26))
                        .foregroundStyle(.black.opacity(0.7))
                }
                HStack(spacing: 8) {
                    Label("\(sessions.count) workouts", systemImage: "calendar")
                    if let first = sessions.last?.date {
                        Text("since \(first.formatted(.dateTime.month(.abbreviated).year()))")
                    }
                }
                .font(.sans(13, .semibold))
                .foregroundStyle(.black.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .background(Grad.ember, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: Palette.ember.opacity(0.45), radius: 22, x: 0, y: 14)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(sessions.count)", label: "Workouts", systemImage: "flame.fill")
            StatTile(value: "\(workoutsThisWeek)", label: "This Week", systemImage: "bolt.fill", tint: Palette.emberHi)
            StatTile(value: "\(totalSets)", label: "Total Sets", systemImage: "square.stack.3d.up.fill", tint: Palette.gold)
        }
    }

    private var workoutsThisWeek: Int {
        let cal = Calendar.current
        return sessions.filter { cal.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count
    }

    private var totalSets: Int { sessions.reduce(0) { $0 + $1.totalSets } }

    // MARK: - Body weight

    private var bodyWeightCard: some View {
        NavigationLink { BodyWeightView() } label: {
            BodyWeightSummaryCard(entries: weights, unit: unit)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Records

    private var recentPRs: [(exercise: Exercise, value: Double, metric: ProgressMetric)] {
        var results: [(exercise: Exercise, value: Double, metric: ProgressMetric, date: Date)] = []
        for exercise in trackedExercises {
            let metric = exercise.primaryMetric
            let series = ProgressCalculator.series(for: exercise, metric: metric, in: sessions.reversed())
            guard series.count >= 2, let best = series.map(\.value).max(), best > 0,
                  let last = series.last, last.value >= best - 0.001 else { continue }
            results.append((exercise, best, metric, last.date))
        }
        // Most-recent PR first — matches "Recent Records" and stays metric-
        // agnostic, so we never rank kilograms against rep counts.
        return results
            .sorted { $0.date > $1.date }
            .map { ($0.exercise, $0.value, $0.metric) }
    }

    /// Every exercise that has ever been logged, most-recently-trained first.
    private var trackedExercises: [Exercise] {
        var seen = Set<PersistentIdentifier>()
        var result: [Exercise] = []
        for session in sessions {
            for entry in session.orderedEntries {
                guard let ex = entry.exercise, entry.setCount > 0 else { continue }
                if seen.insert(ex.persistentModelID).inserted { result.append(ex) }
            }
        }
        return result
    }

    @ViewBuilder
    private var recordsSection: some View {
        let prs = recentPRs
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Recent Records", systemImage: "trophy.fill")
                VStack(spacing: 10) {
                    ForEach(Array(prs.prefix(5).enumerated()), id: \.element.exercise.persistentModelID) { index, pr in
                        NavigationLink {
                            ExerciseDetailView(exercise: pr.exercise)
                        } label: {
                            recordRow(rank: index + 1, exercise: pr.exercise, value: pr.value, metric: pr.metric)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func recordRow(rank: Int, exercise: Exercise, value: Double, metric: ProgressMetric) -> some View {
        let reps = metric == .bestReps
        return HStack(spacing: 14) {
            Text(String(format: "%02d", rank))
                .font(.display(26))
                .foregroundStyle(rank == 1 ? Palette.gold : Palette.inkTertiary)
                .frame(width: 32)
            MuscleGlyph(group: exercise.muscleGroup, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.sans(15, .semibold))
                    .foregroundStyle(Palette.ink)
                Text(reps ? "Best set" : "Best est. 1RM")
                    .font(.sans(11))
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(reps ? String(Int(value)) : value.trimmedWeight)
                    .font(.display(28))
                    .foregroundStyle(Palette.up)
                Text(reps ? "reps" : unit.label)
                    .font(.sans(11, .semibold))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Track section (scope selector + per-scope progress)

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Track Progress", systemImage: "scope")
            scopeChips
            scopeContent
        }
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tracked", systemImage: "bolt.fill", active: scope == .tracked) { scope = .tracked }
                chip("Favorites", systemImage: "star.fill", active: scope == .favorites) { scope = .favorites }
                ForEach(splits) { split in
                    chip(split.name, systemImage: "rectangle.3.group.fill",
                         active: scope == .split(split.persistentModelID)) {
                        scope = .split(split.persistentModelID)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
                Text(title).font(.sans(13, .bold)).tracking(0.5)
            }
            .foregroundStyle(active ? Color.black : Palette.inkSecondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background {
                if active { Capsule().fill(Grad.ember) }
                else { Capsule().fill(Palette.surface).overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1)) }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var scopeContent: some View {
        switch scope {
        case .tracked:
            trendList(trackedExercises,
                      emptyHint: "Log a workout to start tracking lifts here.")
        case .favorites:
            trendList(favorites,
                      emptyHint: "Tap the star on any exercise — or “Favorite all” on a split — to pin lifts here.")
        case .split(let id):
            splitProgress(id)
        }
    }

    @ViewBuilder
    private func trendList(_ exercises: [Exercise], emptyHint: String) -> some View {
        if exercises.isEmpty {
            Text(emptyHint)
                .font(.sans(14)).foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        } else {
            LazyVStack(spacing: 10) {
                ForEach(exercises) { exercise in
                    NavigationLink { ExerciseDetailView(exercise: exercise) } label: {
                        ExerciseTrendCard(exercise: exercise, sessions: sessions, unit: unit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func splitProgress(_ id: PersistentIdentifier) -> some View {
        if let split = splits.first(where: { $0.persistentModelID == id }) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(split.orderedDays) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(day.name.uppercased())
                                .font(.sans(12, .bold)).tracking(1.2)
                                .foregroundStyle(Palette.ink)
                            Rectangle().fill(Palette.hairline).frame(height: 1)
                        }
                        if day.exercises.isEmpty {
                            Text("No exercises in this day yet.")
                                .font(.sans(13)).foregroundStyle(Palette.inkSecondary)
                        } else {
                            ForEach(day.exercises) { exercise in
                                NavigationLink { ExerciseDetailView(exercise: exercise) } label: {
                                    ExerciseTrendCard(exercise: exercise, sessions: sessions, unit: unit)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        } else {
            Text("This split was removed.")
                .font(.sans(14)).foregroundStyle(Palette.inkSecondary)
        }
    }
}

// MARK: - Trend card

struct ExerciseTrendCard: View {
    let exercise: Exercise
    let sessions: [WorkoutSession]
    let unit: WeightUnit

    private var metric: ProgressMetric { exercise.primaryMetric }

    private var points: [ProgressPoint] {
        ProgressCalculator.series(for: exercise, metric: metric, in: sessions.reversed())
    }

    private var valueUnit: String { metric == .bestReps ? "reps" : unit.label }

    private func formattedValue(_ value: Double) -> String {
        metric == .bestReps ? String(Int(value)) : value.trimmedWeight
    }

    var body: some View {
        HStack(spacing: 14) {
            MuscleGlyph(group: exercise.muscleGroup, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(.sans(14, .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if exercise.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.gold)
                    }
                }
                if let latest = points.last?.value, latest > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formattedValue(latest))
                            .font(.display(26))
                            .foregroundStyle(exercise.muscleGroup.color)
                        Text(valueUnit)
                            .font(.sans(10, .semibold))
                            .foregroundStyle(Palette.inkSecondary)
                        if let trend = ProgressCalculator.trendPercent(points) {
                            TrendChip(percent: trend)
                        }
                    }
                } else {
                    Text("Not logged yet")
                        .font(.sans(12))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
            if points.count >= 2 {
                Chart(points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("1RM", point.value))
                        .foregroundStyle(.linearGradient(
                            colors: [exercise.muscleGroup.color.opacity(0.35), .clear],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Date", point.date), y: .value("1RM", point.value))
                        .foregroundStyle(exercise.muscleGroup.color)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 96, height: 44)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .cardStyle()
    }
}
