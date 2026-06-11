//
//  Completeness.swift
//  tracklifts
//
//  Phase 2: a daily 0–100 "how complete was your nutrition" score (Cronometer's
//  signature metric). It measures *adequacy* — how much of each vitamin/mineral
//  (and fiber) DRI today's food covered — and lightly penalizes blowing past the
//  "stay-under" limits (sodium, saturated fat…). Pure + stat-driven, so it's
//  unit-testable and needs no store.
//

import Foundation

enum Completeness {
    /// Adequacy nutrients: the meet-or-exceed micros (vitamins, minerals, fiber)
    /// that have a DRI for these stats. These are what the score averages over.
    static func scoredNutrients(sex: Sex, age: Int) -> [Nutrient] {
        NutritionGoals.targetable.filter {
            $0.limitKind == .meetOrExceed && ($0.target(sex: sex, age: age) ?? 0) > 0
        }
    }

    /// 0–100. The mean of each adequacy nutrient's DRI coverage (capped at 100%
    /// each — so megadosing one nutrient can't inflate the whole score), minus a
    /// bounded penalty for exceeding "stay-under" limits. Limit nutrients are
    /// never rewarded (more is not better); they can only subtract.
    static func score(total: NutrientVector, sex: Sex, age: Int) -> Double {
        let adequacy = scoredNutrients(sex: sex, age: age)
        guard !adequacy.isEmpty else { return 0 }

        let coverage = adequacy.reduce(0.0) { sum, n in
            let target = n.target(sex: sex, age: age) ?? 0
            return sum + min(1.0, total[n] / target)
        } / Double(adequacy.count)

        var penalty = 0.0
        for n in NutritionGoals.targetable where n.limitKind == .stayUnder {
            let limit = n.target(sex: sex, age: age) ?? 0
            guard limit > 0 else { continue }
            penalty += max(0, total[n] / limit - 1) // 0 while under the limit
        }

        let score = coverage * 100 - min(15, penalty * 10)
        return max(0, min(100, score))
    }
}
