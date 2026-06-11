//
//  LogWorkoutView.swift
//  tracklifts
//
//  Manually log a training session: add exercises, then record sets
//  (reps × weight). Shows last session's numbers so you can beat them.
//

import SwiftUI
import SwiftData

struct LogWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    // Observed so set summaries / deltas refresh when body weight changes.
    @AppStorage(BodyMetrics.key) private var bodyWeight: Double = 0

    @Bindable var session: WorkoutSession
    var isNew: Bool = false

    @Query(sort: \WorkoutSession.date, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var showingPicker = false
    @State private var showingSplitPicker = false
    @State private var reorderRequest: ReorderRequest?
    @FocusState private var focusedSet: SetFieldFocus?

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: focusedSet) { _, _ in
                    // Defer a runloop so the focus-driven bottom inset (below) is applied
                    // first — otherwise the last card has nothing beneath it to scroll into
                    // and clamps partway. `.center` keeps the card's title clear of the
                    // transparent nav bar (a `.top` landing scrolls it under the bar).
                    DispatchQueue.main.async { proxy.scrollFieldToTop(focusedEntryID, anchor: .center) }
                }
        }
    }

    /// The exercise-section id that owns the focused set. Scrolling to it lifts the
    /// whole exercise card (its name header + sets) to the top — so you can see which
    /// exercise you're logging — rather than burying the header above the focused field.
    private var focusedEntryID: PersistentIdentifier? {
        guard let setID = focusedSet?.setID else { return nil }
        return session.orderedEntries.first { entry in
            (entry.sets ?? []).contains { $0.persistentModelID == setID }
        }?.persistentModelID
    }

    private var content: some View {
        List {
            Section {
                DatePicker("Date", selection: $session.date, displayedComponents: .date)
                    .font(.sans(15))
                TextField("Title (e.g. Push Day)", text: $session.title)
                    .font(.sans(15))
            }
            .listRowBackground(Palette.surface)

            ForEach(session.orderedEntries) { entry in
                entrySection(entry)
            }

            Section {
                Button { showingPicker = true } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .font(.sans(15, .semibold))
                        .foregroundStyle(Palette.ember)
                }
                Button { showingSplitPicker = true } label: {
                    Label("Add from Split", systemImage: "rectangle.3.group.fill")
                        .font(.sans(15, .semibold))
                        .foregroundStyle(Palette.ember)
                }
            }
            .listRowBackground(Palette.surface)
        }
        .listStyle(.insetGrouped)
        // While a field is focused, give the list extra bottom room so even the *last*
        // card can scroll up to a centered position instead of clamping with nothing below.
        .contentMargins(.bottom, focusedSet != nil ? 500 : 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .keyboardDoneBar()
        .navigationTitle(isNew ? "New Workout" : "Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.entryCount > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { presentReorder() } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("reorderExercises")
                    .accessibilityLabel("Reorder Exercises")
                }
            }
            if isNew {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.sans(15, .semibold))
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { picked in add(picked) }
        }
        .sheet(isPresented: $showingSplitPicker) {
            SplitDayPickerView { day in
                session.title = day.name
                add(day.exercises)
            }
        }
        .sheet(item: $reorderRequest) { request in
            ReorderSheet(request: request)
        }
        .onDisappear {
            if isNew && session.entryCount == 0 { context.delete(session) }
        }
    }

    private func presentReorder() {
        let entries = session.orderedEntries
        reorderRequest = ReorderRequest(
            title: "Reorder Exercises",
            items: entries.map { entry in
                ReorderableItem(id: entry.persistentModelID,
                                name: entry.exercise?.name ?? "Exercise",
                                symbol: entry.exercise?.tag.symbol ?? "dumbbell.fill",
                                color: entry.exercise?.tag.color ?? Palette.ember)
            },
            onSave: { ids in
                withAnimation(.snappy) {
                    for (index, id) in ids.enumerated() {
                        entries.first { $0.persistentModelID == id }?.order = index
                    }
                }
            }
        )
    }

    // MARK: - Entry section

    @ViewBuilder
    private func entrySection(_ entry: LoggedExercise) -> some View {
        let bodyweight = entry.exercise?.isBodyweight ?? false
        Section {
            ForEach(entry.orderedSets) { set in
                SetRow(set: set, unit: unit, isBodyweight: bodyweight, focus: $focusedSet)
            }
            .onDelete { offsets in deleteSets(offsets, in: entry) }

            Button { addSet(to: entry) } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.sans(14, .semibold))
                    .foregroundStyle(Palette.ember)
            }
        } header: {
            HStack(spacing: 8) {
                Text(entry.exercise?.name ?? "Exercise")
                    .font(.sans(15, .bold))
                    .foregroundStyle(Palette.ink)
                    .textCase(nil)
                BodyweightToggleChip(isOn: bodyweight) {
                    entry.exercise?.isBodyweight.toggle()
                }
                if isNewPersonalRecord(entry) {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill")
                        Text("NEW PR")
                    }
                    .font(.sans(11, .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Palette.gold))
                    .shadow(color: Palette.gold.opacity(0.6), radius: 6)
                }
                Spacer()
                Button(role: .destructive) { context.delete(entry) } label: {
                    Image(systemName: "trash").foregroundStyle(Palette.down)
                }
                .buttonStyle(.borderless)
            }
            .padding(.bottom, 2)
        } footer: {
            VStack(alignment: .leading, spacing: 5) {
                if let reference = lastPerformance(for: entry) {
                    Label(reference, systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(Palette.inkSecondary)
                }
                if let delta = progressDelta(for: entry) {
                    Label(delta.text, systemImage: delta.positive ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(delta.positive ? Palette.up : Palette.down)
                        .font(.sans(12, .bold))
                }
            }
            .font(.sans(12))
            .padding(.top, 2)
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - Mutations

    private func add(_ exercises: [Exercise]) {
        var order = session.entryCount
        for exercise in exercises {
            if (session.entries ?? []).contains(where: { $0.exercise?.persistentModelID == exercise.persistentModelID }) {
                continue
            }
            let entry = LoggedExercise(exercise: exercise, order: order)
            entry.session = session
            context.insert(entry)
            addSet(to: entry)
            order += 1
        }
    }

    private func addSet(to entry: LoggedExercise) {
        let last = entry.orderedSets.last
        let new = LoggedSet(
            reps: last?.reps ?? prefilledReps(for: entry),
            weight: last?.weight ?? prefilledWeight(for: entry),
            order: entry.setCount
        )
        new.loggedExercise = entry
        context.insert(new)
    }

    private func deleteSets(_ offsets: IndexSet, in entry: LoggedExercise) {
        let ordered = entry.orderedSets
        for index in offsets { context.delete(ordered[index]) }
    }

    // MARK: - History lookup

    /// Whether `other` was logged before the session currently being edited.
    /// Uses the user-facing date, falling back to creation time for same-day ties.
    private func isBefore(_ other: WorkoutSession) -> Bool {
        guard other.persistentModelID != session.persistentModelID else { return false }
        if other.date != session.date { return other.date < session.date }
        return other.createdAt < session.createdAt
    }

    private func previousEntry(for entry: LoggedExercise) -> LoggedExercise? {
        guard let exercise = entry.exercise else { return nil }
        let priorSessions = allSessions
            .filter { isBefore($0) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
        for past in priorSessions {
            if let match = (past.entries ?? []).first(where: {
                $0.exercise?.persistentModelID == exercise.persistentModelID && $0.setCount > 0
            }) {
                return match
            }
        }
        return nil
    }

    private func lastPerformance(for entry: LoggedExercise) -> String? {
        guard let prev = previousEntry(for: entry) else { return nil }
        let sets = prev.orderedSets
        let body: String
        if prev.exercise?.isBodyweight ?? false {
            if sets.contains(where: { $0.weight > 0 }) {
                body = sets.map { "\($0.reps)+\($0.weight.trimmedWeight)" }
                    .joined(separator: ", ") + " \(unit.label)"
            } else {
                body = sets.map { "\($0.reps)" }.joined(separator: ", ") + " reps"
            }
        } else {
            body = sets.map { "\($0.reps)×\($0.weight.trimmedWeight)" }
                .joined(separator: ", ") + " \(unit.label)"
        }
        return "Last time: \(body)"
    }

    private func progressDelta(for entry: LoggedExercise) -> (text: String, positive: Bool)? {
        guard let prev = previousEntry(for: entry) else { return nil }
        let current = entry.bestEstimatedOneRepMax
        let previous = prev.bestEstimatedOneRepMax
        guard current > 0, previous > 0 else { return nil }

        let diff = current - previous
        if abs(diff) < 0.05 { return ("Same as last time", true) }
        let pct = diff / previous * 100
        let text = "\(abs(diff).trimmedWeight) \(unit.label) (\(String(format: "%+.0f%%", pct))) vs last"
        return (text, diff > 0)
    }

    private func allTimeBestBefore(_ entry: LoggedExercise) -> Double {
        guard let exercise = entry.exercise else { return 0 }
        var best = 0.0
        for past in allSessions where isBefore(past) {
            for e in past.entries ?? [] where e.exercise?.persistentModelID == exercise.persistentModelID {
                best = max(best, e.bestEstimatedOneRepMax)
            }
        }
        return best
    }

    private func isNewPersonalRecord(_ entry: LoggedExercise) -> Bool {
        let current = entry.bestEstimatedOneRepMax
        let previousBest = allTimeBestBefore(entry)
        return current > 0 && previousBest > 0 && current > previousBest + 0.001
    }

    private func prefilledReps(for entry: LoggedExercise) -> Int {
        previousEntry(for: entry)?.orderedSets.first?.reps ?? 8
    }

    private func prefilledWeight(for entry: LoggedExercise) -> Double {
        previousEntry(for: entry)?.orderedSets.first?.weight ?? 0
    }
}

/// Identifies which set field currently holds focus, so the logger can lift the
/// active row to the top of the screen, clear of the keyboard.
private enum SetFieldFocus: Hashable {
    case reps(PersistentIdentifier)
    case weight(PersistentIdentifier)

    var setID: PersistentIdentifier {
        switch self {
        case .reps(let id), .weight(let id): id
        }
    }
}

/// A single editable set row: index, reps, and weight — or, for body-weight
/// movements, reps plus an optional "+ added" load (0 = pure bodyweight).
private struct SetRow: View {
    @Bindable var set: LoggedSet
    let unit: WeightUnit
    var isBodyweight: Bool = false
    var focus: FocusState<SetFieldFocus?>.Binding

    var body: some View {
        HStack(spacing: 14) {
            Text("\(set.order + 1)")
                .font(.display(20))
                .foregroundStyle(Palette.ember)
                .frame(width: 28, height: 28)
                .background(Palette.ember.opacity(0.14), in: .circle)

            field($set.reps, keyboard: .numberPad, width: 56)
                .focused(focus, equals: .reps(set.persistentModelID))
                .accessibilityIdentifier("setReps")
            Text("reps").font(.sans(11, .semibold)).foregroundStyle(Palette.inkSecondary)

            Spacer()

            if isBodyweight {
                Text("+")
                    .font(.sans(16, .bold))
                    .foregroundStyle(set.weight > 0 ? Palette.ember : Palette.inkTertiary)
                fieldDouble($set.weight, width: 58)
                    .focused(focus, equals: .weight(set.persistentModelID))
                Text(unit.label).font(.sans(11, .semibold)).foregroundStyle(Palette.inkSecondary)
            } else {
                fieldDouble($set.weight, width: 68)
                    .focused(focus, equals: .weight(set.persistentModelID))
                Text(unit.label).font(.sans(11, .semibold)).foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func field(_ value: Binding<Int>, keyboard: UIKeyboardType, width: CGFloat) -> some View {
        TextField("0", value: value, format: .number)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.sans(17, .bold))
            .foregroundStyle(Palette.ink)
            .frame(width: width)
            .padding(.vertical, 8)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))
    }

    private func fieldDouble(_ value: Binding<Double>, width: CGFloat) -> some View {
        TextField("0", value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.sans(17, .bold))
            .foregroundStyle(Palette.ink)
            .frame(width: width)
            .padding(.vertical, 8)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))
    }
}
