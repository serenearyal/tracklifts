//
//  Reordering.swift
//  tracklifts
//
//  A small, reusable drag-to-reorder sheet in the FORGE language. Used to
//  reorder exercises in a workout, days in a split, and exercises within a day.
//  The list is permanently in edit mode, so reorder handles are always visible
//  and a single tap-and-drag does the job.
//

import SwiftUI
import SwiftData

/// One draggable line: a stable id plus how to draw it.
struct ReorderableItem: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let symbol: String
    let color: Color
}

/// A pending reorder, used to drive a single `.sheet(item:)`. The owner builds
/// the rows and supplies a closure that writes the new order back to its models.
struct ReorderRequest: Identifiable {
    let id = UUID()
    let title: String
    let items: [ReorderableItem]
    /// Receives the item ids in their new order.
    let onSave: ([PersistentIdentifier]) -> Void
}

struct ReorderSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: ([PersistentIdentifier]) -> Void
    @State private var items: [ReorderableItem]

    init(request: ReorderRequest) {
        self.title = request.title
        self.onSave = request.onSave
        self._items = State(initialValue: request.items)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(item.color)
                                .frame(width: 34, height: 34)
                                .background(item.color.opacity(0.16), in: .rect(cornerRadius: 10))
                            Text(item.name)
                                .font(.sans(15, .semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(Palette.surface)
                    }
                    .onMove { from, to in
                        items.move(fromOffsets: from, toOffset: to)
                    }
                } footer: {
                    Text("Drag the handles to set the order.")
                        .font(.sans(12))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .environment(\.editMode, .constant(.active))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.sans(15))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(items.map(\.id))
                        dismiss()
                    }
                    .font(.sans(15, .semibold))
                }
            }
        }
    }
}
