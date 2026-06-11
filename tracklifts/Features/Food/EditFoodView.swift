//
//  EditFoodView.swift
//  tracklifts
//
//  Create or edit a custom food (Phase 3). Nutrients are entered the way a
//  nutrition label reads — per serving — and converted to the per-100 g vector
//  the catalog stores. A custom food then flows through the same search → log →
//  diary path as a seeded food, with no special-casing anywhere downstream.
//

import SwiftUI
import SwiftData

struct EditFoodView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = create a new food; non-nil = edit (and allow delete).
    var food: FoodItem?
    /// Seeds the name field on create (e.g. the search term that found nothing).
    var prefillName: String = ""
    /// On the barcode "not found → create it" path, the scanned GTIN to store.
    var prefillBarcode: String = ""

    @State private var name = ""
    @State private var brand = ""
    @State private var servingLabel = "1 serving"
    @State private var servingGrams: Double = 100
    /// Per-serving amounts keyed by `Nutrient.rawValue`; converted on save.
    @State private var amounts: [String: Double] = [:]
    @State private var showMore = false
    @State private var confirmingDelete = false

    private var isEditing: Bool { food != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && servingGrams > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailsCard
                    servingCard
                    nutrientGroup(.macros)
                    moreNutrientsSection
                    if isEditing { deleteButton }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(isEditing ? "Edit Food" : "New Food")
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
            .confirmationDialog("Delete this food?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Food", role: .destructive) { deleteFood() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Logged entries keep their saved nutrition — this only removes the food from your list.")
            }
        }
    }

    // MARK: - Sections

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Food", systemImage: "fork.knife")
            VStack(spacing: 8) {
                plainField("Name (e.g. Protein Bar)", text: $name)
                    .textInputAutocapitalization(.words)
                plainField("Brand (optional)", text: $brand)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    private var servingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Serving", systemImage: "scalemass")
            VStack(spacing: 12) {
                plainField("Serving name (e.g. 1 bar)", text: $servingLabel)
                HStack {
                    Text("Serving size").font(.sans(15)).foregroundStyle(Palette.ink)
                    Spacer()
                    decimalField($servingGrams)
                    Text("g").font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                        .frame(width: 38, alignment: .leading)
                }
                Text("Enter the nutrition below as printed on the label for one serving.")
                    .font(.sans(12)).foregroundStyle(Palette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle(padding: 14)
        }
    }

    /// One nutrient group (e.g. Macros) as a card of labelled decimal fields.
    private func nutrientGroup(_ group: NutrientGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: group.label, systemImage: group.symbol)
            VStack(spacing: 4) {
                ForEach(Nutrient.allCases.filter { $0.group == group }) { n in
                    nutrientRow(n)
                }
            }
            .cardStyle(padding: 10)
        }
    }

    /// Fats / vitamins / minerals, collapsed by default so the common case stays
    /// kcal + macros while power users still get full Cronometer-class depth.
    private var moreNutrientsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy) { showMore.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ember)
                    Text(showMore ? "Fewer nutrients" : "More nutrients")
                        .font(.sans(14, .bold)).tracking(1.5).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: showMore ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            if showMore {
                nutrientGroup(.fats)
                nutrientGroup(.vitamins)
                nutrientGroup(.minerals)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmingDelete = true } label: {
            HStack(spacing: 8) {
                Spacer()
                Image(systemName: "trash")
                Text("Delete Food").font(.sans(15, .semibold))
                Spacer()
            }
            .foregroundStyle(Palette.down)
            .padding(.vertical, 14)
            .background(Palette.down.opacity(0.12), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row builders

    private func plainField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.sans(15)).foregroundStyle(Palette.ink)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 12))
    }

    private func nutrientRow(_ n: Nutrient) -> some View {
        HStack {
            Text(n.label).font(.sans(15)).foregroundStyle(Palette.ink)
            Spacer()
            decimalField(amountBinding(n))
            Text(n.unit).font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                .frame(width: 38, alignment: .leading)
        }
    }

    private func decimalField(_ value: Binding<Double>) -> some View {
        TextField("0", value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.sans(16, .bold)).foregroundStyle(Palette.ink)
            .frame(width: 80)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))
    }

    /// Reads/writes the per-serving amount for a nutrient; clears the key when 0
    /// so the stored vector stays sparse.
    private func amountBinding(_ n: Nutrient) -> Binding<Double> {
        Binding(
            get: { amounts[n.rawValue] ?? 0 },
            set: { amounts[n.rawValue] = $0 == 0 ? nil : $0 }
        )
    }

    // MARK: - Load / save / delete

    private func load() {
        guard let food else {
            name = prefillName
            return
        }
        name = food.name
        brand = food.brand
        // The edited food is already persisted, so reading the to-many getter
        // here is safe (the iOS-17 hazard is only for un-inserted models).
        let portion = food.orderedPortions.first
        servingLabel = portion?.label ?? "1 serving"
        servingGrams = portion?.grams ?? 100
        amounts = food.per100g.perServing(servingGrams: servingGrams)
    }

    private func save() {
        let per100g = NutrientVector.fromPerServing(amounts, servingGrams: servingGrams)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = servingLabel.trimmingCharacters(in: .whitespaces)
        let portionLabel = trimmedLabel.isEmpty ? "1 serving" : trimmedLabel

        if let food {
            food.name = trimmedName
            food.brand = trimmedBrand
            food.per100g = per100g // setter also refreshes the kcalPer100g column
            if let portion = food.orderedPortions.first {
                portion.label = portionLabel
                portion.grams = servingGrams
            } else {
                attachPortion(label: portionLabel, grams: servingGrams, to: food)
            }
        } else {
            let new = FoodItem(name: trimmedName, brand: trimmedBrand, source: .custom,
                               per100g: per100g, barcode: prefillBarcode, isCustom: true)
            context.insert(new)
            attachPortion(label: portionLabel, grams: servingGrams, to: new)
        }
        try? context.save()
        dismiss()
    }

    /// Wire a portion from the to-one side only — appending to the food's
    /// to-many getter on a freshly built model crashes SwiftData on iOS 17.0
    /// (mirrors `FoodSeedManager.insertPortions`).
    private func attachPortion(label: String, grams: Double, to food: FoodItem) {
        let portion = FoodPortion(label: label, grams: grams)
        context.insert(portion)
        portion.food = food
    }

    private func deleteFood() {
        guard let food else { return }
        context.delete(food)
        try? context.save()
        dismiss()
    }
}
