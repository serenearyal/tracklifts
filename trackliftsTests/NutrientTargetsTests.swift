//
//  NutrientTargetsTests.swift
//  trackliftsTests
//
//  Guards the Phase 2 reference data + completeness score: published DRIs resolve
//  by sex/age, nutrient grouping / limit kinds are right, and the completeness
//  score behaves (empty = 0, all-met ≈ 100, over-limit only dents, no megadose inflation).
//

import Testing
@testable import tracklifts

struct NutrientReferenceTests {

    @Test func driResolvesBySexAndAge() {
        #expect(DRI.target(.vitaminC, sex: .male, age: 30) == 90)
        #expect(DRI.target(.vitaminC, sex: .female, age: 30) == 75)
        #expect(DRI.target(.iron, sex: .female, age: 30) == 18)
        #expect(DRI.target(.iron, sex: .female, age: 60) == 8)        // post-menopausal drop
        #expect(DRI.target(.iron, sex: .male, age: 30) == 8)
        #expect(DRI.target(.calcium, sex: .female, age: 60) == 1200)  // 51+ bump
        #expect(DRI.target(.calcium, sex: .female, age: 30) == 1000)
        #expect(DRI.target(.vitaminD, sex: .male, age: 75) == 20)     // 70+ bump
        #expect(DRI.target(.vitaminD, sex: .male, age: 40) == 15)
    }

    @Test func limitsAndGroupsAreCorrect() {
        #expect(Nutrient.sodium.limitKind == .stayUnder)
        #expect(Nutrient.satFat.limitKind == .stayUnder)
        #expect(Nutrient.vitaminC.limitKind == .meetOrExceed)
        #expect(Nutrient.vitaminC.group == .vitamins)
        #expect(Nutrient.calcium.group == .minerals)
        #expect(Nutrient.cholesterol.group == .fats)
        #expect(DRI.limit(.sodium, sex: .male, age: 30) == 2300)
        // Stay-under nutrients expose their limit as the "target".
        #expect(Nutrient.sodium.target(sex: .male, age: 30) == 2300)
        // Macros have no DRI adequacy target (handled by the macro goal engine).
        #expect(Nutrient.protein.target(sex: .male, age: 30) == nil)
        #expect(Nutrient.energy.target(sex: .male, age: 30) == nil)
    }

    @Test func everyTargetableNutrientHasAPositiveTarget() {
        #expect(!NutritionGoals.targetable.isEmpty)
        for n in NutritionGoals.targetable {
            #expect((n.target(sex: .male, age: 30) ?? 0) > 0)
            #expect((n.target(sex: .female, age: 45) ?? 0) > 0)
        }
    }
}

struct CompletenessTests {

    /// A day that hits every adequacy nutrient's DRI exactly.
    private func fullyAdequate(sex: Sex, age: Int) -> [String: Double] {
        var values: [String: Double] = [:]
        for n in Completeness.scoredNutrients(sex: sex, age: age) {
            values[n.rawValue] = n.target(sex: sex, age: age) ?? 0
        }
        return values
    }

    @Test func emptyDayScoresZero() {
        #expect(Completeness.score(total: NutrientVector(), sex: .male, age: 30) == 0)
    }

    @Test func meetingEveryTargetScoresHigh() {
        let score = Completeness.score(total: NutrientVector(fullyAdequate(sex: .male, age: 30)),
                                       sex: .male, age: 30)
        #expect(score >= 99) // ~100: all coverage capped at 100%, no limit penalty
    }

    @Test func overLimitSodiumOnlyDents() {
        var values = fullyAdequate(sex: .male, age: 30)
        values[Nutrient.sodium.rawValue] = 9200 // ~4x the 2300 mg limit
        let score = Completeness.score(total: NutrientVector(values), sex: .male, age: 30)
        #expect(score < 100) // dented
        #expect(score >= 80) // but bounded — not catastrophic
    }

    @Test func megadosingOneNutrientDoesNotInflate() {
        let one = Completeness.scoredNutrients(sex: .male, age: 30).first!
        let values = [one.rawValue: (one.target(sex: .male, age: 30) ?? 1) * 100]
        let score = Completeness.score(total: NutrientVector(values), sex: .male, age: 30)
        #expect(score < 20) // only 1 of ~21 nutrients covered, despite the 100x dose
    }
}
