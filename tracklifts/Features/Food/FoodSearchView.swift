//
//  FoodSearchView.swift
//  tracklifts
//
//  The search-and-add engine (Phase 1): search the bundled food catalog, then
//  pick a serving + quantity + meal and commit a snapshotted diary entry.
//

import SwiftUI
import SwiftData

struct FoodSearchView: View {
    let meal: Meal
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]
    @State private var searchText = ""

    private var filtered: [FoodItem] {
        let base = searchText.isEmpty ? foods : foods.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
            || $0.brand.localizedCaseInsensitiveContains(searchText)
        }
        return base.sorted {
            ($0.isFavorite ? 0 : 1, $0.name) < ($1.isFavorite ? 0 : 1, $1.name)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if filtered.isEmpty {
                        Text(foods.isEmpty ? "Loading foods…" : "No matches for “\(searchText)”")
                            .font(.sans(15)).foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity).padding(.top, 50)
                    }
                    ForEach(filtered) { food in
                        NavigationLink {
                            LogFoodView(food: food, meal: meal, day: day) { dismiss() }
                        } label: {
                            FoodRow(food: food)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Add to \(meal.label)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search foods")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }
}

struct FoodRow: View {
    let food: FoodItem

    private var servingKcal: Int {
        Int(food.nutrients(forGrams: food.defaultPortion.grams).energy.rounded())
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name).font(.sans(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                HStack(spacing: 5) {
                    if !food.brand.isEmpty {
                        Text(food.brand).font(.sans(11, .semibold)).foregroundStyle(Palette.inkSecondary)
                        Text("·").foregroundStyle(Palette.inkTertiary)
                    }
                    Text("\(food.defaultPortion.label) · \(servingKcal) kcal")
                        .font(.sans(11)).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
            }
            Spacer()
            if food.isFavorite {
                Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
            }
            Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.ember)
        }
        .cardStyle(padding: 14)
    }
}

struct LogFoodView: View {
    let food: FoodItem
    let day: Date
    let onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @State private var meal: Meal
    @State private var portion: FoodPortion
    @State private var quantity: Double

    init(food: FoodItem, meal: Meal, day: Date, onLogged: @escaping () -> Void) {
        self.food = food
        self.day = day
        self.onLogged = onLogged
        _meal = State(initialValue: meal)
        _portion = State(initialValue: food.defaultPortion)
        _quantity = State(initialValue: 1)
    }

    private var grams: Double { portion.grams * quantity }
    private var nutrients: NutrientVector { food.nutrients(forGrams: grams) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name).font(.display(30)).foregroundStyle(Palette.ink)
                    if !food.brand.isEmpty {
                        Text(food.brand).font(.sans(13, .semibold)).foregroundStyle(Palette.inkSecondary)
                    }
                }

                nutritionPreview

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Serving", systemImage: "fork.knife")
                    Menu {
                        ForEach(food.orderedPortions) { option in
                            Button(option.label) { portion = option }
                        }
                    } label: {
                        HStack {
                            Text(portion.label).font(.sans(15, .semibold)).foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.ember)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .background(Palette.surfaceRaised, in: .rect(cornerRadius: 12))
                    }

                    HStack {
                        Text("Quantity").font(.sans(14, .semibold)).foregroundStyle(Palette.inkSecondary)
                        Spacer()
                        stepperButton("minus") { quantity = max(0.25, quantity - 0.25) }
                        Text(quantity.formatted())
                            .font(.sans(17, .bold)).foregroundStyle(Palette.ink)
                            .frame(minWidth: 48)
                            .contentTransition(.numericText())
                        stepperButton("plus") { quantity += 0.25 }
                    }
                    Text("\(Int(grams.rounded())) g total")
                        .font(.sans(12)).foregroundStyle(Palette.inkTertiary)
                }
                .cardStyle(padding: 16)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Meal", systemImage: "calendar")
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.segmented)
                }

                EmberButton(title: "Add to \(meal.label)", systemImage: "plus") { add() }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("Log Food")
        .navigationBarTitleDisplayMode(.inline)
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

    private var nutritionPreview: some View {
        HStack(spacing: 0) {
            previewStat(Int(nutrients.energy.rounded()).formatted(), "kcal", Palette.ember)
            previewDivider
            previewStat("\(Int(nutrients.protein.rounded()))g", "Protein", Palette.up)
            previewDivider
            previewStat("\(Int(nutrients.carbs.rounded()))g", "Carbs", Palette.gold)
            previewDivider
            previewStat("\(Int(nutrients.fat.rounded()))g", "Fat", Color(hex: 0x4DABF7))
        }
        .padding(.vertical, 16)
        .cardStyle(padding: 8)
    }

    private func previewStat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.display(26)).foregroundStyle(tint).contentTransition(.numericText())
            Text(label.uppercased()).font(.sans(9, .semibold)).tracking(0.6).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewDivider: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 30)
    }

    private func add() {
        let label = quantity == 1 ? portion.label : "\(quantity.formatted())× \(portion.label)"
        let entry = DiaryEntry(date: day, meal: meal, food: food, grams: grams, portionLabel: label)
        context.insert(entry)
        try? context.save()
        onLogged()
    }
}
