//
//  EditExerciseView.swift
//  tracklifts
//
//  Create or edit a custom exercise.
//

import SwiftUI
import SwiftData

struct EditExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var exercise: Exercise?

    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var name = ""
    @State private var groupRaw: String = MuscleGroup.chest.rawValue
    @State private var notes = ""
    @State private var isBodyweight = false
    @State private var showingCustomAlert = false
    @State private var customName = ""

    private var isEditing: Bool { exercise != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Incline Cable Fly", text: $name).font(.sans(15))
                } header: { fieldLabel("Name") }
                .listRowBackground(Palette.surface)

                Section {
                    Picker("Muscle Group", selection: $groupRaw) {
                        ForEach(pickerTags) { tag in
                            Label(tag.displayName, systemImage: tag.symbol).tag(tag.raw)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .font(.sans(15))

                    Button {
                        customName = ""
                        showingCustomAlert = true
                    } label: {
                        Label("Add Custom Group", systemImage: "plus.circle")
                            .font(.sans(15, .semibold))
                            .foregroundStyle(Palette.ember)
                    }
                } header: { fieldLabel("Muscle Group") }
                .listRowBackground(Palette.surface)

                Section {
                    Toggle(isOn: $isBodyweight) {
                        Label("Bodyweight exercise", systemImage: "figure.strengthtraining.functional")
                            .font(.sans(15))
                            .foregroundStyle(Palette.ink)
                    }
                    .tint(Palette.ember)
                } header: { fieldLabel("Type") } footer: {
                    Text("Bodyweight lifts (pull-ups, sit-ups…) log reps and any added weight. Record your body weight in Settings to track their 1RM and volume.")
                        .font(.sans(12))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)

                Section {
                    TextField("Optional cues or setup", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.sans(15))
                } header: { fieldLabel("Notes") }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(isEditing ? "Edit Exercise" : "New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.sans(15))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave).font(.sans(15, .semibold))
                }
            }
            .onAppear(perform: load)
            .alert("New Muscle Group", isPresented: $showingCustomAlert) {
                TextField("e.g. Glutes", text: $customName)
                    .textInputAutocapitalization(.words)
                Button("Add") { addCustomGroup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Name a muscle group to organize this exercise under.")
            }
        }
    }

    /// Built-in groups + any custom groups already in the library + the current
    /// selection (so a just-typed custom name shows as selected), de-duplicated.
    private var pickerTags: [MuscleTag] {
        var tags = MuscleGroup.allCases.map { MuscleTag($0) }
        var seen = Set(tags.map(\.raw))
        let customs = (allExercises.map(\.muscleGroupRaw) + [groupRaw])
            .map { MuscleTag(raw: $0) }
            .filter(\.isCustom)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        for tag in customs where seen.insert(tag.raw).inserted {
            tags.append(tag)
        }
        return tags
    }

    private func addCustomGroup() {
        guard let canonical = MuscleTag.canonicalRaw(forInput: customName) else { return }
        // Reuse an existing built-in/custom group that matches case-insensitively.
        let existing = pickerTags.first { $0.raw.lowercased() == canonical.lowercased() }
        groupRaw = existing?.raw ?? canonical
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(12, .bold)).tracking(1.2)
            .foregroundStyle(Palette.inkSecondary)
    }

    private func load() {
        guard let exercise else { return }
        name = exercise.name
        groupRaw = exercise.muscleGroupRaw
        notes = exercise.notes
        isBodyweight = exercise.isBodyweight
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let exercise {
            exercise.name = trimmed
            exercise.muscleGroupRaw = groupRaw
            exercise.notes = notes
            exercise.isBodyweight = isBodyweight
        } else {
            let new = Exercise(name: trimmed, muscleGroup: .chest, isCustom: true,
                               isBodyweight: isBodyweight, notes: notes)
            new.muscleGroupRaw = groupRaw
            context.insert(new)
        }
        dismiss()
    }
}
