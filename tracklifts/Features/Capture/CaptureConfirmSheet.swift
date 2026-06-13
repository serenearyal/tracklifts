//
//  CaptureConfirmSheet.swift
//  tracklifts
//
//  Phase 4 — step 2 of capture. Review the matched items from a typed/spoken/
//  photographed meal, fix any food match or amount, pick the meal, and commit one
//  `DiaryEntry` per matched row through the same path as every other log. Pushed
//  from `CaptureView`; the commit dismisses the whole capture flow via `onComplete`.
//

import SwiftUI
import SwiftData

struct CaptureConfirmList: View {
    let day: Date
    let onComplete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var matches: [CaptureMatch]
    @State private var meal: Meal = .defaultForNow
    @State private var editingRow: CaptureMatch?

    init(matches: [CaptureMatch], day: Date, onComplete: @escaping () -> Void) {
        self.day = day
        self.onComplete = onComplete
        _matches = State(initialValue: matches)
    }

    private var matchedCount: Int { matches.lazy.filter { $0.food != nil }.count }

    /// Combined nutrients of the rows that resolved to a food — the preview header.
    private var totals: NutrientVector {
        matches.reduce(NutrientVector()) { acc, m in
            acc + (m.food?.nutrients(forGrams: m.grams) ?? NutrientVector())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MacroPreview(nutrients: totals)
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Items", systemImage: "checklist")
                    VStack(spacing: 8) {
                        if matches.isEmpty {
                            Text("Nothing to add.")
                                .font(.sans(13)).foregroundStyle(Palette.inkTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                        ForEach($matches) { $m in row($m) }
                    }
                    .cardStyle(padding: 14)
                }
                Text("Tap a food name to change the match. Amounts are estimates — tweak the grams.")
                    .font(.sans(12)).foregroundStyle(Palette.inkTertiary)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneBar()
        .safeAreaInset(edge: .bottom) { footer }
        .sheet(item: $editingRow) { row in
            CaptureFoodPicker(query: row.parsed.name) { food in changeFood(of: row.id, to: food) }
        }
    }

    // MARK: Row

    private func row(_ m: Binding<CaptureMatch>) -> some View {
        let match = m.wrappedValue
        let kcal = Int(((match.food?.kcalPer100g ?? 0) * match.grams / 100).rounded())
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Button { editingRow = match } label: {
                        HStack(spacing: 5) {
                            Text(match.food?.name ?? match.parsed.name)
                                .font(.sans(14, .semibold))
                                .foregroundStyle(match.food == nil ? Palette.down : Palette.ink)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.inkTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if match.isEstimated { estimatedPill }
                }
                Text(match.food == nil ? "No match — tap to choose" : "\(kcal) kcal · \(match.portionLabel)")
                    .font(.sans(11)).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            TextField("0", value: m.grams, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.sans(15, .bold)).foregroundStyle(Palette.ink)
                .frame(width: 56)
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 8))
            Text("g").font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
            Button { matches.removeAll { $0.id == match.id } } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(Palette.down.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
    }

    /// Marks a row whose nutrition the photo model estimated (no catalog match) —
    /// trust-but-verify; the grams + macros are editable like any other row.
    private var estimatedPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles").font(.system(size: 8, weight: .bold))
            Text("ESTIMATED").font(.sans(9, .bold)).tracking(0.5)
        }
        .foregroundStyle(Palette.ember)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Palette.ember.opacity(0.14), in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.ember.opacity(0.3), lineWidth: 1))
        .fixedSize()
    }

    // MARK: Footer (pinned so the action stays in reach — see LogFoodView)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Meal", selection: $meal) {
                ForEach(Meal.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            EmberButton(title: addTitle, systemImage: "plus") { commit() }
                .padding(.top, 4)
                .disabled(matchedCount == 0)
                .opacity(matchedCount == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(alignment: .top) {
            Palette.bgBottom
                .overlay(alignment: .top) { Palette.hairline.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var addTitle: String {
        matchedCount <= 1 ? "Add to \(meal.label)" : "Add \(matchedCount) to \(meal.label)"
    }

    // MARK: Actions

    private func changeFood(of id: CaptureMatch.ID, to food: FoodItem) {
        guard let idx = matches.firstIndex(where: { $0.id == id }) else { return }
        let resolved = CaptureMatcher.resolveGrams(matches[idx].parsed, food: food)
        matches[idx].food = food
        matches[idx].grams = resolved.grams
        matches[idx].portionLabel = resolved.label
        matches[idx].isEstimated = false   // now a real catalog food — don't re-insert on commit
    }

    private func commit() {
        for m in matches where m.food != nil {
            let food = m.food!
            // An estimated food is built un-inserted in CaptureMatcher; promote it to
            // a real custom food here (so it's reusable/searchable) before logging.
            if m.isEstimated { persistEstimated(food, grams: m.parsed.gramsHint) }
            let entry = DiaryEntry(date: day, meal: meal, food: food, grams: m.grams, portionLabel: m.portionLabel)
            context.insert(entry)
        }
        try? context.save()
        onComplete()                                           // dismiss first — keep it instant
        HealthKitManager.shared.syncDay(day, context: context) // best-effort mirror, deferred internally
    }

    /// Insert a just-estimated custom food and wire its serving portion. The portion
    /// is attached from the to-one side after insert (the iOS-17-safe order — see
    /// `EditFoodView.attachPortion`), never by appending to the food's to-many.
    private func persistEstimated(_ food: FoodItem, grams: Double?) {
        context.insert(food)
        if let grams, grams > 0 {
            let portion = FoodPortion(label: "1 serving", grams: grams)
            context.insert(portion)
            portion.food = food
        }
    }
}

// MARK: - Food picker

/// A food search prefilled with the parsed name so candidate matches show at once.
/// Reuses the shared `FoodSearch` ranking + `FoodRow`; tapping returns + dismisses.
struct CaptureFoodPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let query: String
    let onPick: (FoodItem) -> Void

    @State private var searchText: String
    @State private var results: [FoodItem] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    init(query: String, onPick: @escaping (FoodItem) -> Void) {
        self.query = query
        self.onPick = onPick
        _searchText = State(initialValue: query)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(results) { food in
                            Button { onPick(food); dismiss() } label: { FoodRow(food: food) }
                                .buttonStyle(.plain)
                        }
                        if results.isEmpty {
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
            .navigationTitle("Choose Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
            }
            .onAppear { focused = true; runSearch(searchText) }
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

    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; return }
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            runSearch(term)
        }
    }

    private func runSearch(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        results = term.isEmpty ? [] : FoodSearch.run(term, in: context)
    }
}
