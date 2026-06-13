//
//  TodayView.swift
//  tracklifts
//
//  The "Today" tab: a daily command center. One glance covers today's food
//  vs. targets, today's training, and your body weight — each with its quick
//  action — plus the gateway to Settings. New roadmap surfaces (capture
//  sheet, energy balance) land here as additional cards.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Binding var selectedTab: AppTab

    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    @AppStorage(NutritionGoals.energyKey) private var goalEnergy = NutritionGoals.defaultEnergy
    @AppStorage(NutritionGoals.proteinKey) private var goalProtein = NutritionGoals.defaultProtein
    @AppStorage(NutritionGoals.carbsKey) private var goalCarbs = NutritionGoals.defaultCarbs
    @AppStorage(NutritionGoals.fatKey) private var goalFat = NutritionGoals.defaultFat

    @Query(sort: \DiaryEntry.createdAt) private var allEntries: [DiaryEntry]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]

    @State private var editingSession: WorkoutSession?
    @State private var showingFoodSearch = false
    @State private var showingCapture = false
    @State private var showingAddWeight = false

    // MARK: - Derived (calendar filters aren't #Predicate-expressible; filter in memory)

    private var todayEntries: [DiaryEntry] {
        allEntries.filter { Calendar.current.isDateInToday($0.date) }
    }
    private var eaten: NutrientVector { DiaryMath.total(todayEntries) }
    private var remaining: Double { goalEnergy - eaten.energy }

    private var todaySessions: [WorkoutSession] {
        sessions.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var latestWeight: Double? {
        weights.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }.last?.weight
    }

    private var weekSessions: [WorkoutSession] {
        sessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
    }
    private var weekSets: Int { weekSessions.reduce(0) { $0 + $1.totalSets } }
    private var weekVolume: Double { weekSessions.reduce(0) { $0 + $1.totalVolume } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header.appearLift(0)
                    nutritionSection.appearLift(1)
                    trainingSection.appearLift(2)
                    bodyWeightSection.appearLift(3)
                    weekStrip.appearLift(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationBarHidden(true)
            .sheet(item: $editingSession) { session in
                NavigationStack {
                    LogWorkoutView(session: session, isNew: true)
                }
            }
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(meal: .defaultForNow, day: .now)
            }
            .sheet(isPresented: $showingCapture) {
                CaptureView(day: .now)
            }
            .sheet(isPresented: $showingAddWeight) {
                AddBodyWeightSheet(defaultWeight: latestWeight, unit: unit)
            }
            .onChange(of: weights.count) { BodyMetrics.refreshCurrent(from: weights) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            ScreenHeader(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                         title: "Today")
            Spacer()
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 42, height: 42)
                    .background(Palette.surface, in: .circle)
                    .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsButton")
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    // MARK: - Nutrition

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: "Nutrition", systemImage: "fork.knife")
                Spacer()
                captureButton
                quickAdd("Add Food") { showingFoodSearch = true }
            }
            Button { selectedTab = .food } label: {
                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Int(eaten.energy.rounded()).formatted())
                                .font(.display(40)).foregroundStyle(Palette.ink)
                                .contentTransition(.numericText())
                            Text("/ \(Int(goalEnergy)) kcal")
                                .font(.sans(13, .semibold)).foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Int(abs(remaining).rounded()).formatted())
                                .font(.display(22))
                                .foregroundStyle(remaining >= 0 ? Palette.up : Palette.down)
                            Text(remaining >= 0 ? "LEFT" : "OVER")
                                .font(.sans(9, .bold)).tracking(1.2)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    MacroProgressBar(value: eaten.energy, goal: goalEnergy, color: Palette.ember)
                    HStack(spacing: 12) {
                        MacroStat(label: "Protein", value: eaten.protein, goal: goalProtein, color: Palette.up)
                        MacroStat(label: "Carbs", value: eaten.carbs, goal: goalCarbs, color: Palette.gold)
                        MacroStat(label: "Fat", value: eaten.fat, goal: goalFat, color: Color(hex: 0x4DABF7))
                    }
                }
                .cardStyle(padding: 18)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Training

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: "Training", systemImage: "dumbbell.fill")
                Spacer()
                if !todaySessions.isEmpty {
                    quickAdd("Log Workout") { editingSession = WorkoutSession.blank(in: context) }
                }
            }
            if todaySessions.isEmpty {
                EmberButton(title: "Log Today's Workout", systemImage: "plus") {
                    editingSession = WorkoutSession.blank(in: context)
                }
                if let last = sessions.first {
                    Button {
                        editingSession = WorkoutSession.repeated(from: last, in: context)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .bold))
                            Text("REPEAT LAST WORKOUT")
                                .font(.sans(13, .bold)).tracking(1)
                        }
                        .foregroundStyle(Palette.ember)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Palette.surface, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Palette.ember.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(todaySessions, id: \.persistentModelID) { session in
                    NavigationLink {
                        LogWorkoutView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Body weight

    private var bodyWeightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: "Body Weight", systemImage: "figure")
                Spacer()
                quickAdd("Log Weight") { showingAddWeight = true }
            }
            NavigationLink {
                BodyWeightView()
            } label: {
                BodyWeightSummaryCard(entries: weights, unit: unit)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - This week

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "This Week", systemImage: "calendar")
            HStack(spacing: 12) {
                StatTile(value: "\(weekSessions.count)", label: "Workouts", systemImage: "flame.fill")
                StatTile(value: "\(weekSets)", label: "Sets",
                         systemImage: "square.stack.3d.up.fill", tint: Palette.gold)
                StatTile(value: Int(weekVolume).formatted(.number.notation(.compactName)),
                         label: "Vol (\(unit.label))", systemImage: "scalemass.fill", tint: Palette.emberHi)
            }
        }
    }

    // MARK: - Bits

    /// Prominent camera pill — opens the capture sheet (snap a photo / type / speak).
    private var captureButton: some View {
        Button { showingCapture = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill").font(.system(size: 12, weight: .bold))
                Text("Snap Meal").font(.sans(12, .bold)).tracking(0.5)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Grad.ember, in: .capsule)
            .shadow(color: Palette.ember.opacity(0.45), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture a meal")
        .accessibilityIdentifier("captureButton")
    }

    /// Small ember circle in a section row — the card's quick action.
    private func quickAdd(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(Grad.ember, in: .circle)
                .shadow(color: Palette.ember.opacity(0.4), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    TodayView(selectedTab: .constant(.today))
        .modelContainer(for: [
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
            BodyWeightEntry.self,
            FoodItem.self, FoodPortion.self, DiaryEntry.self,
        ], inMemory: true)
        .preferredColorScheme(.dark)
}
