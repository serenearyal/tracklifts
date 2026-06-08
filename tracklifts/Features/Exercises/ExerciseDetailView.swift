//
//  ExerciseDetailView.swift
//  tracklifts
//

import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    @AppStorage(BodyMetrics.key) private var bodyWeight: Double = 0

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var showingEdit = false

    private var history: [(session: WorkoutSession, entry: LoggedExercise)] {
        sessions.compactMap { session in
            guard let entry = session.entries.first(where: {
                $0.exercise?.persistentModelID == exercise.persistentModelID
            }) else { return nil }
            return (session, entry)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero.appearLift(0)

                if !exercise.notes.isEmpty {
                    Text(exercise.notes)
                        .font(.sans(14))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                        .appearLift(1)
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Progression", systemImage: "chart.xyaxis.line")
                    ExerciseProgressView(exercise: exercise)
                }
                .cardStyle(padding: 18)
                .appearLift(2)

                historySection.appearLift(3)
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { exercise.isFavorite.toggle() } label: {
                    Image(systemName: exercise.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(exercise.isFavorite ? Palette.gold : Palette.inkSecondary)
                }
            }
            if exercise.isCustom {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showingEdit = true }.font(.sans(15, .semibold))
                }
            }
        }
        .sheet(isPresented: $showingEdit) { EditExerciseView(exercise: exercise) }
    }

    private var hero: some View {
        let headline = bestHeadline
        return HStack(spacing: 16) {
            MuscleGlyph(group: exercise.muscleGroup, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TagChip(text: exercise.muscleGroup.displayName, color: exercise.muscleGroup.color)
                    BodyweightToggleChip(isOn: exercise.isBodyweight, label: "BODYWEIGHT") {
                        exercise.isBodyweight.toggle()
                    }
                }
                if let headline {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(headline.label.uppercased())
                            .font(.sans(10, .semibold)).tracking(1.2)
                            .foregroundStyle(Palette.inkSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(headline.value)
                                .font(.display(40))
                                .foregroundStyle(Palette.ink)
                            Text(headline.unit)
                                .font(.sans(13, .semibold))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                } else {
                    Text("Not logged yet")
                        .font(.sans(14))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 18)
    }

    /// The hero stat: best est. 1RM for loaded lifts, best reps for pure
    /// bodyweight (no recorded body weight). Nil when never logged.
    private var bestHeadline: (label: String, value: String, unit: String)? {
        if exercise.tracksExternalLoad {
            let pb = ProgressCalculator.personalBestOneRepMax(for: exercise, in: sessions)
            guard pb > 0 else { return nil }
            return ("Best est. 1RM", pb.trimmedWeight, unit.label)
        } else {
            let best = ProgressCalculator.series(for: exercise, metric: .bestReps, in: sessions)
                .map(\.value).max() ?? 0
            guard best > 0 else { return nil }
            return ("Best set", String(Int(best)), "reps")
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "History", systemImage: "clock.arrow.circlepath")
            if history.isEmpty {
                Text("No sessions logged for this exercise yet.")
                    .font(.sans(14))
                    .foregroundStyle(Palette.inkSecondary)
                    .cardStyle()
            } else {
                ForEach(history.prefix(12), id: \.session.persistentModelID) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.session.date.formatted(.dateTime.month().day().year()))
                                .font(.sans(14, .bold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(item.entry.sets.count) sets")
                                .font(.sans(11, .semibold))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Text(setSummary(item.entry))
                            .font(.sans(13))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(padding: 14)
                }
            }
        }
    }

    private func setSummary(_ entry: LoggedExercise) -> String {
        entry.orderedSets
            .map { $0.summary(unit: unit) }
            .joined(separator: "   ")
    }
}
