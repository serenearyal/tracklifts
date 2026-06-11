//
//  NutritionPlan.swift
//  tracklifts
//
//  Turns the onboarding profile (goal + stats) into daily energy + macro
//  targets via Mifflin-St Jeor BMR → TDEE → goal adjustment → macro split.
//

import Foundation
import SwiftData

enum Sex: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary, light, moderate, veryActive
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .veryActive: "Very active"
        }
    }
    var detail: String {
        switch self {
        case .sedentary: "Little or no exercise"
        case .light: "1–3 sessions / week"
        case .moderate: "3–5 sessions / week"
        case .veryActive: "6+ sessions / week"
        }
    }
    var symbol: String {
        switch self {
        case .sedentary: "figure.seated.side"
        case .light: "figure.walk"
        case .moderate: "figure.run"
        case .veryActive: "figure.strengthtraining.traditional"
        }
    }
    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .veryActive: 1.725
        }
    }
}

enum FitnessGoal: String, CaseIterable, Identifiable {
    case lose, maintain, recomp, leanBulk, gain
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lose: "Lose fat"
        case .maintain: "Maintain"
        case .recomp: "Recomp"
        case .leanBulk: "Lean bulk"
        case .gain: "Gain muscle"
        }
    }
    var detail: String {
        switch self {
        case .lose: "Lean out in a calorie deficit"
        case .maintain: "Hold your weight steady"
        case .recomp: "Lose fat & build muscle, same weight"
        case .leanBulk: "Slow gain, minimal fat"
        case .gain: "Build muscle in a surplus"
        }
    }
    var symbol: String {
        switch self {
        case .lose: "arrow.down.forward.circle.fill"
        case .maintain: "equal.circle.fill"
        case .recomp: "arrow.up.arrow.down.circle.fill"
        case .leanBulk: "arrow.up.right.circle.fill"
        case .gain: "arrow.up.forward.circle.fill"
        }
    }
    /// Protein target in grams per kg bodyweight. Higher for a deficit (muscle
    /// retention), a recomp (drive composition change), and a lean bulk.
    var proteinPerKg: Double {
        switch self {
        case .lose: 2.2
        case .maintain: 1.6
        case .recomp: 2.0
        case .leanBulk: 2.0
        case .gain: 1.8
        }
    }

    /// Direction of intended weight change: -1 lose, +1 gain / lean bulk,
    /// 0 maintain / recomp (both held at maintenance calories).
    var direction: Int {
        switch self {
        case .lose: -1
        case .maintain, .recomp: 0
        case .leanBulk, .gain: 1
        }
    }

    /// Whether this goal involves a deliberate weight change (and so needs a pace).
    var changesWeight: Bool { direction != 0 }
}

/// How aggressively to pursue a lose/gain goal. Each pace maps to a weekly change
/// as a fraction of bodyweight, which (via ~`kcalPerKg`) becomes a daily calorie
/// delta and an estimated timeframe. `recommended` is the sustainable default.
enum WeightChangePace: String, CaseIterable, Identifiable {
    case relaxed, recommended, intense, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .relaxed: "Relaxed"
        case .recommended: "Recommended"
        case .intense: "Intense"
        case .custom: "Custom"
        }
    }

    /// Sustainable over the long term? Only the aggressive preset is flagged;
    /// a custom pace is judged by its actual rate in the UI.
    var isSustainable: Bool { self != .intense }

    /// Weekly change as a fraction of bodyweight, per goal direction. Fat loss
    /// tolerates a faster rate than lean-muscle gain. Maintain/recomp have no
    /// rate, and `custom` supplies its rate directly (not from a fraction).
    func weeklyRateFraction(for goal: FitnessGoal) -> Double {
        switch goal {
        case .maintain, .recomp: return 0
        case .lose:
            switch self {
            case .relaxed: return 0.0045
            case .recommended: return 0.0065
            case .intense: return 0.009
            case .custom: return 0
            }
        case .leanBulk:
            switch self {
            case .relaxed: return 0.0008
            case .recommended: return 0.0015
            case .intense: return 0.0025
            case .custom: return 0
            }
        case .gain:
            switch self {
            case .relaxed: return 0.001
            case .recommended: return 0.002
            case .intense: return 0.0035
            case .custom: return 0
            }
        }
    }
}

