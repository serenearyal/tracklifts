//
//  ExerciseLibraryView.swift
//  tracklifts
//
//  The "Exercises" half of the Library tab: the searchable movement catalog,
//  grouped by muscle. Embedded inside `LibraryView`'s NavigationStack.
//

import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var selectedGroup: MuscleGroup?
    @State private var favoritesOnly = false
    @State private var showingAdd = false

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (!favoritesOnly || ex.isFavorite)
            && (selectedGroup == nil || ex.muscleGroup == selectedGroup)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Eyebrow(text: "\(exercises.count) movements")
                    Spacer()
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 42, height: 42)
                            .background(Grad.ember, in: .circle)
                            .shadow(color: Palette.ember.opacity(0.5), radius: 10, y: 4)
                    }
                }
                .padding(.top, 2)

                filterBar

                if sections.isEmpty {
                    Text(exercises.isEmpty ? "Loading library…" : "No matches")
                        .font(.sans(15)).foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }

                ForEach(sections, id: \.group) { section in
                    HStack(spacing: 8) {
                        Circle().fill(section.group.color).frame(width: 7, height: 7)
                        Text(section.group.displayName.uppercased())
                            .font(.sans(12, .bold)).tracking(1.5)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, 8)

                    ForEach(section.items) { exercise in
                        ZStack(alignment: .trailing) {
                            NavigationLink {
                                ExerciseDetailView(exercise: exercise)
                            } label: {
                                ExerciseRow(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    exercise.isFavorite.toggle()
                                } label: {
                                    Label(exercise.isFavorite ? "Unfavorite" : "Favorite",
                                          systemImage: exercise.isFavorite ? "star.slash" : "star.fill")
                                }
                                Button {
                                    exercise.isBodyweight.toggle()
                                } label: {
                                    Label(exercise.isBodyweight ? "Mark as Weighted" : "Mark as Bodyweight",
                                          systemImage: "figure.strengthtraining.functional")
                                }
                                if exercise.isCustom {
                                    Divider()
                                    Button(role: .destructive) {
                                        context.delete(exercise)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }

                            Button { exercise.isFavorite.toggle() } label: {
                                Image(systemName: exercise.isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(exercise.isFavorite ? Palette.gold : Palette.inkTertiary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .searchable(text: $searchText, prompt: "Search exercises")
        .sheet(isPresented: $showingAdd) { EditExerciseView() }
    }

    private var filterBar: some View {
        VStack(spacing: 12) {
            Picker("Filter", selection: $favoritesOnly) {
                Text("All").tag(false)
                Text("Favorites").tag(true)
            }
            .pickerStyle(.segmented)

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
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 14) {
            MuscleGlyph(group: exercise.muscleGroup, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.sans(16, .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(exercise.muscleGroup.displayName.uppercased())
                        .font(.sans(11, .semibold)).tracking(1)
                        .foregroundStyle(Palette.inkSecondary)
                    if exercise.isBodyweight {
                        Text("BODYWEIGHT")
                            .font(.sans(9, .bold)).tracking(0.8)
                            .foregroundStyle(Palette.up)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.up.opacity(0.14), in: .capsule)
                    }
                }
            }
            Spacer(minLength: 44) // room for the star overlay
        }
        .cardStyle()
    }
}
