//
//  SaveMealSheet.swift
//  tracklifts
//
//  Turns a diary meal section you've already logged into a reusable SavedMeal —
//  the zero-typing path to "I eat the same breakfast every day." Snapshots each
//  entry's food + grams + portion; the saved meal then re-logs them in one tap.
//

import SwiftUI
import SwiftData

struct SaveMealSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let defaultName: String
    let entries: [DiaryEntry]

    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(defaultName: String, entries: [DiaryEntry]) {
        self.defaultName = defaultName
        self.entries = entries
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Save these \(entries.count) item\(entries.count == 1 ? "" : "s") as a meal you can add again in one tap.")
                        .font(.sans(13)).foregroundStyle(Palette.inkSecondary)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Name", systemImage: "bookmark.fill")
                        TextField("Meal name", text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .font(.sans(16, .semibold)).foregroundStyle(Palette.ink)
                            .padding(.vertical, 12).padding(.horizontal, 14)
                            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Items", systemImage: "list.bullet")
                        ForEach(entries) { entry in
                            HStack {
                                Text(entry.foodName)
                                    .font(.sans(14, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                                Spacer()
                                Text(entry.servingText)
                                    .font(.sans(12)).foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    }
                    .cardStyle(padding: 14)

                    EmberButton(title: "Save Meal", systemImage: "checkmark") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || entries.isEmpty)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle("Save as Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !entries.isEmpty else { return }
        let saved = SavedMeal(name: trimmed)
        context.insert(saved)
        for (index, entry) in entries.enumerated() {
            guard let food = entry.food else { continue } // only re-loggable items
            let item = SavedMealItem(food: food, grams: entry.grams,
                                     portionLabel: entry.portionLabel, order: index)
            context.insert(item)
            item.meal = saved // to-one side only, after insert (iOS 17 rule)
        }
        try? context.save()
        dismiss()
    }
}
