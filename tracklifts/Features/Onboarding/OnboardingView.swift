//
//  OnboardingView.swift
//  tracklifts
//
//  First-run setup: collects the user's goal + stats and turns them into daily
//  energy + macro targets (via NutritionPlan). Shown once, and re-runnable from
//  Settings ("Recalculate").
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("weightUnit") private var unit: WeightUnit = .kg
    @AppStorage(Profile.didOnboardKey) private var didOnboard = false

    @State private var step = 0
    @State private var goal: FitnessGoal?
    @State private var sex: Sex = .male
    @State private var age = 25
    @State private var heightCm: Double = 170
    @State private var weight: Double = 0
    @State private var activity: ActivityLevel = .moderate
    @State private var pace: WeightChangePace = .recommended
    @State private var targetWeight: Double = 0
    @State private var customRateKg: Double = 0   // custom weekly rate (kg/wk)
    @State private var loaded = false
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable { case weight, goalWeight }

    /// The ordered stages. The Target & Pace stage only appears for goals that
    /// involve a weight change, so "maintain" skips straight to the plan.
    private enum Stage { case welcome, goal, about, activity, target, plan }
    private var stages: [Stage] {
        var s: [Stage] = [.welcome, .goal, .about, .activity]
        if let goal, goal.changesWeight { s.append(.target) }
        s.append(.plan)
        return s
    }
    private var stage: Stage { stages[min(step, stages.count - 1)] }
    private var lastStep: Int { stages.count - 1 }

    private var weightKg: Double { unit == .lb ? weight * 0.453592 : weight }
    /// Effective weekly rate (kg) — preset fraction × weight, or the custom rate.
    private var effectiveWeeklyKg: Double {
        NutritionPlan.weeklyRateKg(goal: goal ?? .maintain, weightKg: weightKg,
                                   pace: pace, customWeeklyKg: customRateKg)
    }
    private var energyDelta: Double {
        NutritionPlan.dailyEnergyDelta(goal: goal ?? .maintain, weeklyRateKg: effectiveWeeklyKg)
    }
    private var plan: NutritionPlan {
        NutritionPlan.compute(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
                              activity: activity, goal: goal ?? .maintain, energyDelta: energyDelta)
    }

    private var canAdvance: Bool {
        switch stage {
        case .goal: return goal != nil
        case .about: return weight > 0
        default: return true
        }
    }

    var body: some View {
        // NOTE: background applied via `.background`, not a ZStack wrapper — wrapping
        // the content in `ZStack { AppBackground(); … }` makes the ScrollView receive
        // an unbounded width, so `.frame(maxWidth:.infinity)` + `.padding` overflows
        // and the leading-aligned headers clip off the left edge.
        VStack(spacing: 0) {
            topBar
            Group {
                switch stage {
                case .welcome: welcomeStep
                case .goal: goalStep
                case .about: aboutStep
                case .activity: activityStep
                case .target: targetStep
                case .plan: planStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
        .onAppear(perform: prefill)
    }

    /// Seed the form once per appearance. When a profile was saved before
    /// (re-run via Settings → Recalculate) we restore the prior answers; a fresh
    /// first run keeps `goal` unselected and uses sensible defaults.
    private func prefill() {
        guard !loaded else { return }
        loaded = true

        if weight == 0 {
            weight = BodyMetrics.current > 0 ? BodyMetrics.current : (unit == .lb ? 160 : 72)
        }
        if Profile.isSaved {
            sex = Profile.sex
            age = Profile.age
            heightCm = Profile.heightCm
            activity = Profile.activity
            goal = Profile.goal
            pace = Profile.pace
            customRateKg = Profile.customWeeklyKg
            let savedTargetKg = Profile.targetWeightKg
            if savedTargetKg > 0 { targetWeight = unit == .lb ? savedTargetKg / 0.453592 : savedTargetKg }
        }
        if targetWeight == 0 { targetWeight = defaultTargetWeight }
        if customRateKg == 0 { customRateKg = defaultCustomRate }
    }

    /// A sensible starting custom rate (kg/wk) = the recommended preset for the goal.
    private var defaultCustomRate: Double {
        let r = WeightChangePace.recommended.weeklyRateFraction(for: goal ?? .leanBulk) * weightKg
        return r > 0 ? r : 0.005 * weightKg
    }

    /// A first-guess goal weight, nudged from the current weight by the goal
    /// direction and kept on the correct side of "now".
    private var defaultTargetWeight: Double {
        switch goal {
        case .lose: return (weight * 0.92).rounded()
        case .leanBulk: return (weight * 1.04).rounded()
        case .gain: return (weight * 1.06).rounded()
        default: return weight.rounded()
        }
    }

    // MARK: - Chrome

    @ViewBuilder private var topBar: some View {
        if step > 0 {
            HStack(spacing: 6) {
                ForEach(1...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(Grad.ember) : AnyShapeStyle(Palette.surfaceRaised))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button { withAnimation(.snappy) { step -= 1 } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 54, height: 54)
                        .background(Palette.surface, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            EmberButton(title: step == lastStep ? "Start Tracking" : (step == 0 ? "Build My Plan" : "Continue"),
                        systemImage: step == lastStep ? "checkmark" : "arrow.right") {
                if step == lastStep { finish() }
                else { withAnimation(.snappy) { step += 1 } }
            }
            .opacity(canAdvance ? 1 : 0.5)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("Logo")
                .resizable().scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: Palette.ember.opacity(0.5), radius: 22, y: 8)
            Text("TRACKLIFTS")
                .font(.display(52)).foregroundStyle(Palette.ink).tracking(1)
            Text("Let's build your nutrition plan")
                .font(.sans(17, .semibold)).foregroundStyle(Palette.ink)
            Text("A few quick questions and we'll set daily calorie + macro targets tuned to your goal.")
                .font(.sans(14)).foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var goalStep: some View {
        stepScaffold(eyebrow: "Step 1", title: "What's your goal?") {
            VStack(spacing: 12) {
                ForEach(FitnessGoal.allCases) { option in
                    selectCard(title: option.label, detail: option.detail, symbol: option.symbol,
                               selected: goal == option) {
                        withAnimation(.snappy) {
                            goal = option
                            targetWeight = defaultTargetWeight
                            customRateKg = defaultCustomRate
                        }
                    }
                }
            }
        }
    }

    private var aboutStep: some View {
        stepScaffold(eyebrow: "Step 2", title: "About you") {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Sex")
                    Picker("Sex", selection: $sex) {
                        ForEach(Sex.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .cardStyle(padding: 16)

                tickerStepper(label: "Age", display: "\(age)", unit: "yrs",
                              value: Binding(get: { Double(age) }, set: { age = Int($0.rounded()) }),
                              range: 13...100, step: 1,
                              dec: { age = max(13, age - 1) }, inc: { age = min(100, age + 1) })

                tickerStepper(label: "Height", display: heightDisplay, unit: "",
                              value: $heightCm, range: 120...220, step: heightStep,
                              dec: { heightCm = max(120, heightCm - heightStep) },
                              inc: { heightCm = min(220, heightCm + heightStep) })

                tickerField(label: "Weight", value: $weight, range: weightBounds, focus: .weight,
                            dec: { adjustWeight(-1) }, inc: { adjustWeight(1) })
            }
        }
    }

    private var activityStep: some View {
        stepScaffold(eyebrow: "Step 3", title: "How active are you?") {
            VStack(spacing: 12) {
                ForEach(ActivityLevel.allCases) { level in
                    selectCard(title: level.label, detail: level.detail, symbol: level.symbol,
                               selected: activity == level) {
                        withAnimation(.snappy) { activity = level }
                    }
                }
            }
        }
    }

    private var targetStep: some View {
        stepScaffold(eyebrow: "Step 4", title: "Target & pace") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    tickerField(label: "Goal weight", value: $targetWeight, range: targetBounds,
                                focus: .goalWeight, dec: { adjustTarget(-1) }, inc: { adjustTarget(1) })
                    Text("Now: \(weightLabel)")
                        .font(.sans(12)).foregroundStyle(Palette.inkSecondary)
                        .padding(.leading, 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("How fast?")
                    ForEach(WeightChangePace.allCases) { p in
                        selectCard(title: p.label, detail: paceDetail(p), symbol: paceSymbol(p),
                                   selected: pace == p, badge: paceBadge(p)) {
                            withAnimation(.snappy) {
                                pace = p
                                if p == .custom && customRateKg == 0 { customRateKg = defaultCustomRate }
                            }
                        }
                        if p == .custom && pace == .custom { customRateControl }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !deltaSummary.isEmpty {
                    Text(deltaSummary)
                        .font(.sans(15, .bold)).foregroundStyle(Palette.ember)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Slider + steppers to dial in a custom weekly rate (kg/wk), shown when the
    /// Custom pace is selected.
    private var customRateControl: some View {
        VStack(spacing: 10) {
            HStack {
                stepButton("minus") { adjustCustomRate(-0.05) }
                Text(customRateDisplay)
                    .font(.sans(18, .bold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                stepButton("plus") { adjustCustomRate(0.05) }
            }
            Slider(value: $customRateKg, in: safeRange(customRateBounds), step: 0.01).tint(Palette.ember)
        }
        .cardStyle(padding: 16)
        .id("customControl")
    }

    private var planStep: some View {
        stepScaffold(eyebrow: "All set", title: "Your daily targets") {
            VStack(spacing: 18) {
                VStack(spacing: 2) {
                    Text("\(Int(plan.energy))")
                        .font(.display(86)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Text("KCAL / DAY")
                        .font(.sans(12, .bold)).tracking(2).foregroundStyle(Palette.ember)
                }
                .padding(.top, 6)

                MacroPreview(nutrients: NutrientVector(energy: plan.energy, protein: plan.protein,
                                                       carbs: plan.carbs, fat: plan.fat))

                if let line = planTimeframeLine {
                    Text(line)
                        .font(.sans(13, .semibold)).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                Text("Tuned to your goal to \((goal ?? .maintain).label.lowercased()). You can fine-tune any value later in Settings.")
                    .font(.sans(13)).foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Building blocks

    private func stepScaffold<Content: View>(eyebrow: String, title: String,
                                             @ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: eyebrow)
                        Text(title.uppercased()).font(.display(40)).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Keep the focused field above the keyboard.
            .onChange(of: focusedField) { _, field in
                guard let field else { return }
                withAnimation(.snappy) { proxy.scrollTo(field, anchor: .center) }
            }
            // Reveal the custom-rate control when Custom is picked.
            .onChange(of: pace) { _, p in
                if p == .custom { withAnimation(.snappy) { proxy.scrollTo("customControl", anchor: .bottom) } }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.sans(11, .bold)).tracking(1.2).foregroundStyle(Palette.inkSecondary)
    }

    private func selectCard(title: String, detail: String, symbol: String, selected: Bool,
                            badge: (text: String, color: Color)? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? Color.black : Palette.ember)
                    .frame(width: 48, height: 48)
                    .background(selected ? AnyShapeStyle(Grad.ember) : AnyShapeStyle(Palette.ember.opacity(0.14)),
                                in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.sans(17, .bold)).foregroundStyle(Palette.ink)
                    Text(detail).font(.sans(13)).foregroundStyle(Palette.inkSecondary)
                    if let badge {
                        TagChip(text: badge.text, color: badge.color).padding(.top, 3)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Palette.ember : Palette.inkTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(selected ? Palette.ember : Palette.hairline, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    /// Stepper row + a swipeable slider, for display-only metrics (age, height).
    private func tickerStepper(label: String, display: String, unit: String,
                               value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                               dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            HStack {
                fieldLabel(label)
                Spacer()
                stepButton("minus", dec)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(display).font(.sans(20, .bold)).foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    if !unit.isEmpty {
                        Text(unit).font(.sans(12, .semibold)).foregroundStyle(Palette.inkSecondary)
                    }
                }
                .frame(minWidth: 72, alignment: .trailing)
                stepButton("plus", inc)
            }
            Slider(value: value, in: safeRange(range), step: step).tint(Palette.ember)
        }
        .cardStyle(padding: 16)
    }

    /// Typable field + steppers + swipeable slider, for weight & goal weight.
    private func tickerField(label: String, value: Binding<Double>, range: ClosedRange<Double>,
                             focus: FocusField, dec: @escaping () -> Void,
                             inc: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel(label)
            HStack(spacing: 10) {
                stepButton("minus", dec)
                TextField("0", value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: focus)
                    .multilineTextAlignment(.center)
                    .font(.sans(22, .bold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                Text(unit.label.uppercased())
                    .font(.sans(12, .bold)).tracking(1).foregroundStyle(Palette.inkSecondary)
                stepButton("plus", inc)
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 12))
            Slider(value: value, in: safeRange(range), step: 1).tint(Palette.ember)
        }
        .cardStyle(padding: 16)
        .id(focus)
    }

    /// Guards a slider against an empty/inverted range (e.g. target == current).
    private func safeRange(_ r: ClosedRange<Double>) -> ClosedRange<Double> {
        r.lowerBound < r.upperBound ? r : r.lowerBound...(r.lowerBound + 1)
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ember)
                .frame(width: 38, height: 38)
                .background(Palette.surfaceRaised, in: .circle)
        }
        .buttonStyle(.plain)
    }

    // Height stepping respects the user's unit (cm vs inches).
    private var heightStep: Double { unit == .lb ? 2.54 : 1 }
    private var heightDisplay: String {
        if unit == .lb {
            let totalInches = Int((heightCm / 2.54).rounded())
            return "\(totalInches / 12)'\(totalInches % 12)\""
        }
        return "\(Int(heightCm.rounded())) cm"
    }

    // MARK: - Target & pace helpers

    private var targetKg: Double { unit == .lb ? targetWeight * 0.453592 : targetWeight }
    private var weightLabel: String { "\(Int(weight.rounded())) \(unit.label)" }
    private var targetWeightLabel: String { "\(Int(targetWeight.rounded())) \(unit.label)" }

    /// Allowed goal-weight range in the active unit, kept on the correct side of
    /// the current weight for the chosen goal.
    private var targetBounds: ClosedRange<Double> {
        let lo = unit == .lb ? 66.0 : 30.0
        let hi = unit == .lb ? 550.0 : 250.0
        switch goal?.direction {
        case -1: return lo...max(lo, (weight - 1).rounded())     // lose: below current
        case 1: return min((weight + 1).rounded(), hi)...hi      // gain / lean bulk: above current
        default: return lo...hi
        }
    }

    private func adjustTarget(_ delta: Double) {
        let b = targetBounds
        targetWeight = min(max((targetWeight + delta).rounded(), b.lowerBound), b.upperBound)
    }

    /// Allowed body-weight range in the active unit (≈ 30–250 kg).
    private var weightBounds: ClosedRange<Double> { unit == .lb ? 66...550 : 30...250 }

    private func adjustWeight(_ delta: Double) {
        let b = weightBounds
        weight = min(max((weight + delta).rounded(), b.lowerBound), b.upperBound)
    }

    // MARK: Custom pace

    /// Custom weekly-rate range (kg/wk): a hair above the intense preset, floored low.
    private var customRateBounds: ClosedRange<Double> {
        let maxFrac = (goal ?? .leanBulk) == .lose ? 0.012 : 0.006
        return 0.05...max(0.1, maxFrac * weightKg)
    }

    private func adjustCustomRate(_ delta: Double) {
        let b = customRateBounds
        customRateKg = min(max(customRateKg + delta, b.lowerBound), b.upperBound)
    }

    /// e.g. "0.50 kg/wk", in the user's unit.
    private var customRateDisplay: String {
        let raw = unit == .lb ? customRateKg / 0.453592 : customRateKg
        return String(format: raw < 1 ? "%.2f" : "%.1f", raw) + " \(unit.label)/wk"
    }

    private func paceSymbol(_ p: WeightChangePace) -> String {
        switch p {
        case .relaxed: "tortoise.fill"
        case .recommended: "checkmark.seal.fill"
        case .intense: "hare.fill"
        case .custom: "slider.horizontal.3"
        }
    }

    private func paceBadge(_ p: WeightChangePace) -> (text: String, color: Color)? {
        switch p {
        case .recommended: return ("Sustainable", Palette.up)
        case .intense: return ("Aggressive", Palette.gold)
        case .relaxed: return nil
        case .custom:
            let intenseRate = WeightChangePace.intense.weeklyRateFraction(for: goal ?? .maintain) * weightKg
            return intenseRate > 0 && customRateKg > intenseRate
                ? ("Aggressive", Palette.gold) : ("Sustainable", Palette.up)
        }
    }

    /// The weekly rate (kg) a given pace would use, accounting for custom.
    private func paceWeeklyKg(_ p: WeightChangePace) -> Double {
        NutritionPlan.weeklyRateKg(goal: goal ?? .maintain, weightKg: weightKg,
                                   pace: p, customWeeklyKg: customRateKg)
    }

    /// e.g. "0.5 kg/wk · ~12 wks" for a pace, in the user's unit.
    private func paceDetail(_ p: WeightChangePace) -> String {
        let weeklyKg = paceWeeklyKg(p)
        let raw = unit == .lb ? weeklyKg / 0.453592 : weeklyKg
        // Two decimals below 1 unit/wk so slow paces (lean bulk) stay distinct.
        let weekly = String(format: raw < 1 ? "%.2f" : "%.1f", raw)
        let wks = Int(NutritionPlan.weeksToTarget(currentKg: weightKg, targetKg: targetKg,
                                                  weeklyRateKg: weeklyKg).rounded())
        let time = wks > 0 ? " · ~\(wks) wk\(wks == 1 ? "" : "s")" : ""
        return "\(weekly) \(unit.label)/wk\(time)"
    }

    /// Daily calorie delta for the selected pace, e.g. "−515 kcal / day deficit".
    private var deltaSummary: String {
        let d = Int(energyDelta.rounded())
        guard d != 0 else { return "" }
        return "\(d > 0 ? "+" : "−")\(abs(d)) kcal / day \(d > 0 ? "surplus" : "deficit")"
    }

    private var weeks: Double {
        NutritionPlan.weeksToTarget(currentKg: weightKg, targetKg: targetKg, weeklyRateKg: effectiveWeeklyKg)
    }

    /// "Reach 75 kg in ~12 weeks at a recommended pace." — only for lose/gain.
    private var planTimeframeLine: String? {
        guard let goal, goal.changesWeight else { return nil }
        let wks = Int(weeks.rounded())
        guard wks > 0 else { return nil }
        let time = wks < 12 ? "~\(wks) weeks" : "~\(Int((weeks / 4.345).rounded())) months"
        return "Reach \(targetWeightLabel) in \(time) at a \(pace.label.lowercased()) pace."
    }

    // MARK: - Finish

    private func finish() {
        Profile.apply(sex: sex, age: age, heightCm: heightCm, weightInUnit: weight,
                      targetWeightInUnit: targetWeight, unit: unit, activity: activity,
                      goal: goal ?? .maintain, pace: pace, customWeeklyKg: customRateKg,
                      logWeight: true, context: context)
        didOnboard = true
    }
}
