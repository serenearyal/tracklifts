//
//  FoodDiaryView.swift
//  tracklifts
//
//  The "Food" tab (Phase 1): a daily diary grouped by meal with an energy +
//  macro summary vs. your goals. A top search bar opens the catalog; entries
//  swipe to delete and tap to edit. List-based for native swipe actions.
//

import SwiftUI
import SwiftData

/// One sheet at a time — adding a food, or editing an existing entry.
private enum FoodSheet: Identifiable {
    case search(Meal)
    case edit(DiaryEntry)

    var id: String {
        switch self {
        case .search(let meal): "search-\(meal.rawValue)"
        case .edit(let entry): "edit-\(entry.persistentModelID.hashValue)"
        }
    }
}

struct FoodDiaryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DiaryEntry.createdAt) private var allEntries: [DiaryEntry]

    @AppStorage(NutritionGoals.energyKey) private var goalEnergy = NutritionGoals.defaultEnergy
    @AppStorage(NutritionGoals.proteinKey) private var goalProtein = NutritionGoals.defaultProtein
    @AppStorage(NutritionGoals.carbsKey) private var goalCarbs = NutritionGoals.defaultCarbs
    @AppStorage(NutritionGoals.fatKey) private var goalFat = NutritionGoals.defaultFat

    @State private var day: Date = Calendar.current.startOfDay(for: .now)
    @State private var sheet: FoodSheet?

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
            List {
                Section {
                    dateNav.diaryRow(top: 8, bottom: 2)
                    searchBar.diaryRow(top: 4, bottom: 2)
                    summaryCard.diaryRow(top: 6, bottom: 2)
                    if dayEntries.isEmpty, !previousDayEntries.isEmpty {
                        copyPreviousButton.diaryRow()
                    }
                }
                ForEach(Meal.allCases) { meal in
                    mealSection(meal)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationBarHidden(true)
            .sheet(item: $sheet) { item in
                switch item {
                case .search(let meal): FoodSearchView(meal: meal, day: day)
                case .edit(let entry): EditDiaryEntrySheet(entry: entry)
                }
            }
        }
    }

    // MARK: - Header pieces

    private var searchBar: some View {
        Button { sheet = .search(.defaultForNow) } label: {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.inkSecondary)
                Text("Search foods").font(.sans(15)).foregroundStyle(Palette.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.surface, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

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

    // MARK: - Meal section

    private func mealSection(_ meal: Meal) -> some View {
        let items = entries(for: meal)
        let kcal = items.reduce(0.0) { $0 + $1.kcal }
        return Section {
            if items.isEmpty {
                addFoodRow(meal).diaryRow(top: 2, bottom: 6)
            } else {
                ForEach(items) { entry in
                    entryRow(entry)
                        .diaryRow(top: 4, bottom: 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                context.delete(entry); try? context.save()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        } header: {
            mealHeader(meal, kcal: kcal)
        }
    }

    private func mealHeader(_ meal: Meal, kcal: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: meal.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ember)
            Text(meal.label).font(.sans(13, .bold)).tracking(1).foregroundStyle(Palette.ink).textCase(nil)
            Spacer()
            if kcal > 0 {
                Text("\(Int(kcal.rounded())) kcal").font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
            }
            Button { sheet = .search(meal) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 28, height: 28).background(Grad.ember, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
    }

    private func addFoodRow(_ meal: Meal) -> some View {
        Button { sheet = .search(meal) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Palette.ember)
                Text("Add food").font(.sans(14)).foregroundStyle(Palette.inkSecondary)
                Spacer()
            }
            .padding(.vertical, 11).padding(.horizontal, 14)
            .background(Palette.surface.opacity(0.5), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.plain)
    }

    private func entryRow(_ entry: DiaryEntry) -> some View {
        Button { sheet = .edit(entry) } label: {
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
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// Borderless full-bleed List row chrome over the app background.
    func diaryRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        self.listRowInsets(EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Edit entry

struct EditDiaryEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: DiaryEntry

    @State private var grams: Double
    @State private var meal: Meal

    init(entry: DiaryEntry) {
        self.entry = entry
        _grams = State(initialValue: entry.grams)
        _meal = State(initialValue: entry.meal)
    }

    private var preview: NutrientVector {
        if let food = entry.food { return food.nutrients(forGrams: grams) }
        if entry.grams > 0 { return entry.nutrients.scaled(by: grams / entry.grams) }
        return NutrientVector()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.foodName).font(.display(28)).foregroundStyle(Palette.ink)
                        if !entry.brand.isEmpty {
                            Text(entry.brand).font(.sans(13, .semibold)).foregroundStyle(Palette.inkSecondary)
                        }
                    }

                    MacroPreview(nutrients: preview)

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Amount", systemImage: "scalemass")
                        HStack(spacing: 10) {
                            Text("Grams").font(.sans(14, .semibold)).foregroundStyle(Palette.inkSecondary)
                            Spacer()
                            stepperButton("minus") { grams = max(1, grams - 5) }
                            TextField("0", value: $grams, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .font(.sans(17, .bold)).foregroundStyle(Palette.ink)
                                .frame(width: 70)
                            stepperButton("plus") { grams += 5 }
                            Text("g").font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .cardStyle(padding: 16)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Meal", systemImage: "calendar")
                        Picker("Meal", selection: $meal) {
                            ForEach(Meal.allCases) { m in Text(m.label).tag(m) }
                        }
                        .pickerStyle(.segmented)
                    }

                    EmberButton(title: "Save", systemImage: "checkmark") { save() }

                    Button(role: .destructive) { delete() } label: {
                        Text("Delete Entry")
                            .font(.sans(14, .semibold)).foregroundStyle(Palette.down)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    private func stepperButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ember)
                .frame(width: 36, height: 36)
                .background(Palette.surfaceRaised, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard grams > 0 else { return }
        entry.restate(grams: grams, meal: meal)
        try? context.save()
        dismiss()
    }

    private func delete() {
        context.delete(entry)
        try? context.save()
        dismiss()
    }
}