/// Computed daily nutrition targets.
struct NutritionPlan {
    var energy: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    // Physiological input bounds. Inputs are clamped here so a stray/huge value
    // (typo, stale weight, kg/lb confusion) can never produce absurd targets.
    static let minWeightKg = 30.0
    static let maxWeightKg = 250.0
    static let minHeightCm = 120.0
    static let maxHeightCm = 230.0
    static let minAge = 13
    static let maxAge = 100

    /// Approx. energy stored per kg of body mass — converts a weekly rate of
    /// change into a daily calorie delta. (~7700 kcal/kg, the common rule of thumb.)
    static let kcalPerKg = 7700.0

    /// Mifflin-St Jeor BMR → TDEE (× activity) → `energyDelta` → macro split
    /// (protein per-kg, fat 27% of energy, carbs fill the remainder). Inputs are
    /// clamped to sane bounds; `energyDelta` is the daily surplus(+)/deficit(−).
    static func compute(sex: Sex, age: Int, heightCm: Double, weightKg: Double,
                        activity: ActivityLevel, goal: FitnessGoal,
                        energyDelta: Double) -> NutritionPlan {
        let w = min(max(weightKg, minWeightKg), maxWeightKg)
        let h = min(max(heightCm, minHeightCm), maxHeightCm)
        let a = Double(min(max(age, minAge), maxAge))
        let bmr = 10 * w + 6.25 * h - 5 * a + (sex == .male ? 5 : -161)
        let tdee = bmr * activity.factor
        let floor = sex == .male ? 1500.0 : 1200.0
        let energy = (max(floor, tdee + energyDelta) / 10).rounded() * 10
        let protein = max(40, goal.proteinPerKg * w).rounded()
        let fat = (energy * 0.27 / 9).rounded()
        let carbs = max(0, (energy - protein * 4 - fat * 9) / 4).rounded()
        return NutritionPlan(energy: energy, protein: protein, carbs: carbs, fat: fat)
    }

    /// The weekly weight-change rate (kg) for a goal — from a preset pace
    /// (fraction of clamped bodyweight) or a user-chosen `custom` rate.
    static func weeklyRateKg(goal: FitnessGoal, weightKg: Double,
                             pace: WeightChangePace, customWeeklyKg: Double) -> Double {
        guard goal.changesWeight else { return 0 }
        if pace == .custom { return max(0, customWeeklyKg) }
        let w = min(max(weightKg, minWeightKg), maxWeightKg)
        return pace.weeklyRateFraction(for: goal) * w
    }

    /// Signed daily calorie delta from an explicit weekly rate (kg): negative for
    /// a deficit, positive for a surplus, 0 for maintain/recomp. Clamped to a safe
    /// daily magnitude so neither end of the scale gets extreme.
    static func dailyEnergyDelta(goal: FitnessGoal, weeklyRateKg: Double) -> Double {
        guard goal.changesWeight else { return 0 }
        let daily = abs(weeklyRateKg) * kcalPerKg / 7
        let magnitude = goal == .lose ? min(max(daily, 200), 1000) : min(max(daily, 75), 500)
        return Double(goal.direction) * magnitude
    }

    /// Convenience: daily delta for a preset pace.
    static func dailyEnergyDelta(goal: FitnessGoal, weightKg: Double, pace: WeightChangePace) -> Double {
        dailyEnergyDelta(goal: goal,
                         weeklyRateKg: weeklyRateKg(goal: goal, weightKg: weightKg, pace: pace, customWeeklyKg: 0))
    }

    /// Estimated weeks to move from `currentKg` to `targetKg` at a weekly rate
    /// (kg). 0 when there's no rate or no gap.
    static func weeksToTarget(currentKg: Double, targetKg: Double, weeklyRateKg: Double) -> Double {
        let r = abs(weeklyRateKg)
        guard r > 0 else { return 0 }
        return abs(currentKg - targetKg) / r
    }

    /// Convenience: weeks for a preset pace.
    static func weeksToTarget(currentKg: Double, targetKg: Double,
                              goal: FitnessGoal, pace: WeightChangePace) -> Double {
        weeksToTarget(currentKg: currentKg, targetKg: targetKg,
                      weeklyRateKg: weeklyRateKg(goal: goal, weightKg: currentKg, pace: pace, customWeeklyKg: 0))
    }
}

/// The user's single onboarding profile, stored in UserDefaults.
enum Profile {
    static let sexKey = "profileSex"
    static let ageKey = "profileAge"
    static let heightKey = "profileHeightCm"
    static let activityKey = "profileActivity"
    static let goalKey = "profileGoal"
    static let paceKey = "profilePace"
    static let customRateKey = "profileCustomRateKg"
    static let targetWeightKey = "profileTargetWeightKg"
    static let didOnboardKey = "didOnboard"

