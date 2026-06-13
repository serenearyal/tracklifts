//
//  MealTextParserTests.swift
//  trackliftsTests
//
//  Guards the Phase 4 on-device meal parser: segmentation (commas / and / with),
//  quantity forms (digits, fractions, written words, fused "200g"), and unit
//  normalization. Pure — no SwiftData, no network.
//

import Foundation
import Testing
@testable import tracklifts

struct MealTextParserTests {

    @Test func parsesAMultiItemMeal() {
        let items = MealTextParser.parse("2 eggs, 1 cup oatmeal, a banana, 200g chicken breast")
        #expect(items.count == 4)

        #expect(items[0] == ParsedItem(name: "eggs", quantity: 2, unit: ""))
        #expect(items[1] == ParsedItem(name: "oatmeal", quantity: 1, unit: "cup"))
        #expect(items[2] == ParsedItem(name: "banana", quantity: 1, unit: ""))
        #expect(items[3] == ParsedItem(name: "chicken breast", quantity: 200, unit: "g"))
    }

    @Test func splitsOnWordSeparatorsButNotMidWord() {
        // "with"/"and" split; "sandwich" (contains "and") must not.
        let items = MealTextParser.parse("oatmeal with blueberries and a turkey sandwich")
        #expect(items.map(\.name) == ["oatmeal", "blueberries", "turkey sandwich"])
    }

    @Test func understandsFractionsAndWrittenNumbers() {
        #expect(MealTextParser.parse("1/2 cup rice").first == ParsedItem(name: "rice", quantity: 0.5, unit: "cup"))
        #expect(MealTextParser.parse("½ avocado").first == ParsedItem(name: "avocado", quantity: 0.5, unit: ""))
        #expect(MealTextParser.parse("three eggs").first == ParsedItem(name: "eggs", quantity: 3, unit: ""))
        // article between the number and the unit.
        #expect(MealTextParser.parse("half a cup of greek yogurt").first
                == ParsedItem(name: "greek yogurt", quantity: 0.5, unit: "cup"))
    }

    @Test func normalizesUnitSynonymsAndFusedTokens() {
        #expect(MealTextParser.parse("2 tbsp peanut butter").first?.unit == "tbsp")
        #expect(MealTextParser.parse("2 tablespoons peanut butter").first?.unit == "tbsp")
        #expect(MealTextParser.parse("8oz steak").first == ParsedItem(name: "steak", quantity: 8, unit: "oz"))
        #expect(MealTextParser.parse("250ml milk").first == ParsedItem(name: "milk", quantity: 250, unit: "ml"))
    }

    @Test func dropsFillerWordsAndKeepsTheFoodName() {
        #expect(MealTextParser.parse("a bowl of brown rice").first
                == ParsedItem(name: "brown rice", quantity: 1, unit: "bowl"))
        #expect(MealTextParser.parse("some spinach").first
                == ParsedItem(name: "spinach", quantity: 1, unit: ""))
    }

    @Test func emptyOrWhitespaceYieldsNothing() {
        #expect(MealTextParser.parse("").isEmpty)
        #expect(MealTextParser.parse("   \n  ").isEmpty)
        #expect(MealTextParser.parse(",,, and ").isEmpty)
    }
}
