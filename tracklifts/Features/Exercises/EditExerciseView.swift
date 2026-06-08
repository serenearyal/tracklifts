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

    @State private var name = ""
    @State private var group: MuscleGroup = .chest
    @State private var notes = ""
    @State private var isBodyweight = false

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
                    Picker("Muscle Group", selection: $group) {
                        ForEach(MuscleGroup.allCases) { g in
                            Label(g.displayName, systemImage: g.symbol).tag(g)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .font(.sans(15))
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
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(12, .bold)).tracking(1.2)
            .foregroundStyle(Palette.inkSecondary)
    }

    private func load() {
        guard let exercise else { return }
        name = exercise.name
        group = exercise.muscleGroup
        notes = exercise.notes
        isBodyweight = exercise.isBodyweight
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let exercise {
            exercise.name = trimmed
            exercise.muscleGroup = group
            exercise.notes = notes
            exercise.isBodyweight = isBodyweight
        } else {
            context.insert(Exercise(name: trimmed, muscleGroup: group, isCustom: true,
                                    isBodyweight: isBodyweight, notes: notes))
        }
        dismiss()
    }
}
