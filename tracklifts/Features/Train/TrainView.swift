//
//  TrainView.swift
//  tracklifts
//
//  The "Train" tab unifies everything training: the workout log, your splits,
//  and the movement catalog behind a single FORGE-styled segmented switcher.
//  Each segment keeps its own scroll, search, and actions; this view owns the
//  shared NavigationStack + atmosphere.
//

import SwiftUI
import SwiftData

enum TrainMode: String, CaseIterable, Identifiable {
    case log = "Log"
    case splits = "Splits"
    case exercises = "Exercises"
    var id: Self { self }
}

struct TrainView: View {
    @State private var mode: TrainMode = .log

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TrainModeSwitcher(mode: $mode)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                switch mode {
                case .log: WorkoutHistoryView()
                case .splits: SplitsListView()
                case .exercises: ExerciseLibraryView()
                }
            }
            .background(AppBackground())
            .navigationBarHidden(true)
        }
    }
}

/// Three-way ember pill switcher with a sliding highlight — the "title" of the
/// Train tab and the control that swaps its content.
struct TrainModeSwitcher: View {
    @Binding var mode: TrainMode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TrainMode.allCases) { item in
                segment(item)
            }
        }
        .padding(4)
        .background(Palette.surface, in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private func segment(_ item: TrainMode) -> some View {
        let selected = (item == mode)
        return Button {
            withAnimation(.snappy(duration: 0.28)) { mode = item }
        } label: {
            Text(item.rawValue.uppercased())
                .font(.sans(13, .bold))
                .tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color.black : Palette.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background { highlight(selected) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trainSegment.\(item.rawValue.lowercased())")
    }

    @ViewBuilder
    private func highlight(_ selected: Bool) -> some View {
        if selected {
            Capsule()
                .fill(Grad.ember)
                .matchedGeometryEffect(id: "trainSeg", in: ns)
                .shadow(color: Palette.ember.opacity(0.40), radius: 8, y: 3)
        }
    }
}

#Preview {
    TrainView()
        .modelContainer(for: [
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
            WorkoutSession.self, LoggedExercise.self, LoggedSet.self,
        ], inMemory: true)
        .preferredColorScheme(.dark)
}