    static var sex: Sex { Sex(rawValue: UserDefaults.standard.string(forKey: sexKey) ?? "") ?? .male }
    static var age: Int { let v = UserDefaults.standard.integer(forKey: ageKey); return v == 0 ? 25 : v }
    static var heightCm: Double { let v = UserDefaults.standard.double(forKey: heightKey); return v == 0 ? 170 : v }
    static var activity: ActivityLevel {
        ActivityLevel(rawValue: UserDefaults.standard.string(forKey: activityKey) ?? "") ?? .moderate
    }
    static var goal: FitnessGoal {
        FitnessGoal(rawValue: UserDefaults.standard.string(forKey: goalKey) ?? "") ?? .maintain
    }
    static var pace: WeightChangePace {
        WeightChangePace(rawValue: UserDefaults.standard.string(forKey: paceKey) ?? "") ?? .recommended
    }
    /// Saved goal weight in kg (0 if never set).
    static var targetWeightKg: Double { UserDefaults.standard.double(forKey: targetWeightKey) }
    /// Saved custom weekly rate in kg (0 if never set / not custom).
    static var customWeeklyKg: Double { UserDefaults.standard.double(forKey: customRateKey) }

    /// Whether a profile has been saved before — used to prefill onboarding when
    /// it's re-run (Recalculate) vs. starting fresh (first run / debug reset).
    static var isSaved: Bool { UserDefaults.standard.object(forKey: goalKey) != nil }

    /// Clears the saved profile so onboarding starts as a clean first-run. Does
    /// not touch `didOnboard` (the caller decides whether to re-show onboarding).
    static func reset() {
        let d = UserDefaults.standard
        [sexKey, ageKey, heightKey, activityKey, goalKey, paceKey, customRateKey, targetWeightKey]
            .forEach(d.removeObject)
    }

    /// Persists the profile, applies the computed plan to the diary's targets,
    /// and optionally logs the weight. `weightInUnit`/`targetWeightInUnit` are in
    /// the user's unit; the calorie delta is derived from `goal` + `pace`.
    @MainActor
    static func apply(sex: Sex, age: Int, heightCm: Double, weightInUnit: Double,
                      targetWeightInUnit: Double, unit: WeightUnit, activity: ActivityLevel,
                      goal: FitnessGoal, pace: WeightChangePace, customWeeklyKg: Double,
                      logWeight: Bool, context: ModelContext) {
        let d = UserDefaults.standard
        let toKg = { (v: Double) in unit == .lb ? v * 0.453592 : v }
        let kg = toKg(weightInUnit)

        d.set(sex.rawValue, forKey: sexKey)
        d.set(age, forKey: ageKey)
        d.set(heightCm, forKey: heightKey)
        d.set(activity.rawValue, forKey: activityKey)
        d.set(goal.rawValue, forKey: goalKey)
        d.set(pace.rawValue, forKey: paceKey)
        d.set(customWeeklyKg, forKey: customRateKey)
        d.set(toKg(targetWeightInUnit), forKey: targetWeightKey)

        BodyMetrics.current = weightInUnit
        if logWeight, weightInUnit > 0 {
            context.insert(BodyWeightEntry(date: .now, weight: weightInUnit))
        }

        let weeklyKg = NutritionPlan.weeklyRateKg(goal: goal, weightKg: kg, pace: pace, customWeeklyKg: customWeeklyKg)
        let delta = NutritionPlan.dailyEnergyDelta(goal: goal, weeklyRateKg: weeklyKg)
        let plan = NutritionPlan.compute(sex: sex, age: age, heightCm: heightCm, weightKg: kg,
                                         activity: activity, goal: goal, energyDelta: delta)
        d.set(plan.energy, forKey: NutritionGoals.energyKey)
        d.set(plan.protein, forKey: NutritionGoals.proteinKey)
        d.set(plan.carbs, forKey: NutritionGoals.carbsKey)
        d.set(plan.fat, forKey: NutritionGoals.fatKey)
        // Phase 2 — personalized micronutrient targets from the same stats.
        for n in NutritionGoals.targetable {
            d.set(NutritionGoals.defaultTarget(n, sex: sex, age: age), forKey: NutritionGoals.key(for: n))
        }
        try? context.save()
    }
}
