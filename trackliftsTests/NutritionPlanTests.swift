//
//  NutritionPlanTests.swift
//  trackliftsTests
//
//  Guards the onboarding math: targets must stay physiologically sane for any
//  input (the "11000 kcal / 900 g protein" bug), and the pace → calorie-delta /
//  timeframe conversions must behave.
//

import Testing
@testable import tracklifts

struct NutritionPlanTests {

    // MARK: - Clamping (the reported bug)

    @Test func absurdWeightProducesSaneTargets() {
        // A wildly out-of-range weight (typo / stale value / kg-lb confusion)
        // must not blow up energy or protein.
        let delta = NutritionPlan.dailyEnergyDelta(goal: .gain, weightKg: 999, pace: .intense)
        let plan = NutritionPlan.compute(sex: .male, age: 25, heightCm: 999, weightKg: 999,
                                         activity: .veryActive, goal: .gain, energyDelta: delta)
        #expect(plan.energy <= 8000)      // was ~11000 before the clamp
        #expect(plan.protein <= 550)      // was ~900 before the clamp
        #expect(plan.energy >= 1500)
        #expect(plan.carbs >= 0)
    }

    @Test func normalProfileIsReasonable() {
        let delta = NutritionPlan.dailyEnergyDelta(goal: .lose, weightKg: 80, pace: .recommended)
        let plan = NutritionPlan.compute(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                         activity: .moderate, goal: .lose, energyDelta: delta)
        #expect((1500...3500).contains(plan.energy))
        #expect((120...220).contains(plan.protein))
    }

    @Test func sexAwareFloorIsRespected() {
        // Even an extreme deficit cannot push a woman below 1200 kcal.
        let plan = NutritionPlan.compute(sex: .female, age: 100, heightCm: 120, weightKg: 30,
                                         activity: .sedentary, goal: .lose, energyDelta: -1000)
        #expect(plan.energy == 1200)
    }

    // MARK: - Pace → calorie delta

    @Test func recommendedPaceGivesSaneDeficit() {
        let delta = NutritionPlan.dailyEnergyDelta(goal: .lose, weightKg: 80, pace: .recommended)
        #expect(delta < 0)
        #expect(delta >= -1000)
    }

    @Test func gainSurplusIsPositiveAndClamped() {
        let delta = NutritionPlan.dailyEnergyDelta(goal: .gain, weightKg: 80, pace: .recommended)
        #expect(delta > 0)
        #expect(delta <= 500)
    }

    @Test func fasterPaceMeansBiggerDelta() {
        let relaxed = NutritionPlan.dailyEnergyDelta(goal: .lose, weightKg: 90, pace: .relaxed)
        let recommended = NutritionPlan.dailyEnergyDelta(goal: .lose, weightKg: 90, pace: .recommended)
        let intense = NutritionPlan.dailyEnergyDelta(goal: .lose, weightKg: 90, pace: .intense)
        #expect(abs(relaxed) < abs(recommended))
        #expect(abs(recommended) < abs(intense))
    }

    @Test func leanBulkIsAGentlerSurplusThanGain() {
        let lean = NutritionPlan.dailyEnergyDelta(goal: .leanBulk, weightKg: 80, pace: .recommended)
        let gain = NutritionPlan.dailyEnergyDelta(goal: .gain, weightKg: 80, pace: .recommended)
        #expect(lean > 0)
        #expect(lean < gain)
        #expect(lean <= 500)
        #expect(FitnessGoal.leanBulk.direction == 1)
    }

    @Test func recompHoldsMaintenanceWithHigherProtein() {
        let recomp = NutritionPlan.compute(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                           activity: .moderate, goal: .recomp, energyDelta: 0)
        let maintain = NutritionPlan.compute(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                             activity: .moderate, goal: .maintain, energyDelta: 0)
        #expect(recomp.energy == maintain.energy)   // maintenance calories
        #expect(recomp.protein > maintain.protein)  // but more protein (2.0 vs 1.6 g/kg)
        #expect(FitnessGoal.recomp.direction == 0)
        #expect(!FitnessGoal.recomp.changesWeight)  // so it skips the pace step
        #expect(NutritionPlan.dailyEnergyDelta(goal: .recomp, weeklyRateKg: 0) == 0)
    }

    @Test func customRateDrivesDeltaAndTimeframe() {
        let delta = NutritionPlan.dailyEnergyDelta(goal: .lose, weeklyRateKg: 0.5)
        #expect(delta < 0)
        #expect(abs(delta + 550) < 30)   // 0.5 kg/wk × 7700 / 7 ≈ 550
        let weeks = NutritionPlan.weeksToTarget(currentKg: 80, targetKg: 76, weeklyRateKg: 0.5)
        #expect(abs(weeks - 8) < 0.001) // 4 kg / 0.5 = 8 weeks
    }

    @Test func customRateStillClamped() {
        #expect(NutritionPlan.dailyEnergyDelta(goal: .lose, weeklyRateKg: 5) >= -1000)
    }

    @Test func maintainHasNoDelta() {
        #expect(NutritionPlan.dailyEnergyDelta(goal: .maintain, weightKg: 80, pace: .recommended) == 0)
        #expect(WeightChangePace.recommended.weeklyRateFraction(for: .maintain) == 0)
    }

    // MARK: - Sustainability flag + timeframe

    @Test func onlyIntenseIsFlaggedUnsustainable() {
        #expect(WeightChangePace.relaxed.isSustainable)
        #expect(WeightChangePace.recommended.isSustainable)
        #expect(!WeightChangePace.intense.isSustainable)
    }

    @Test func weeksToTargetIsPositiveForAGap() {
        let weeks = NutritionPlan.weeksToTarget(currentKg: 80, targetKg: 72, goal: .lose, pace: .recommended)
        #expect(weeks > 0)
        // ~8 kg at ~0.5 kg/week → in the rough neighbourhood of a few months.
        #expect((8...30).contains(weeks))
    }

    @Test func weeksToTargetIsZeroWhenNoGap() {
        #expect(NutritionPlan.weeksToTarget(currentKg: 80, targetKg: 80, goal: .lose, pace: .recommended) == 0)
        #expect(NutritionPlan.weeksToTarget(currentKg: 80, targetKg: 72, goal: .maintain, pace: .recommended) == 0)
    }
}
