//
//  BodyWeightView.swift
//  tracklifts
//
//  Phase 0 of the nutrition/body roadmap: a real body-weight log. Records
//  weigh-ins over time, charts the trend, and keeps `BodyMetrics.current`
//  (the value the calisthenics effective-load math reads) in sync with the
//  most recent entry.
//

import SwiftUI
import SwiftData
import Charts

struct BodyWeightView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    @Query(sort: \BodyWeightEntry.date) private var entries: [BodyWeightEntry]

    @State private var window: TimeWindow = .all
    @State private var showingAdd = false

    /// Chronological (oldest → newest).
    private var sorted: [BodyWeightEntry] {
        entries.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    private var points: [ProgressPoint] {
        let all = sorted.map { ProgressPoint(id: $0.persistentModelID, date: $0.date, value: $0.weight) }
        guard let days = window.days else { return all }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return all.filter { $0.date >= cutoff }
    }

    private var latest: Double { sorted.last?.weight ?? 0 }

    private var windowDelta: Double? {
        guard let first = points.first?.value, let last = points.last?.value, points.count > 1 else { return nil }
        return last - first
    }

    /// Each entry paired with its change from the previous weigh-in, newest first.
    private var history: [(entry: BodyWeightEntry, delta: Double?)] {
        let s = sorted
        let withDelta = s.enumerated().map { i, e in
            (entry: e, delta: i > 0 ? e.weight - s[i - 1].weight : nil)
        }
        return withDelta.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if entries.isEmpty {
                    EmptyStateView(symbol: "figure",
                                   title: "No Weigh-Ins Yet",
                                   message: "Log your body weight to chart your trend over time.")
                        .padding(.top, 20)
                    EmberButton(title: "Log Your First Weigh-In", systemImage: "plus") { showingAdd = true }
                } else {
                    heroCard
                    EmberButton(title: "Log Weight", systemImage: "plus") { showingAdd = true }
                    rangePicker
                    if points.count >= 2 {
                        VStack(spacing: 14) { summaryRow; chart }.cardStyle(padding: 16)
                    } else {
                        notEnoughData
                    }
                    historySection
                }
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("Body Weight")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            AddBodyWeightSheet(defaultWeight: latest > 0 ? latest : nil, unit: unit)
        }
        .onAppear { BodyMetrics.refreshCurrent(from: entries) }
        .onChange(of: entries.count) { BodyMetrics.refreshCurrent(from: entries) }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Current weight")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latest.trimmedWeight)
                    .font(.display(64))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text(unit.label.uppercased())
                    .font(.display(24))
                    .foregroundStyle(Palette.inkSecondary)
            }
            if let d = windowDelta, abs(d) > 0.0001 {
                HStack(spacing: 5) {
                    Image(systemName: d < 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 11, weight: .black))
                    Text("\(abs(d).trimmedWeight) \(unit.label) \(window == .all ? "all time" : window.label.lowercased())")
                        .font(.sans(13, .semibold))
                }
                .foregroundStyle(Palette.ember)
            } else if let last = sorted.last {
                Text("Last logged \(last.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.sans(12)).foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20)
    }

    // MARK: - Range

    private var rangePicker: some View {
        HStack {
            Label("Range", systemImage: "calendar")
                .font(.sans(12, .semibold))
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Picker("Range", selection: $window) {
                ForEach(TimeWindow.allCases) { w in Text(w.label).tag(w) }
            }
            .pickerStyle(.menu)
            .tint(Palette.ember)
        }
    }

    // MARK: - Chart

    private var summaryRow: some View {
        let vals = points.map(\.value)
        return HStack(spacing: 0) {
            StatPill(value: vals.last.map(\.trimmedWeight) ?? "—", label: "Latest", tint: Palette.ember)
            statDivider
            StatPill(value: vals.min().map(\.trimmedWeight) ?? "—", label: "Lowest")
            statDivider
            StatPill(value: vals.max().map(\.trimmedWeight) ?? "—", label: "Highest")
        }
        .padding(.vertical, 6)
    }

    private var statDivider: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 34)
    }

    private var chart: some View {
        Chart(points) { point in
            AreaMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                .foregroundStyle(.linearGradient(colors: [Palette.ember.opacity(0.30), Palette.ember.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                .foregroundStyle(Palette.ember)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .shadow(color: Palette.ember.opacity(0.5), radius: 6, y: 3)
            PointMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                .foregroundStyle(Palette.ember)
                .symbolSize(36)
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
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Palette.ember)
            Text("Log at least two weigh-ins to see your trend.")
                .font(.sans(14)).foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).frame(height: 160)
        .cardStyle()
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "History", systemImage: "clock.arrow.circlepath")
            ForEach(history, id: \.entry.persistentModelID) { item in
                historyRow(item.entry, delta: item.delta)
            }
        }
    }

    private func historyRow(_ entry: BodyWeightEntry, delta: Double?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.sans(14, .semibold)).foregroundStyle(Palette.ink)
                Text(entry.date.formatted(.dateTime.year()))
                    .font(.sans(11)).foregroundStyle(Palette.inkTertiary)
            }
            Spacer()
            if let d = delta, abs(d) > 0.0001 {
                HStack(spacing: 3) {
                    Image(systemName: d < 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 9, weight: .black))
                    Text(abs(d).trimmedWeight).font(.sans(11, .bold))
                }
                .foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Palette.surfaceRaised, in: .capsule)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(entry.weight.trimmedWeight).font(.display(24)).foregroundStyle(Palette.ink)
                Text(unit.label).font(.sans(10, .semibold)).foregroundStyle(Palette.inkSecondary)
            }
        }
        .cardStyle()
        .contextMenu {
            Button(role: .destructive) {
                context.delete(entry)
                try? context.save()
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Add sheet

struct AddBodyWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let defaultWeight: Double?
    let unit: WeightUnit

    @State private var weight: Double
    @State private var date: Date = .now
    @FocusState private var focused: Bool

    init(defaultWeight: Double?, unit: WeightUnit) {
        self.defaultWeight = defaultWeight
        self.unit = unit
        _weight = State(initialValue: defaultWeight ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TextField("0", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .multilineTextAlignment(.trailing)
                            .font(.display(60))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: 200)
                        Text(unit.label.uppercased())
                            .font(.display(26))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(Palette.ember)
                        .cardStyle(padding: 16)

                    EmberButton(title: "Save Weigh-In", systemImage: "checkmark") { save() }
                        .opacity(weight > 0 ? 1 : 0.5)
                        .disabled(weight <= 0)

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        guard weight > 0 else { return }
        let entry = BodyWeightEntry(date: Calendar.current.startOfDay(for: date), weight: weight)
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}

// MARK: - Progress-tab summary card

struct BodyWeightSummaryCard: View {
    let entries: [BodyWeightEntry]
    let unit: WeightUnit

    private var sorted: [BodyWeightEntry] {
        entries.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }
    private var points: [ProgressPoint] {
        sorted.map { ProgressPoint(id: $0.persistentModelID, date: $0.date, value: $0.weight) }
    }
    private var latest: Double { sorted.last?.weight ?? 0 }
    private var delta: Double? {
        guard let first = sorted.first?.weight, let last = sorted.last?.weight, sorted.count > 1 else { return nil }
        return last - first
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.ember)
                .frame(width: 42, height: 42)
                .background(Palette.ember.opacity(0.14), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ember.opacity(0.30), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text("BODY WEIGHT")
                    .font(.sans(11, .bold)).tracking(1.2)
                    .foregroundStyle(Palette.inkSecondary)
                if latest > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(latest.trimmedWeight)
                            .font(.display(26)).foregroundStyle(Palette.ink)
                        Text(unit.label)
                            .font(.sans(10, .semibold)).foregroundStyle(Palette.inkSecondary)
                        if let d = delta, abs(d) > 0.0001 {
                            HStack(spacing: 2) {
                                Image(systemName: d < 0 ? "arrow.down.right" : "arrow.up.right")
                                    .font(.system(size: 9, weight: .black))
                                Text(abs(d).trimmedWeight).font(.sans(11, .bold))
                            }
                            .foregroundStyle(Palette.ember)
                        }
                    }
                } else {
                    Text("Track your weight trend")
                        .font(.sans(12)).foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
            if points.count >= 2 {
                Chart(points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                        .foregroundStyle(.linearGradient(colors: [Palette.ember.opacity(0.35), .clear],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                        .foregroundStyle(Palette.ember)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 92, height: 44)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .cardStyle()
    }
}

#Preview {
    NavigationStack { BodyWeightView() }
        .modelContainer(for: [BodyWeightEntry.self], inMemory: true)
        .preferredColorScheme(.dark)
}
