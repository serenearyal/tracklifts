//
//  FoodSearchView.swift
//  tracklifts
//
//  The search-and-add engine (Phase 1): a pinned top search field, a Recent
//  shortcut, a visible favorite star per row, then pick serving + quantity +
//  meal and commit a snapshotted diary entry.
//

import SwiftUI
import SwiftData

/// One recipe-editor sheet at a time — new, or editing an existing recipe.
private enum RecipeSheet: Identifiable {
    case new
    case edit(Recipe)
    var id: String {
        switch self {
        case .new: "new"
        case .edit(let recipe): "edit-\(recipe.persistentModelID.hashValue)"
        }
    }
}

struct FoodSearchView: View {
    let meal: Meal
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var recentEntries: [DiaryEntry]
    @Query(sort: \SavedMeal.createdAt, order: .reverse) private var savedMeals: [SavedMeal]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var searchText = ""
    @State private var results: [FoodItem] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    // Barcode + Open Food Facts (Phase 3)
    @State private var scanning = false
    @State private var lookingUp = false
    @State private var pendingFood: FoodItem?            // programmatic push to LogFoodView
    @State private var onlineResults: [RemoteFood] = []
    @State private var onlineTask: Task<Void, Never>?
    @State private var newFood: NewFoodRequest?          // create sheet (typed name or scanned barcode)
    @State private var recipeSheet: RecipeSheet?         // recipe create/edit sheet

    /// A request to open the custom-food editor, carrying any prefill.
    struct NewFoodRequest: Identifiable {
        let id = UUID()
        var name = ""
        var barcode = ""
    }

