//
//  NutrientReference.swift
//  tracklifts
//
//  Phase 2 reference data: how each `Nutrient` is grouped + scored, and the
//  Dietary Reference Intakes (DRIs) used to auto-set personalized targets.
//
//  The DRI/RDA/AI values below are the OFFICIAL published figures from the
//  Institute of Medicine / National Academies (NASEM) Dietary Reference Intakes,
//  with "stay-under" limits from the USDA–HHS Dietary Guidelines for Americans.
//  They are reference constants, not estimates. Values are daily, for adults; for
//  ages < 19 we apply the 19–30 band (the app is adult-focused).
//

import Foundation

/// How a nutrient is grouped in the micronutrient panel.
enum NutrientGroup: String, CaseIterable, Identifiable {
    case macros, fats, vitamins, minerals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .macros: "Macros"
        case .fats: "Fats & Cholesterol"
        case .vitamins: "Vitamins"
        case .minerals: "Minerals"
        }
    }

    var order: Int { NutrientGroup.allCases.firstIndex(of: self) ?? 0 }

    var symbol: String {
        switch self {
        case .macros: "chart.pie.fill"
        case .fats: "drop.fill"
        case .vitamins: "pills.fill"
        case .minerals: "bolt.fill"
        }
    }

    /// Nutrients in this group that carry a personalized target.
    var targetable: [Nutrient] {
        Nutrient.allCases.filter { $0.group == self && $0.target(sex: .male, age: 30) != nil }
    }
}

/// Whether hitting the target is good (`meetOrExceed`) or whether the value is a
/// ceiling to stay under (`stayUnder`, e.g. sodium / saturated fat).
enum NutrientLimitKind { case meetOrExceed, stayUnder }

extension Nutrient {
    var group: NutrientGroup {
        switch self {
        case .energy, .protein, .carbs, .fat, .fiber, .sugar:
            return .macros
        case .satFat, .monoFat, .polyFat, .transFat, .cholesterol:
            return .fats
        case .vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminK,
             .thiamin, .riboflavin, .niacin, .vitaminB6, .folate, .vitaminB12:
            return .vitamins
        case .sodium, .calcium, .iron, .magnesium, .phosphorus,
             .potassium, .zinc, .copper, .selenium, .manganese:
            return .minerals
        }
    }

    var limitKind: NutrientLimitKind {
        switch self {
        case .sodium, .satFat, .transFat, .cholesterol: return .stayUnder
        default: return .meetOrExceed
        }
    }

    /// The personalized daily target for this nutrient: the DRI for
    /// `meetOrExceed` nutrients, the limit for `stayUnder` nutrients, else nil.
    func target(sex: Sex, age: Int) -> Double? {
        switch limitKind {
        case .meetOrExceed: return DRI.target(self, sex: sex, age: age)
        case .stayUnder: return DRI.limit(self, sex: sex, age: age)
        }
    }

    /// Nutrients shown in the micronutrient panel (vitamins + minerals + fats).
    static var micros: [Nutrient] {
        allCases.filter { $0.group == .vitamins || $0.group == .minerals || $0.group == .fats }
    }
}

/// Dietary Reference Intakes. `target` = RDA/AI for adequacy nutrients; `limit`
/// = the recommended ceiling for "stay-under" nutrients.
enum DRI {
    /// RDA (or AI where no RDA exists) for `meetOrExceed` nutrients. nil = the
    /// nutrient has no adequacy target (handled elsewhere, or not scored).
    static func target(_ n: Nutrient, sex: Sex, age: Int) -> Double? {
        let male = sex == .male
        switch n {
        // Vitamins
        case .vitaminA:   return male ? 900 : 700          // mcg RAE
        case .vitaminC:   return male ? 90 : 75            // mg
        case .vitaminD:   return age > 70 ? 20 : 15        // mcg
        case .vitaminE:   return 15                        // mg
        case .vitaminK:   return male ? 120 : 90           // mcg (AI)
        case .thiamin:    return male ? 1.2 : 1.1          // mg
        case .riboflavin: return male ? 1.3 : 1.1          // mg
        case .niacin:     return male ? 16 : 14            // mg
        case .vitaminB6:  return age > 50 ? (male ? 1.7 : 1.5) : 1.3   // mg
        case .folate:     return 400                       // mcg DFE
        case .vitaminB12: return 2.4                       // mcg
        // Minerals
        case .calcium:
            let needsMore = male ? (age > 70) : (age > 50)
            return needsMore ? 1200 : 1000                 // mg
        case .iron:       return (!male && age <= 50) ? 18 : 8         // mg
        case .magnesium:
            if male { return age <= 30 ? 400 : 420 }
            else    { return age <= 30 ? 310 : 320 }       // mg
        case .phosphorus: return 700                       // mg
        case .potassium:  return male ? 3400 : 2600        // mg (AI)
        case .zinc:       return male ? 11 : 8             // mg
        case .copper:     return 0.9                       // mg
        case .selenium:   return 55                        // mcg
        case .manganese:  return male ? 2.3 : 1.8          // mg (AI)
        // Fiber gets an adequacy target so the panel + score reward it.
        case .fiber:      return male ? 38 : 25            // g (AI)
        default:          return nil   // energy/macros/neutral fats handled elsewhere
        }
    }

    /// Recommended daily ceiling for `stayUnder` nutrients. Saturated-fat /
    /// cholesterol / trans-fat ceilings come from the Dietary Guidelines (which
    /// set no formal Tolerable Upper Intake Level).
    static func limit(_ n: Nutrient, sex: Sex, age: Int) -> Double? {
        switch n {
        case .sodium:      return 2300   // mg (Chronic Disease Risk Reduction)
        case .satFat:      return 22     // g  (~10% of a 2,000 kcal diet)
        case .transFat:    return 2      // g  (keep as low as possible)
        case .cholesterol: return 300    // mg (traditional guideline)
        default:           return nil
        }
    }
}
