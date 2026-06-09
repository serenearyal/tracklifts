//
//  LibraryView.swift
//  tracklifts
//
//  The "Library" tab unifies the movement catalog and your training splits
//  behind a single FORGE-styled segmented switcher, so planning lives in one
//  place. Each half keeps its own scroll, search, and actions; this view owns
//  the shared NavigationStack + atmosphere.
//

import SwiftUI
import SwiftData

enum LibraryMode: String, CaseIterable, Identifiable {
    case exercises = "Exercises"
    case splits = "Splits"
    var id: Self { self }
}

struct LibraryView: View {
    @State private var mode: LibraryMode = .exercises

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LibraryModeSwitcher(mode: $mode)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                switch mode {
                case .exercises: ExerciseLibraryView()
                case .splits: SplitsListView()
                }
            }
            .background(AppBackground())
            .navigationBarHidden(true)
        }
    }
}

/// Two-way ember pill switcher with a sliding highlight — the "title" of the
/// Library tab and the control that swaps its content.
struct LibraryModeSwitcher: View {
    @Binding var mode: LibraryMode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LibraryMode.allCases) { item in
                segment(item)
            }
        }
        .padding(4)
        .background(Palette.surface, in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private func segment(_ item: LibraryMode) -> some View {
        let selected = (item == mode)
        return Button {
            withAnimation(.snappy(duration: 0.28)) { mode = item }
        } label: {
            Text(item.rawValue.uppercased())
                .font(.sans(13, .bold))
                .tracking(1.5)
                .foregroundStyle(selected ? Color.black : Palette.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background { highlight(selected) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("librarySegment.\(item.rawValue.lowercased())")
    }

    @ViewBuilder
    private func highlight(_ selected: Bool) -> some View {
        if selected {
            Capsule()
                .fill(Grad.ember)
                .matchedGeometryEffect(id: "librarySeg", in: ns)
                .shadow(color: Palette.ember.opacity(0.40), radius: 8, y: 3)
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [
            Exercise.self, Split.self, SplitDay.self, SplitItem.self,
        ], inMemory: true)
}