    /// Filtering runs in SQLite (predicate + `fetchLimit`), not by loading the
    /// whole catalog into memory — at thousands of foods, scanning every row in
    /// Swift on each keystroke janks the main thread. Keystrokes are debounced;
    /// relevance ranking (name-prefix > word-prefix > anywhere, favorites first)
    /// is applied only to the capped result set, so "kiwi" still surfaces
    /// "Kiwifruit, raw" above "Beverages, … Kiwi".
    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        onlineTask?.cancel()
        onlineResults = []
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; searching = false; return }
        searching = true
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            search(term)
            searching = false
            // When the bundled catalog is thin on matches, ask Open Food Facts too.
            if results.count < 8 { scheduleOnlineSearch(term) }
        }
    }

    /// Branded online fallback — a gentler debounce so typing doesn't hammer OFF.
    private func scheduleOnlineSearch(_ term: String) {
        onlineTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await FoodProviders.shared.search(term)
            guard !Task.isCancelled else { return }
            let localBarcodes = Set(results.map(\.barcode).filter { !$0.isEmpty })
            onlineResults = found.filter { $0.barcode.isEmpty || !localBarcodes.contains($0.barcode) }
        }
    }

    @MainActor private func search(_ term: String) {
        results = FoodSearch.run(term, in: context) // shared ranking (see Data/FoodSearch.swift)
    }

    /// Most-recently-logged distinct foods — a quick re-log shortcut.
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
                        if searchText.isEmpty {
                            if !savedMeals.isEmpty {
                                sectionHeader("Saved Meals")
                                ForEach(savedMeals) { saved in savedMealRow(saved) }
                            }
                            if !recipes.isEmpty {
                                sectionHeader("Recipes")
                                ForEach(recipes) { recipe in recipeRow(recipe) }
                            }
                            if !recentFoods.isEmpty {
                                sectionHeader("Recent")
                                ForEach(recentFoods) { food in foodLink(food) }
                            }
                            if savedMeals.isEmpty && recipes.isEmpty && recentFoods.isEmpty {
                                Text("Search to add a food")
                                    .font(.sans(15)).foregroundStyle(Palette.inkSecondary)
                                    .frame(maxWidth: .infinity).padding(.top, 50)
                            }
                            createCustomRow
                            createRecipeRow
                        } else {
                            if results.isEmpty && !searching {
                                Text("No matches for “\(searchText)”")
                                    .font(.sans(15)).foregroundStyle(Palette.inkSecondary)
                                    .frame(maxWidth: .infinity).padding(.top, 50)
                            }
                            ForEach(results) { food in foodLink(food) }
                            if !onlineResults.isEmpty {
                                onlineHeader
                                ForEach(Array(onlineResults.enumerated()), id: \.offset) { _, r in
                                    remoteRow(r)
                                }
                            }
                            if !searching { createNamedRow }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
            .background(AppBackground())
            .navigationTitle("Add to \(meal.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
            }
            .onAppear { searchFocused = true }
            .onChange(of: searchText) { _, newValue in scheduleSearch(newValue) }
            .navigationDestination(item: $pendingFood) { food in
                LogFoodView(food: food, meal: meal, day: day) { dismiss() }
            }
            .fullScreenCover(isPresented: $scanning) {
                BarcodeScannerView(onScan: handleScan)
            }
            .sheet(item: $newFood, onDismiss: { scheduleSearch(searchText) }) { req in
                EditFoodView(food: nil, prefillName: req.name, prefillBarcode: req.barcode)
            }
            .sheet(item: $recipeSheet) { sheet in
                switch sheet {
                case .new: RecipeEditorView(recipe: nil)
                case .edit(let recipe): RecipeEditorView(recipe: recipe)
                }
            }
            .overlay { if lookingUp { lookupOverlay } }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
            TextField("Search foods", text: $searchText)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .font(.sans(16))
                .foregroundStyle(Palette.ink)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkTertiary)
                }
                .buttonStyle(.plain)
            }
            Button { scanning = true } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ember)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Palette.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.hairline, lineWidth: 1))
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text.uppercased())
                .font(.sans(12, .bold)).tracking(1.5)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
        }
        .padding(.top, 6)
    }

    /// Always-available entry to build a food that isn't in the catalog.
    private var createCustomRow: some View {
        Button { newFood = NewFoodRequest() } label: { createRowLabel("Create a custom food") }
            .buttonStyle(.plain).padding(.top, 6)
    }

    /// Offer to create the exact food the user typed — prefills its name.
    private var createNamedRow: some View {
        Button { newFood = NewFoodRequest(name: searchText) } label: { createRowLabel("Create “\(searchText)”") }
            .buttonStyle(.plain).padding(.top, 6)
    }

    private func createRowLabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.ember)
            Text(title).font(.sans(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer()
        }
        .cardStyle(padding: 14)
    }

    /// Full-row tap logs the food; the overlaid star toggles favorite without navigating.
    private func foodLink(_ food: FoodItem) -> some View {
        ZStack(alignment: .trailing) {
            NavigationLink {
                LogFoodView(food: food, meal: meal, day: day) { dismiss() }
            } label: {
                FoodRow(food: food)
            }
            .buttonStyle(.plain)

            Button { food.isFavorite.toggle() } label: {
                Image(systemName: food.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(food.isFavorite ? Palette.gold : Palette.inkTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
    }

    // MARK: - Saved meals

    /// Tapping logs every item into this sheet's meal slot + day, then dismisses.
    private func savedMealRow(_ saved: SavedMeal) -> some View {
        Button { logSavedMeal(saved) } label: {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ember)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(saved.name).font(.sans(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text("\(saved.orderedItems.count) items · \(Int(saved.totalKcal.rounded())) kcal")
                        .font(.sans(11)).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.ember)
            }
            .cardStyle(padding: 14)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                context.delete(saved)
                try? context.save()
            } label: { Label("Delete Meal", systemImage: "trash") }
        }
    }

    private func logSavedMeal(_ saved: SavedMeal) {
        for item in saved.orderedItems {
            guard let food = item.food else { continue } // skip items whose food was deleted
            context.insert(DiaryEntry(date: day, meal: meal, food: food,
                                      grams: item.grams, portionLabel: item.portionLabel))
        }
        try? context.save()
        dismiss()                                              // back to the diary — keep it instant
        HealthKitManager.shared.syncDay(day, context: context) // best-effort mirror, deferred internally
    }

    // MARK: - Recipes

    /// Tapping logs the recipe's derived per-serving food via the standard LogFoodView.
    private func recipeRow(_ recipe: Recipe) -> some View {
        Button {
            if let food = recipe.food { pendingFood = food }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ember).frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.name).font(.sans(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(recipeSubtitle(recipe)).font(.sans(11)).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkTertiary)
            }
            .cardStyle(padding: 14)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { recipeSheet = .edit(recipe) } label: { Label("Edit Recipe", systemImage: "pencil") }
            Button(role: .destructive) {
                context.delete(recipe); try? context.save()
            } label: { Label("Delete Recipe", systemImage: "trash") }
        }
    }

    private func recipeSubtitle(_ recipe: Recipe) -> String {
        let food = recipe.food
        let kcal = Int(((food?.kcalPer100g ?? 0) * (food?.defaultPortion.grams ?? 0) / 100).rounded())
        let n = recipe.orderedIngredients.count
        return "\(n) ingredient\(n == 1 ? "" : "s") · \(kcal) kcal/serving"
    }

    /// Always-available entry to build a recipe from existing foods.
    private var createRecipeRow: some View {
        Button { recipeSheet = .new } label: { createRowLabel("Create a recipe") }
            .buttonStyle(.plain).padding(.top, 6)
    }

    // MARK: - Barcode + Open Food Facts

    private var onlineHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.inkSecondary)
            Text("Online · Open Food Facts".uppercased())
                .font(.sans(12, .bold)).tracking(1.5).foregroundStyle(Palette.inkSecondary)
            Spacer()
        }
        .padding(.top, 10)
    }

    /// A network search hit (not yet cached) — tapping caches it, then logs it.
    private func remoteRow(_ r: RemoteFood) -> some View {
        Button { pendingFood = upsert(r) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.name).font(.sans(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    HStack(spacing: 5) {
                        if !r.brand.isEmpty {
                            Text(r.brand).font(.sans(11, .semibold)).foregroundStyle(Palette.inkSecondary)
                            Text("·").foregroundStyle(Palette.inkTertiary)
                        }
                        Text("\(Int(r.per100g.energy.rounded())) kcal / 100 g")
                            .font(.sans(11)).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
            }
            .cardStyle(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var lookupOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Palette.ember)
                Text("Looking up barcode…").font(.sans(14, .semibold)).foregroundStyle(Palette.ink)
            }
            .padding(24).background(Palette.surface, in: .rect(cornerRadius: 16))
        }
    }

    /// Scan result: prefer a cached/custom food with this barcode (offline + instant),
    /// else resolve via Open Food Facts, else offer to create it.
    private func handleScan(_ code: String) {
        let gtin = code.filter(\.isNumber)
        Task { @MainActor in
            if let local = localFood(barcode: gtin) { pendingFood = local; return }
            lookingUp = true
            defer { lookingUp = false }
            if let remote = await FoodProviders.shared.lookup(barcode: gtin) {
                pendingFood = upsert(remote)
            } else {
                newFood = NewFoodRequest(barcode: gtin)
            }
        }
    }

    private func localFood(barcode: String) -> FoodItem? {
        guard !barcode.isEmpty else { return nil }
        var d = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.barcode == barcode })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Cache a remote food as a `FoodItem`, reusing an existing row with the same
    /// barcode so re-scans never duplicate. Portion wired from the to-one side
    /// only (appending to the to-many on a fresh model crashes iOS 17).
    @discardableResult
    private func upsert(_ r: RemoteFood) -> FoodItem {
        if let existing = localFood(barcode: r.barcode) {
            existing.name = r.name
            existing.brand = r.brand
            existing.per100g = r.per100g
            try? context.save()
            return existing
        }
        let food = FoodItem(name: r.name, brand: r.brand, source: .openFoodFacts,
                            per100g: r.per100g, barcode: r.barcode)
        context.insert(food)
        let portion = FoodPortion(label: r.servingGrams > 0 ? "1 serving" : "100 g",
                                  grams: r.servingGrams > 0 ? r.servingGrams : 100)
        context.insert(portion)
        portion.food = food
        try? context.save()
        return food
    }
}

