//
//  SplitsListView.swift
//  tracklifts
//
//  The "Splits" segment of the Train tab: build and manage training routines.
//  Embedded inside `TrainView`'s NavigationStack.
//

import SwiftUI
import SwiftData

struct SplitsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Split.order), SortDescriptor(\Split.createdAt)])
    private var splits: [Split]

    @State private var newlyCreated: Split?
    @State private var reorderRequest: ReorderRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Eyebrow(text: "Your routines")
                    Spacer()
                    if splits.count > 1 {
                        Button(action: presentReorder) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.ember)
                                .frame(width: 42, height: 42)
                                .background(Palette.surface, in: .circle)
                                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                        }
                        .accessibilityIdentifier("reorderSplits")
                        .accessibilityLabel("Reorder Splits")
                    }
                    Button(action: createSplit) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 42, height: 42)
                            .background(Grad.ember, in: .circle)
                            .shadow(color: Palette.ember.opacity(0.5), radius: 10, y: 4)
                    }
                    .accessibilityIdentifier("addSplit")
                    .accessibilityLabel("Add Split")
                }
                .padding(.top, 2)
                .appearLift(0)

                if splits.isEmpty {
                    EmptyStateView(symbol: "rectangle.3.group",
                                   title: "No Splits Yet",
                                   message: "Create a routine like Push / Pull / Legs and fill each day with your lifts.")
                        .padding(.top, 20)
                        .appearLift(1)
                } else {
                    ForEach(Array(splits.enumerated()), id: \.element.persistentModelID) { index, split in
                        NavigationLink {
                            SplitEditorView(split: split)
                        } label: {
                            SplitRow(split: split)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                setFavorite(true, in: split)
                            } label: { Label("Favorite all lifts", systemImage: "star.fill") }
                            Button {
                                setFavorite(false, in: split)
                            } label: { Label("Remove from Favorites", systemImage: "star.slash") }
                            Divider()
                            Button(role: .destructive) {
                                context.delete(split)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .appearLift(min(index + 1, 6))
                    }
                }
            }
            .padding(20)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .navigationDestination(item: $newlyCreated) { split in
            SplitEditorView(split: split)
        }
        .sheet(item: $reorderRequest) { request in
            ReorderSheet(request: request)
        }
    }

    private func presentReorder() {
        reorderRequest = ReorderRequest(
            title: "Reorder Splits",
            items: splits.map { split in
                ReorderableItem(id: split.persistentModelID,
                                name: split.name.isEmpty ? "Split" : split.name,
                                symbol: "rectangle.3.group.fill",
                                color: Palette.ember)
            },
            onSave: { ids in
                withAnimation(.snappy) {
                    for (index, id) in ids.enumerated() {
                        splits.first { $0.persistentModelID == id }?.order = index
                    }
                }
            }
        )
    }

    private func createSplit() {
        // Insert first, then wire the to-one inverse — assigning the to-many
        // (`split.days = …`) on a freshly built model crashes SwiftData on iOS 17.
        let split = Split(name: "New Split", order: splits.count)
        context.insert(split)
        for (index, name) in ["Push", "Pull", "Legs"].enumerated() {
            let day = SplitDay(name: name, order: index)
            context.insert(day)
            day.split = split
        }
        newlyCreated = split
    }

    private func deleteSplits(_ offsets: IndexSet) {
        for index in offsets { context.delete(splits[index]) }
    }

    private func setFavorite(_ value: Bool, in split: Split) {
        for exercise in split.orderedDays.flatMap(\.exercises) { exercise.isFavorite = value }
    }
}

struct SplitRow: View {
    let split: Split

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(split.name)
                    .font(.display(28))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(split.orderedDays.count) days".uppercased())
                    .font(.sans(11, .bold)).tracking(1)
                    .foregroundStyle(Palette.inkSecondary)
            }
            FlowDays(days: split.orderedDays.map(\.name))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// Simple wrapping row of day chips.
private struct FlowDays: View {
    let days: [String]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(days.prefix(5).enumerated()), id: \.offset) { _, day in
                Text(day.uppercased())
                    .font(.sans(11, .bold)).tracking(0.5)
                    .foregroundStyle(Palette.ember)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Palette.ember.opacity(0.14), in: .capsule)
            }
        }
    }
}
