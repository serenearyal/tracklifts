//
//  SplitEditorView.swift
//  tracklifts
//
//  Edit a split: rename it, manage days, assign exercises, and track its
//  progress. Bulk-favorite a whole split or a single day in one tap.
//

import SwiftUI
import SwiftData

struct SplitEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var split: Split

    @State private var pickingDay: SplitDay?
    @State private var reorderRequest: ReorderRequest?

    /// Every distinct exercise across the split.
    private var allExercises: [Exercise] {
        var seen = Set<PersistentIdentifier>()
        return split.orderedDays.flatMap(\.exercises).filter { seen.insert($0.persistentModelID).inserted }
    }

    private var allFavorited: Bool {
        !allExercises.isEmpty && allExercises.allSatisfy(\.isFavorite)
    }

    var body: some View {
        List {
            Section {
                TextField("Split name", text: $split.name)
                    .font(.display(26))
                    .foregroundStyle(Palette.ink)

                Button {
                    setFavorite(!allFavorited, for: allExercises)
                } label: {
                    Label(allFavorited ? "Remove split from Favorites" : "Favorite all lifts in split",
                          systemImage: allFavorited ? "star.slash.fill" : "star.fill")
                        .font(.sans(15, .semibold))
                        .foregroundStyle(allFavorited ? Palette.inkSecondary : Palette.gold)
                }
                .disabled(allExercises.isEmpty)
            } header: { label("Split Name") }
            .listRowBackground(Palette.surface)

            ForEach(split.orderedDays) { day in
                daySection(day)
            }
            .onDelete(perform: deleteDays)

            Section {
                Button(action: addDay) {
                    Label("Add Day", systemImage: "plus.circle.fill")
                        .font(.sans(15, .semibold))
                        .foregroundStyle(Palette.ember)
                }
            }
            .listRowBackground(Palette.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(split.name.isEmpty ? "Split" : split.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if split.dayCount > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { presentReorderDays() } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("reorderDays")
                    .accessibilityLabel("Reorder Days")
                }
            }
        }
        .sheet(item: $pickingDay) { day in
            ExercisePickerView { picked in addExercises(picked, to: day) }
        }
        .sheet(item: $reorderRequest) { request in
            ReorderSheet(request: request)
        }
    }

    // MARK: - Reordering

    private func presentReorderDays() {
        let days = split.orderedDays
        reorderRequest = ReorderRequest(
            title: "Reorder Days",
            items: days.enumerated().map { index, day in
                ReorderableItem(id: day.persistentModelID,
                                name: day.name.isEmpty ? "Day \(index + 1)" : day.name,
                                symbol: "calendar",
                                color: Palette.ember)
            },
            onSave: { ids in
                withAnimation(.snappy) {
                    for (index, id) in ids.enumerated() {
                        days.first { $0.persistentModelID == id }?.order = index
                    }
                }
            }
        )
    }

    private func presentReorderExercises(in day: SplitDay) {
        let items = day.orderedItems
        reorderRequest = ReorderRequest(
            title: "Reorder Exercises",
            items: items.compactMap { item in
                guard let exercise = item.exercise else { return nil }
                return ReorderableItem(id: item.persistentModelID,
                                       name: exercise.name,
                                       symbol: exercise.tag.symbol,
                                       color: exercise.tag.color)
            },
            onSave: { ids in
                withAnimation(.snappy) {
                    for (index, id) in ids.enumerated() {
                        items.first { $0.persistentModelID == id }?.order = index
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func daySection(_ day: SplitDay) -> some View {
        Section {
            DayNameField(day: day)

            ForEach(day.orderedItems) { item in
                if let exercise = item.exercise {
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                    } label: {
                        HStack(spacing: 12) {
                            MuscleGlyph(tag: exercise.tag, size: 34)
                            Text(exercise.name)
                                .font(.sans(15))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if exercise.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.gold)
                            }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            exercise.isFavorite.toggle()
                        } label: {
                            Label(exercise.isFavorite ? "Unfavorite" : "Favorite",
                                  systemImage: exercise.isFavorite ? "star.slash" : "star.fill")
                        }
                        .tint(Palette.gold)
                    }
                }
            }
            .onDelete { deleteItems($0, in: day) }

            Button { pickingDay = day } label: {
                Label("Add Exercise", systemImage: "plus")
                    .font(.sans(14, .semibold))
                    .foregroundStyle(Palette.ember)
            }
        } header: {
            HStack(spacing: 14) {
                label(day.name.isEmpty ? "Day" : day.name)
                Spacer()
                if day.exercises.count > 1 {
                    Button {
                        presentReorderExercises(in: day)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.ember)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reorder exercises")
                }
                if !day.exercises.isEmpty {
                    Menu {
                        Button {
                            setFavorite(true, for: day.exercises)
                        } label: { Label("Favorite all in day", systemImage: "star.fill") }
                        Button {
                            setFavorite(false, for: day.exercises)
                        } label: { Label("Remove all from Favorites", systemImage: "star.slash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listRowBackground(Palette.surface)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(12, .bold)).tracking(1.2)
            .foregroundStyle(Palette.inkSecondary)
    }

    // MARK: - Mutations

    private func setFavorite(_ value: Bool, for exercises: [Exercise]) {
        for exercise in exercises { exercise.isFavorite = value }
    }

    private func addDay() {
        let day = SplitDay(name: "Day \(split.dayCount + 1)", order: split.dayCount)
        day.split = split
        context.insert(day)
    }

    private func deleteDays(_ offsets: IndexSet) {
        let ordered = split.orderedDays
        for index in offsets { context.delete(ordered[index]) }
    }

    private func addExercises(_ exercises: [Exercise], to day: SplitDay) {
        var order = day.itemCount
        for exercise in exercises {
            if (day.items ?? []).contains(where: { $0.exercise?.persistentModelID == exercise.persistentModelID }) {
                continue
            }
            let item = SplitItem(exercise: exercise, order: order)
            item.day = day
            context.insert(item)
            order += 1
        }
    }

    private func deleteItems(_ offsets: IndexSet, in day: SplitDay) {
        let ordered = day.orderedItems
        for index in offsets { context.delete(ordered[index]) }
    }
}

private struct DayNameField: View {
    @Bindable var day: SplitDay
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(Palette.ember)
            TextField("Day name", text: $day.name)
                .font(.sans(15, .semibold))
                .foregroundStyle(Palette.ink)
        }
    }
}
