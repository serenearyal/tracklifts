//
//  ExerciseProgressView.swift
//  tracklifts
//
//  The progression chart + stats for a single exercise. Reused by the exercise
//  detail screen and the Progress tab.
//

import SwiftUI
import SwiftData
import Charts

struct ExerciseProgressView: View {
    let exercise: Exercise
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg

    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @State private var metric: ProgressMetric
    @State private var window: TimeWindow = .all

    init(exercise: Exercise) {
        self.exercise = exercise
        // Pure bodyweight lifts (no recorded body weight) progress by reps.
        _metric = State(initialValue: exercise.primaryMetric)
    }

    private var accent: Color { exercise.muscleGroup.color }

    private var relevantSessions: [WorkoutSession] {
        sessions.filter { session in
            session.entries.contains { $0.exercise?.persistentModelID == exercise.persistentModelID }
        }
    }

    private var allTimePoints: [ProgressPoint] {
        ProgressCalculator.series(for: exercise, metric: metric, in: relevantSessions)
    }

    private var points: [ProgressPoint] {
        guard let days = window.days else { return allTimePoints }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return allTimePoints.filter { $0.date >= cutoff }
    }

    private var unitSuffix: String { metric.isWeightUnit ? " \(unit.label)" : "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Metric", selection: $metric) {
                ForEach(ProgressMetric.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Label("Range", systemImage: "calendar")
                    .font(.sans(12, .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Picker("Range", selection: $window) {
                    ForEach(TimeWindow.allCases) { w in
                        Text(w.label).tag(w)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.ember)
            }

            if points.count < 2 {
                notEnoughData
            } else {
                summaryRow
                chart
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 0) {
            let values = points.map(\.value)
            StatPill(value: formatted(values.last ?? 0), label: "Latest", tint: accent)
            divider
            StatPill(value: formatted(values.max() ?? 0), label: "Best")
            divider
            if let trend = ProgressCalculator.trendPercent(points) {
                StatPill(value: String(format: "%+.0f%%", trend),
                         label: "Change",
                         tint: trend >= 0 ? Palette.up : Palette.down)
            } else {
                StatPill(value: "—", label: "Change")
            }
        }
        .padding(.vertical, 6)
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 34)
    }

    private var chart: some View {
        Chart(points) { point in
            AreaMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                .foregroundStyle(.linearGradient(
                    colors: [accent.opacity(0.35), accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)

            LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                .foregroundStyle(accent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .shadow(color: accent.opacity(0.5), radius: 6, y: 3)

            PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                .foregroundStyle(accent)
                .symbolSize(36)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.sans(10))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel()
                    .font(.sans(10))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(height: 220)
    }

    private var notEnoughData: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(accent)
            Text(emptyMessage)
                .font(.sans(14))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    private var emptyMessage: String {
        if allTimePoints.isEmpty { return "No data logged yet" }
        if window != .all && allTimePoints.count >= 2 {
            return "Not enough data in \(window.label.lowercased()) — try All time"
        }
        return "Log this lift again to see a trend"
    }

    private func formatted(_ value: Double) -> String {
        if metric == .bestReps { return String(Int(value)) }
        return value.trimmedWeight + unitSuffix
    }
}
