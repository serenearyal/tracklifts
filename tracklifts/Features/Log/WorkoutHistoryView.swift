//
//  WorkoutHistoryView.swift
//  tracklifts
//
//  The "Log" tab: your past sessions, and the entry point for logging a new one.
//

import SwiftUI
import SwiftData

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var editingSession: WorkoutSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(eyebrow: "Train. Track. Repeat.", title: "Training Log")
                        .padding(.top, 8)
                        .appearLift(0)

                    EmberButton(title: "Log Today's Workout", systemImage: "plus") {
                        startNewSession()
                    }
                    .appearLift(1)

                    if sessions.isEmpty {
                        EmptyStateView(symbol: "square.and.pencil",
                                       title: "No Workouts Yet",
                                       message: "Hit the button above to record your first session.")
                            .padding(.top, 20)
                            .appearLift(2)
                    } else {
                        Text("History")
                            .font(.sans(13, .bold)).tracking(1.5)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.top, 6)
                            .appearLift(2)

                        LazyVStack(spacing: 12) {
                            ForEach(Array(sessions.enumerated()), id: \.element.persistentModelID) { index, session in
                                NavigationLink {
                                    LogWorkoutView(session: session)
                                } label: {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        repeatWorkout(session)
                                    } label: { Label("Repeat Workout", systemImage: "arrow.clockwise") }
                                    Divider()
                                    Button(role: .destructive) {
                                        context.delete(session)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .appearLift(min(index + 3, 8))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationBarHidden(true)
            .sheet(item: $editingSession) { session in
                NavigationStack {
                    LogWorkoutView(session: session, isNew: true)
                }
            }
        }
    }

    private func startNewSession() {
        let session = WorkoutSession(date: .now)
        context.insert(session)
        editingSession = session
    }

    /// Clones a past session's exercises and sets into a fresh session for today.
    private func repeatWorkout(_ source: WorkoutSession) {
        let new = WorkoutSession(date: .now, title: source.title)
        context.insert(new)
        for entry in source.orderedEntries {
            guard let exercise = entry.exercise else { continue }
            let newEntry = LoggedExercise(exercise: exercise, order: entry.order)
            newEntry.session = new
            context.insert(newEntry)
            for set in entry.orderedSets {
                let newSet = LoggedSet(reps: set.reps, weight: set.weight, order: set.order)
                newSet.loggedExercise = newEntry
                context.insert(newSet)
            }
        }
        editingSession = new
    }
}

struct SessionRow: View {
    let session: WorkoutSession
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Grad.ember)
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.date.formatted(.dateTime.weekday(.wide)).uppercased())
                            .font(.sans(11, .bold))
                            .tracking(1.8)
                            .foregroundStyle(Palette.ember)
                        Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.display(28))
                            .foregroundStyle(Palette.ink)
                    }
                    Spacer()
                    if !session.title.isEmpty {
                        TagChip(text: session.title)
                    }
                }

                if session.entries.isEmpty {
                    Text("Empty session")
                        .font(.sans(13))
                        .foregroundStyle(Palette.inkTertiary)
                } else {
                    Text(exerciseNames)
                        .font(.sans(13))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        miniStat("\(session.entries.count)", "lifts")
                        miniStat("\(session.totalSets)", "sets")
                        miniStat(Int(session.totalVolume).formatted(), unit.label)
                    }
                }
            }
            .padding(.leading, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.30), radius: 14, x: 0, y: 8)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.sans(13, .bold)).foregroundStyle(Palette.ink)
            Text(label.uppercased()).font(.sans(10, .semibold)).tracking(0.5).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Palette.surfaceRaised, in: .capsule)
    }

    private var exerciseNames: String {
        session.orderedEntries.compactMap { $0.exercise?.name }.joined(separator: " · ")
    }
}