struct FoodRow: View {
    let food: FoodItem

    /// Energy from the promoted `kcalPer100g` column — avoids JSON-decoding the
    /// full nutrient blob just to show one number per row.
    private var servingKcal: Int {
        Int((food.kcalPer100g * food.defaultPortion.grams / 100).rounded())
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
            Spacer(minLength: 52) // room for the favorite-star overlay
        }
        .cardStyle(padding: 14)
    }
}

/// Shared energy + macro readout used by the log + edit sheets.
struct MacroPreview: View {
    let nutrients: NutrientVector

    var body: some View {
        HStack(spacing: 0) {
            cell(Int(nutrients.energy.rounded()).formatted(), "kcal", Palette.ember)
            divider
            cell("\(Int(nutrients.protein.rounded()))g", "Protein", Palette.up)
            divider
            cell("\(Int(nutrients.carbs.rounded()))g", "Carbs", Palette.gold)
            divider
            cell("\(Int(nutrients.fat.rounded()))g", "Fat", Color(hex: 0x4DABF7))
        }
        .padding(.vertical, 16)
        .cardStyle(padding: 8)
    }

    private func cell(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.display(26)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label.uppercased()).font(.sans(9, .semibold)).tracking(0.6).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 30)
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
    @State private var editing = false
    @State private var editingRecipe = false

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

                MacroPreview(nutrients: nutrients)

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

                NutritionFactsView(nutrients: nutrients)

                if food.source == .openFoodFacts {
                    Text("Data from Open Food Facts, licensed under ODbL.")
                        .font(.sans(11)).foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        // Meal picker + commit pinned to the bottom so the action stays in reach
        // without scrolling past the full nutrition-facts panel.
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Meal", systemImage: "calendar")
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                EmberButton(title: "Add to \(meal.label)", systemImage: "plus") { add() }
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(alignment: .top) {
                Palette.bgBottom
                    .overlay(alignment: .top) { Palette.hairline.frame(height: 1) }
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("Log Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if food.source == .recipe, food.recipe != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingRecipe = true } label: {
                        Image(systemName: "pencil").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Palette.ember)
                }
            } else if food.isCustom {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = true } label: {
                        Image(systemName: "pencil").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Palette.ember)
                }
            }
        }
        .sheet(isPresented: $editing) { EditFoodView(food: food) }
        .sheet(isPresented: $editingRecipe) {
            if let recipe = food.recipe { RecipeEditorView(recipe: recipe) }
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

    private func add() {
        let label = quantity == 1 ? portion.label : "\(quantity.formatted())× \(portion.label)"
        let entry = DiaryEntry(date: day, meal: meal, food: food, grams: grams, portionLabel: label)
        context.insert(entry)
        try? context.save()
        onLogged()                                             // dismiss first — keep "Add" instant
        HealthKitManager.shared.syncDay(day, context: context) // best-effort mirror, deferred internally
    }
}
