//
//  WorkoutHistoryView.swift
//  tracklifts
//
//  The "Log" segment of the Train tab: your past sessions, and the entry
//  point for logging a new one. Embedded inside `TrainView`'s NavigationStack.
//

import SwiftUI
import SwiftData

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var editingSession: WorkoutSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Eyebrow(text: sessions.isEmpty ? "Your sessions" : "\(sessions.count) sessions")
                    Spacer()
                    Button {
                        editingSession = WorkoutSession.blank(in: context)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 42, height: 42)
                            .background(Grad.ember, in: .circle)
                            .shadow(color: Palette.ember.opacity(0.5), radius: 10, y: 4)
                    }
                    .accessibilityIdentifier("addWorkout")
                    .accessibilityLabel("Log Workout")
                }
                .padding(.top, 2)
                .appearLift(0)

                if sessions.isEmpty {
                    EmptyStateView(symbol: "square.and.pencil",
                                   title: "No Workouts Yet",
                                   message: "Hit + above to record your first session — or start from Today.")
                        .padding(.top, 20)
                        .appearLift(1)
                } else {
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
                                    editingSession = WorkoutSession.repeated(from: session, in: context)
                                } label: { Label("Repeat Workout", systemImage: "arrow.clockwise") }
                                Divider()
                                Button(role: .destructive) {
                                    context.delete(session)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .appearLift(min(index + 1, 8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editingSession) { session in
            NavigationStack {
                LogWorkoutView(session: session, isNew: true)
            }
        }
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

                if session.entryCount == 0 {
                    Text("Empty session")
                        .font(.sans(13))
                        .foregroundStyle(Palette.inkTertiary)
                } else {
                    Text(exerciseNames)
                        .font(.sans(13))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        miniStat("\(session.entryCount)", "lifts")
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
