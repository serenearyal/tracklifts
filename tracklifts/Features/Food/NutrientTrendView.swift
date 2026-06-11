//
//  NutrientTrendView.swift
//  tracklifts
//
//  Phase 2: any nutrient's daily total over time, with the personalized target
//  drawn as a reference line. Mirrors the BodyWeightView chart so the Progress
//  language stays consistent (Area + Line + Point, ember accent, range picker).
//

import SwiftUI
import SwiftData
import Charts

struct NutrientTrendView: View {
    @Query(sort: \DiaryEntry.date) private var entries: [DiaryEntry]
    @State private var selected: Nutrient
    @State private var window: TimeWindow = .all

    private let sex = Profile.sex
    private let age = Profile.age

    init(initial: Nutrient = .protein) {
        _selected = State(initialValue: initial)
    }

    private struct DayPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    /// One summed point per day for the selected nutrient, within the window.
    private var points: [DayPoint] {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for e in entries {
            byDay[cal.startOfDay(for: e.date), default: 0] += e.nutrients[selected]
        }
        var pts = byDay.map { DayPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        if let days = window.days {
            let cutoff = cal.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
            pts = pts.filter { $0.date >= cutoff }
        }
        return pts
    }

    private var target: Double? {
        let t = selected.target(sex: sex, age: age) ?? 0
        return t > 0 ? t : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                nutrientPicker
                rangePicker
                if points.count >= 2 {
                    VStack(spacing: 14) { summaryRow; chart }.cardStyle(padding: 16)
                } else {
                    notEnoughData
                }
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("Nutrient Trends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar) // diary hides its bar; show ours on push
    }

    // MARK: - Pickers

    private var nutrientPicker: some View {
        Menu {
            Picker("Nutrient", selection: $selected) {
                ForEach(Nutrient.allCases) { n in Text(n.label).tag(n) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Nutrient")
                    Text(selected.label).font(.display(30)).foregroundStyle(Palette.ink)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.ember)
            }
            .cardStyle(padding: 18)
        }
        .buttonStyle(.plain)
    }

    private var rangePicker: some View {
        HStack {
            Label("Range", systemImage: "calendar")
                .font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
            Spacer()
            Picker("Range", selection: $window) {
                ForEach(TimeWindow.allCases) { w in Text(w.label).tag(w) }
            }
            .pickerStyle(.menu).tint(Palette.ember)
        }
    }

    // MARK: - Chart

    private var summaryRow: some View {
        let vals = points.map(\.value)
        let avg = vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
        return HStack(spacing: 0) {
            StatPill(value: fmt(vals.last ?? 0), label: "Latest", tint: Palette.ember)
            statDivider
            StatPill(value: fmt(avg), label: "Average")
            statDivider
            StatPill(value: fmt(vals.max() ?? 0), label: "Peak")
        }
        .padding(.vertical, 6)
    }

    private var statDivider: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 34)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.date), y: .value(selected.label, point.value))
                    .foregroundStyle(.linearGradient(colors: [Palette.ember.opacity(0.30), Palette.ember.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", point.date), y: .value(selected.label, point.value))
                    .foregroundStyle(Palette.ember)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .shadow(color: Palette.ember.opacity(0.5), radius: 6, y: 3)
                PointMark(x: .value("Date", point.date), y: .value(selected.label, point.value))
                    .foregroundStyle(Palette.ember)
                    .symbolSize(36)
            }
            if let target {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Palette.inkSecondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target \(fmt(target)) \(selected.unit)")
                            .font(.sans(9, .semibold)).foregroundStyle(Palette.inkSecondary)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.sans(10)).foregroundStyle(Palette.inkSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().font(.sans(10)).foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(height: 220)
    }

    private var notEnoughData: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.ember)
            Text("Log \(selected.label.lowercased()) on at least two days to see a trend.")
                .font(.sans(14)).foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).frame(height: 160).cardStyle()
    }

    private func fmt(_ v: Double) -> String {
        if v >= 10 { return String(Int(v.rounded())) }
        if v >= 1 { return String(format: "%.1f", v) }
        if v > 0 { return String(format: "%.2f", v) }
        return "0"
    }
}
