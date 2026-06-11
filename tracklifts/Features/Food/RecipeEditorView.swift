//
//  RecipeEditorView.swift
//  tracklifts
//
//  Create or edit a recipe (Phase 3). Pick foods as ingredients, set grams +
//  servings, and the editor recomputes the recipe's single derived food (source
//  .recipe) on save — so a recipe logs through the same LogFoodView path as any
//  food. Mirrors EditFoodView's scaffold (cards, SectionLabel, keyboardDoneBar).
//

import SwiftUI
import SwiftData

struct RecipeEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = create a new recipe; non-nil = edit (and allow delete).
    var recipe: Recipe?

    @State private var name = ""
    @State private var servings: Double = 1
    /// Working ingredient set (food + grams), edited live; persisted on save.
    @State private var draft: [Draft] = []
    @State private var picking = false
    @State private var confirmingDelete = false

    struct Draft: Identifiable {
        let id = UUID()
        var food: FoodItem
        var grams: Double
    }

    private var isEditing: Bool { recipe != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.isEmpty && servings > 0
    }

    /// Live per-serving nutrients for the preview header.
    private var perServing: NutrientVector {
        let agg = RecipeMath.aggregate(draft.map { ($0.food.per100g, $0.grams) }, servings: servings)
        return agg.per100g.scaled(by: agg.servingGrams / 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailsCard
                    MacroPreview(nutrients: perServing)
                    ingredientsCard
                    if isEditing { deleteButton }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(isEditing ? "Edit Recipe" : "New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.sans(15)).foregroundStyle(Palette.inkSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave).font(.sans(15, .semibold))
                }
            }
            .keyboardDoneBar()
            .onAppear(perform: load)
            .sheet(isPresented: $picking) {
                RecipeFoodPicker { food in
                    draft.append(Draft(food: food, grams: food.defaultPortion.grams))
                }
            }
            .confirmationDialog("Delete this recipe?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Recipe", role: .destructive) { deleteRecipe() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Logged servings keep their saved nutrition — this only removes the recipe.")
            }
        }
    }

    // MARK: - Sections

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Recipe", systemImage: "list.clipboard")
            VStack(spacing: 12) {
                TextField("Name (e.g. Protein Smoothie)", text: $name)
                    .textInputAutocapitalization(.words)
                    .font(.sans(15)).foregroundStyle(Palette.ink)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .background(Palette.surfaceRaised, in: .rect(cornerRadius: 12))
                HStack {
                    Text("Servings").font(.sans(15)).foregroundStyle(Palette.ink)
                    Spacer()
                    stepperButton("minus") { servings = max(1, servings - 1) }
                    Text(servings.formatted())
                        .font(.sans(17, .bold)).foregroundStyle(Palette.ink)
                        .frame(minWidth: 44).contentTransition(.numericText())
                    stepperButton("plus") { servings += 1 }
                }
                Text("Logs as one serving = the total of all ingredients ÷ servings.")
                    .font(.sans(12)).foregroundStyle(Palette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle(padding: 14)
        }
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Ingredients", systemImage: "carrot")
            VStack(spacing: 8) {
                if draft.isEmpty {
                    Text("Add foods to build the recipe.")
                        .font(.sans(13)).foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
                ForEach($draft) { $item in
                    ingredientRow($item)
                }
                Button { picking = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Palette.ember)
                        Text("Add ingredient").font(.sans(14, .semibold)).foregroundStyle(Palette.ember)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .cardStyle(padding: 14)
        }
    }

    private func ingredientRow(_ item: Binding<Draft>) -> some View {
        let food = item.wrappedValue.food
        let kcal = Int((food.kcalPer100g * item.wrappedValue.grams / 100).rounded())
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(.sans(14, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("\(kcal) kcal").font(.sans(11)).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 8)
            TextField("0", value: item.grams, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.sans(15, .bold)).foregroundStyle(Palette.ink)
                .frame(width: 60)
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 8))
            Text("g").font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
            Button { draft.removeAll { $0.id == item.wrappedValue.id } } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(Palette.down.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            HStack(spacing: 8) {
                Spacer()
                Image(systemName: "trash")
                Text("Delete Recipe").font(.sans(15, .semibold))
                Spacer()
            }
            .foregroundStyle(Palette.down)
            .padding(.vertical, 14)
            .background(Palette.down.opacity(0.12), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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

    // MARK: - Load / save / delete

    private func load() {
        guard let recipe else { return }
        name = recipe.name
        servings = recipe.servings
        draft = recipe.orderedIngredients.compactMap { ing in
            guard let food = ing.food else { return nil }
            return Draft(food: food, grams: ing.grams)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !draft.isEmpty else { return }
        let agg = RecipeMath.aggregate(draft.map { ($0.food.per100g, $0.grams) }, servings: servings)

        let r: Recipe
        if let recipe {
            r = recipe
            r.name = trimmedName
            r.servings = servings
            for ing in recipe.orderedIngredients { context.delete(ing) } // rebuilt below
        } else {
            r = Recipe(name: trimmedName, servings: servings)
            context.insert(r)
        }
        for (index, d) in draft.enumerated() {
            let ing = RecipeIngredient(food: d.food, grams: d.grams, order: index)
            context.insert(ing)
            ing.recipe = r // to-one side only, after insert (iOS 17 rule)
        }

        // Refresh the derived, loggable food (created once, then reused).
        if let food = r.food {
            food.name = trimmedName
            food.per100g = agg.per100g // setter also refreshes kcalPer100g
            if let portion = food.orderedPortions.first {
                portion.label = "1 serving"
                portion.grams = agg.servingGrams
            } else {
                attachServingPortion(agg.servingGrams, to: food)
            }
        } else {
            let food = FoodItem(name: trimmedName, source: .recipe, per100g: agg.per100g, isCustom: true)
            context.insert(food)
            attachServingPortion(agg.servingGrams, to: food)
            r.food = food // one-to-one; both inserted
        }
        try? context.save()
        dismiss()
    }

    private func attachServingPortion(_ grams: Double, to food: FoodItem) {
        let portion = FoodPortion(label: "1 serving", grams: grams)
        context.insert(portion)
        portion.food = food
    }

    private func deleteRecipe() {
        guard let recipe else { return }
        context.delete(recipe) // cascades to ingredients + the derived food
        try? context.save()
        dismiss()
    }
}

// MARK: - Ingredient picker

/// A lightweight food search that hands a picked food back (no logging). Reuses
/// the shared `FoodSearch` ranking + `FoodRow`; tapping a row returns + dismisses.
private struct RecipeFoodPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let onPick: (FoodItem) -> Void

    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var recentEntries: [DiaryEntry]
    @State private var searchText = ""
    @State private var results: [FoodItem] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var recentFoods: [FoodItem] {
        var seen = Set<PersistentIdentifier>()
        var out: [FoodItem] = []
        for entry in recentEntries {
            guard let food = entry.food else { continue }
            if seen.insert(food.persistentModelID).inserted { out.append(food) }
            if out.count >= 8 { break }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                ScrollView {
                    LazyVStack(spacing: 10) {
                        let list = searchText.isEmpty ? recentFoods : results
                        if searchText.isEmpty, !recentFoods.isEmpty { header("Recent") }
                        ForEach(list) { food in
                            Button { onPick(food); dismiss() } label: { FoodRow(food: food) }
                                .buttonStyle(.plain)
                        }
                        if !searchText.isEmpty, results.isEmpty {
                            Text("No matches for “\(searchText)”")
                                .font(.sans(15)).foregroundStyle(Palette.inkSecondary)
                                .frame(maxWidth: .infinity).padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
            .background(AppBackground())
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
            }
            .onAppear { focused = true }
            .onChange(of: searchText) { _, v in scheduleSearch(v) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkSecondary)
            TextField("Search foods", text: $searchText)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .font(.sans(16)).foregroundStyle(Palette.ink)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Palette.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.hairline, lineWidth: 1))
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }

    private func header(_ text: String) -> some View {
        HStack {
            Text(text.uppercased())
                .font(.sans(12, .bold)).tracking(1.5).foregroundStyle(Palette.inkSecondary)
            Spacer()
        }
        .padding(.top, 6)
    }

    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; return }
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            results = FoodSearch.run(term, in: context)
        }
    }
}
