//
//  ExercisePickerView.swift
//  tracklifts
//
//  Multi-select picker for adding exercises to a workout or split day.
//

import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let onAdd: ([Exercise]) -> Void

    @State private var searchText = ""
    @State private var selectedGroup: MuscleGroup?
    @State private var selectedIDs: Set<PersistentIdentifier> = []

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (selectedGroup == nil || ex.muscleGroup == selectedGroup)
            && (searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var sections: [(group: MuscleGroup, items: [Exercise])] {
        MuscleGroup.allCases.compactMap { group in
            let items = filtered.filter { $0.muscleGroup == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button { selectedGroup = nil } label: {
                                TagChip(text: "All", color: Palette.inkSecondary, filled: selectedGroup == nil)
                            }.buttonStyle(.plain)
                            ForEach(MuscleGroup.allCases) { group in
                                Button {
                                    selectedGroup = (selectedGroup == group) ? nil : group
                                } label: {
                                    TagChip(text: group.displayName, color: group.color, filled: selectedGroup == group)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(sections, id: \.group) { section in
                    Section {
                        ForEach(section.items) { exercise in
                            Button { toggle(exercise) } label: {
                                HStack(spacing: 12) {
                                    MuscleGlyph(group: exercise.muscleGroup, size: 34)
                                    Text(exercise.name)
                                        .font(.sans(15))
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                    Image(systemName: selectedIDs.contains(exercise.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(selectedIDs.contains(exercise.persistentModelID) ? Palette.ember : Palette.inkTertiary)
                                }
                            }
                            .listRowBackground(Palette.surface)
                        }
                    } header: {
                        Text(section.group.displayName.uppercased())
                            .font(.sans(12, .bold)).tracking(1.2)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.sans(15))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add\(selectedIDs.isEmpty ? "" : " (\(selectedIDs.count))")") {
                        onAdd(exercises.filter { selectedIDs.contains($0.persistentModelID) })
                        dismiss()
                    }
                    .font(.sans(15, .semibold))
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func toggle(_ exercise: Exercise) {
        let id = exercise.persistentModelID
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }
}

/// Lets the user pick a day from one of their splits to bulk-add its exercises.
struct SplitDayPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Split.order), SortDescriptor(\Split.createdAt)])
    private var splits: [Split]

    let onPick: (SplitDay) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if splits.isEmpty {
                    EmptyStateView(symbol: "rectangle.3.group",
                                   title: "No Splits",
                                   message: "Create a split in the Splits tab first.")
                } else {
                    List {
                        ForEach(splits) { split in
                            Section {
                                ForEach(split.orderedDays) { day in
                                    Button {
                                        onPick(day); dismiss()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(day.name).font(.sans(15, .semibold)).foregroundStyle(Palette.ink)
                                                Text(day.exercises.map(\.name).joined(separator: ", "))
                                                    .font(.sans(12))
                                                    .foregroundStyle(Palette.inkSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(Palette.inkTertiary)
                                        }
                                    }
                                    .listRowBackground(Palette.surface)
                                }
                            } header: {
                                Text(split.name.uppercased())
                                    .font(.sans(12, .bold)).tracking(1.2)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(AppBackground())
                }
            }
            .navigationTitle("Add from Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.sans(15))
                }
            }
        }
    }
}
