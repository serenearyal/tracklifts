//
//  ExerciseLibraryView.swift
//  tracklifts
//
//  The "Exercises" segment of the Train tab: the searchable movement catalog,
//  grouped by muscle. Embedded inside `TrainView`'s NavigationStack.
//

import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var selectedRaw: String?
    @State private var favoritesOnly = false
    @State private var showingAdd = false

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (!favoritesOnly || ex.isFavorite)
            && (selectedRaw == nil || ex.muscleGroupRaw == selectedRaw)
            && (searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var sections: [(tag: MuscleTag, items: [Exercise])] {
        filtered.muscleTagsPresent.map { tag in
            (tag, filtered.filter { $0.muscleGroupRaw == tag.raw })
        }
    }

    /// Built-in groups (always shown) plus any custom groups in the library.
    private var filterTags: [MuscleTag] {
        MuscleGroup.allCases.map { MuscleTag($0) } + exercises.muscleTagsPresent.filter(\.isCustom)
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

                ForEach(sections, id: \.tag) { section in
                    HStack(spacing: 8) {
                        Circle().fill(section.tag.color).frame(width: 7, height: 7)
                        Text(section.tag.displayName.uppercased())
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
                    Button { selectedRaw = nil } label: {
                        TagChip(text: "All", color: Palette.inkSecondary, filled: selectedRaw == nil)
                    }.buttonStyle(.plain)
                    ForEach(filterTags) { tag in
                        Button {
                            selectedRaw = (selectedRaw == tag.raw) ? nil : tag.raw
                        } label: {
                            TagChip(text: tag.displayName, color: tag.color, filled: selectedRaw == tag.raw)
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
            MuscleGlyph(tag: exercise.tag, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.sans(16, .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(exercise.tag.displayName.uppercased())
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
