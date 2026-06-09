//
//  FoodDiaryView.swift
//  tracklifts
//
//  The "Food" tab (Phase 1): a daily diary grouped by meal, with an energy +
//  macro summary against your goals. Tapping a meal's add button opens the
//  search-and-log flow.
//

import SwiftUI
import SwiftData

struct FoodDiaryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DiaryEntry.createdAt) private var allEntries: [DiaryEntry]

    @AppStorage(NutritionGoals.energyKey) private var goalEnergy = NutritionGoals.defaultEnergy
    @AppStorage(NutritionGoals.proteinKey) private var goalProtein = NutritionGoals.defaultProtein
    @AppStorage(NutritionGoals.carbsKey) private var goalCarbs = NutritionGoals.defaultCarbs
    @AppStorage(NutritionGoals.fatKey) private var goalFat = NutritionGoals.defaultFat

    @State private var day: Date = Calendar.current.startOfDay(for: .now)
    @State private var searchMeal: Meal = .breakfast
    @State private var showingSearch = false

    private var dayEntries: [DiaryEntry] {
        allEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
    private var total: NutrientVector { DiaryMath.total(dayEntries) }

    private func entries(for meal: Meal) -> [DiaryEntry] {
        dayEntries.filter { $0.meal == meal }.sorted { $0.createdAt < $1.createdAt }
    }

    private var previousDayEntries: [DiaryEntry] {
        let prev = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        return allEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: prev) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dateNav.appearLift(0)
                    summaryCard.appearLift(1)
                    if dayEntries.isEmpty, !previousDayEntries.isEmpty {
                        copyPreviousButton.appearLift(2)
                    }
                    ForEach(Array(Meal.allCases.enumerated()), id: \.element) { index, meal in
                        mealSection(meal).appearLift(min(index + 2, 6))
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSearch) {
                FoodSearchView(meal: searchMeal, day: day)
            }
        }
    }

    // MARK: - Date navigator

    private var dateNav: some View {
        HStack(spacing: 12) {
            navButton("chevron.left") { shiftDay(-1) }
            VStack(spacing: 2) {
                Text(relativeLabel.uppercased())
                    .font(.sans(11, .bold)).tracking(1.8)
                    .foregroundStyle(Palette.ember)
                Text(day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.display(30))
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { day = Calendar.current.startOfDay(for: .now) } }
            navButton("chevron.right") { shiftDay(1) }
                .opacity(isToday ? 0.3 : 1)
                .disabled(isToday)
        }
        .padding(.top, 8)
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.ember)
                .frame(width: 42, height: 42)
                .background(Palette.surface, in: .circle)
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var relativeLabel: String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }
    private func shiftDay(_ delta: Int) {
        withAnimation(.snappy) {
            day = Calendar.current.date(byAdding: .day, value: delta, to: day) ?? day
        }
    }

    // MARK: - Summary

    private var remaining: Double { goalEnergy - total.energy }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Energy")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Int(total.energy.rounded()).formatted())
                            .font(.display(44)).foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text("/ \(Int(goalEnergy)) kcal")
                            .font(.sans(14, .semibold)).foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Int(abs(remaining).rounded()).formatted())
                        .font(.display(26))
                        .foregroundStyle(remaining >= 0 ? Palette.up : Palette.down)
                    Text(remaining >= 0 ? "LEFT" : "OVER")
                        .font(.sans(10, .bold)).tracking(1.2)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            MacroProgressBar(value: total.energy, goal: goalEnergy, color: Palette.ember)
            HStack(spacing: 12) {
                MacroStat(label: "Protein", value: total.protein, goal: goalProtein, color: Palette.up)
                MacroStat(label: "Carbs", value: total.carbs, goal: goalCarbs, color: Palette.gold)
                MacroStat(label: "Fat", value: total.fat, goal: goalFat, color: Color(hex: 0x4DABF7))
            }
        }
        .cardStyle(padding: 18)
    }

    private var copyPreviousButton: some View {
        Button { withAnimation(.snappy) { copyPreviousDay() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc.fill").font(.system(size: 12, weight: .bold))
                Text("Copy \(previousDayEntries.count) items from the previous day")
                    .font(.sans(13, .semibold))
            }
            .foregroundStyle(Palette.ember)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Palette.ember.opacity(0.12), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.ember.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func copyPreviousDay() {
        for entry in previousDayEntries {
            guard let food = entry.food else { continue }
            context.insert(DiaryEntry(date: day, meal: entry.meal, food: food,
                                      grams: entry.grams, portionLabel: entry.portionLabel))
        }
        try? context.save()
    }

    // MARK: - Meal sections

    private func mealSection(_ meal: Meal) -> some View {
        let items = entries(for: meal)
        let kcal = items.reduce(0.0) { $0 + $1.kcal }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: meal.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ember)
                Text(meal.label.uppercased()).font(.sans(13, .bold)).tracking(1.2).foregroundStyle(Palette.ink)
                Spacer()
                if kcal > 0 {
                    Text("\(Int(kcal.rounded())) kcal").font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                }
                Button { searchMeal = meal; showingSearch = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 30, height: 30).background(Grad.ember, in: .circle)
                }
                .buttonStyle(.plain)
            }
            if items.isEmpty {
                Button { searchMeal = meal; showingSearch = true } label: {
                    Text("Add food")
                        .font(.sans(13)).foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .background(Palette.surface.opacity(0.5), in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(items) { entry in entryRow(entry) }
            }
        }
    }

    private func entryRow(_ entry: DiaryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName).font(.sans(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(entry.servingText).font(.sans(12)).foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(entry.kcal.rounded()))").font(.display(22)).foregroundStyle(Palette.ink)
                Text("kcal").font(.sans(10, .semibold)).foregroundStyle(Palette.inkSecondary)
            }
        }
        .cardStyle(padding: 14)
        .contextMenu {
            Button(role: .destructive) {
                context.delete(entry); try? context.save()
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Reusable bars

struct MacroProgressBar: View {
    let value: Double
    let goal: Double
    var color: Color = Palette.ember

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceRaised)
                Capsule().fill(color)
                    .frame(width: max(0, min(1, goal > 0 ? value / goal : 0)) * geo.size.width)
            }
        }
        .frame(height: 8)
    }
}

struct MacroStat: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label.uppercased()).font(.sans(10, .bold)).tracking(0.6).foregroundStyle(Palette.inkSecondary)
            }
            Text("\(Int(value.rounded()))g").font(.sans(16, .bold)).foregroundStyle(Palette.ink)
            MacroProgressBar(value: value, goal: goal, color: color)
            Text("of \(Int(goal))g").font(.sans(10)).foregroundStyle(Palette.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
