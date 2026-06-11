//
//  usda-import.swift
//  tracklifts — build-time tool (NOT part of the app target)
//
//  Converts a USDA FoodData Central "Full Download" CSV bundle (SR Legacy +
//  Foundation foods, public domain) into tracklifts/Resources/FoodCatalog.json:
//  the Phase 2 food catalog carrying the full micronutrient panel. Foundation-only.
//
//  Usage:
//    swift tools/usda-import.swift --input <fdc_csv_dir> \
//        --output tracklifts/Resources/FoodCatalog.json [--limit 3000]
//    swift tools/usda-import.swift --input tools/usda-fixture --verify
//
//  Get the CSVs from https://fdc.nal.usda.gov/download-datasets (choose the
//  SR Legacy and Foundation "Full Download" CSV bundles; unzip into one dir with
//  food.csv + food_nutrient.csv). FDC amounts are per 100 g and already in our
//  canonical units (g / mg / mcg / kcal) for the mapped ids — only energy
//  precedence and Vitamin D IU need conversion (handled in `resolve`).
//

import Foundation

// MARK: - Output shape (mirrors `CatalogRecord` decoded by FoodSeedManager)

struct OutPortion: Codable { let label: String; let grams: Double }
struct OutRecord: Codable {
    let name: String
    let brand: String
    let fdcId: Int
    let nutrients: [String: Double]
    let portions: [OutPortion]
}

// MARK: - USDA nutrient_id -> our Nutrient.rawValue (units already canonical)

let primaryMap: [Int: String] = [
    1008: "energy",                                   // kcal
    1003: "protein", 1004: "fat", 1005: "carbs",
    1079: "fiber", 2000: "sugar",
    1258: "satFat", 1292: "monoFat", 1293: "polyFat", 1257: "transFat",
    1253: "cholesterol", 1093: "sodium",
    1106: "vitaminA",                                 // mcg RAE
    1162: "vitaminC", 1114: "vitaminD",               // mcg
    1109: "vitaminE", 1185: "vitaminK",
    1165: "thiamin", 1166: "riboflavin", 1167: "niacin",
    1175: "vitaminB6", 1190: "folate",                // mcg DFE
    1178: "vitaminB12",
    1087: "calcium", 1089: "iron", 1090: "magnesium",
    1091: "phosphorus", 1092: "potassium",
    1095: "zinc", 1098: "copper", 1103: "selenium", 1101: "manganese",
]

// Fallback ids, used only when the preferred id is absent for a food.
let energyKJ = 1062, energyAtwaterGeneral = 2047, energyAtwaterSpecific = 2048
let vitDIU = 1110, sugarAlt = 1063, folateTotal = 1177
let fallbackIds: Set<Int> = [energyKJ, energyAtwaterGeneral, energyAtwaterSpecific,
                             vitDIU, sugarAlt, folateTotal]
let caredIds = Set(primaryMap.keys).union(fallbackIds)
let keepTypes: Set<String> = ["sr_legacy_food", "foundation_food"]
let defaultPortions = [OutPortion(label: "100 g", grams: 100),
                       OutPortion(label: "1 oz (28 g)", grams: 28)]

// MARK: - Helpers

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8)); exit(1)
}
func log(_ msg: String) { FileHandle.standardError.write(Data((msg + "\n").utf8)) }

/// Robust CSV line split (handles quoted fields with embedded commas / "" escapes).
func parseCSVLine(_ chars: [Character]) -> [String] {
    var fields: [String] = []; var cur = ""; var inQ = false; var i = 0
    while i < chars.count {
        let c = chars[i]
        if inQ {
            if c == "\"" {
                if i + 1 < chars.count && chars[i + 1] == "\"" { cur.append("\""); i += 1 }
                else { inQ = false }
            } else { cur.append(c) }
        } else if c == "\"" { inQ = true }
        else if c == "," { fields.append(cur); cur = "" }
        else { cur.append(c) }
        i += 1
    }
    fields.append(cur); return fields
}

/// Strip surrounding double quotes from a CSV field (FDC quotes every value).
func unquote(_ s: Substring) -> String {
    var t = s
    if t.hasPrefix("\"") { t = t.dropFirst() }
    if t.hasSuffix("\"") { t = t.dropLast() }
    return String(t)
}

func readLines(_ path: String) -> [String] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { die("cannot read \(path)") }
    var lines: [String] = []
    text.enumerateLines { line, _ in lines.append(line) }
    return lines
}

/// USDA descriptions are like "Spinach, raw" — trim and collapse whitespace.
func cleanName(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Resolve a food's raw {nutrient_id: amount} into {our key: amount}.
func resolve(_ raw: [Int: Double]) -> [String: Double] {
    var out: [String: Double] = [:]
    for (id, key) in primaryMap where raw[id] != nil { out[key] = raw[id] }
    // Energy: prefer 1008 kcal, then Atwater kcal, then kJ -> kcal.
    if out["energy"] == nil {
        if let v = raw[energyAtwaterSpecific] ?? raw[energyAtwaterGeneral] { out["energy"] = v }
        else if let kj = raw[energyKJ] { out["energy"] = kj / 4.184 }
    }
    // Vitamin D: prefer mcg (1114), else IU (1110) / 40.
    if out["vitaminD"] == nil, let iu = raw[vitDIU] { out["vitaminD"] = iu / 40 }
    // Sugar / folate fallbacks.
    if out["sugar"] == nil, let v = raw[sugarAlt] { out["sugar"] = v }
    if out["folate"] == nil, let v = raw[folateTotal] { out["folate"] = v }
    return out.mapValues { ($0 * 1000).rounded() / 1000 }   // tidy JSON
}

// MARK: - Args

let args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let verify = args.contains("--verify")
let inputDir = opt("--input") ?? "tools/usda-fixture"
let outputPath = opt("--output")
let limit = opt("--limit").flatMap { Int($0) }

// MARK: - food.csv -> kept foods (sr_legacy + foundation)

let foodLines = readLines(inputDir + "/food.csv")
guard foodLines.count > 1 else { die("empty food.csv in \(inputDir)") }
let foodHeader = parseCSVLine(Array(foodLines[0]))
guard let fdcIdx = foodHeader.firstIndex(of: "fdc_id"),
      let typeIdx = foodHeader.firstIndex(of: "data_type"),
      let descIdx = foodHeader.firstIndex(of: "description") else { die("food.csv missing columns") }

var foodNames: [Int: String] = [:]
for line in foodLines.dropFirst() where !line.isEmpty {
    let f = parseCSVLine(Array(line))
    guard f.count > max(fdcIdx, typeIdx, descIdx), keepTypes.contains(f[typeIdx]),
          let id = Int(f[fdcIdx]) else { continue }
    foodNames[id] = cleanName(f[descIdx])
}
log("Kept \(foodNames.count) foods (sr_legacy + foundation).")

// MARK: - food_nutrient.csv (big, numeric) -> per-food {id: amount}

let fnLines = readLines(inputDir + "/food_nutrient.csv")
guard fnLines.count > 1 else { die("empty food_nutrient.csv in \(inputDir)") }
// Fast comma-split (these columns are numeric, no embedded commas) + unquote,
// since FDC wraps every field — including the numbers — in double quotes.
let fnHeader = fnLines[0].split(separator: ",", omittingEmptySubsequences: false).map { unquote($0) }
guard let fnFdcIdx = fnHeader.firstIndex(of: "fdc_id"),
      let fnNutIdx = fnHeader.firstIndex(of: "nutrient_id"),
      let fnAmtIdx = fnHeader.firstIndex(of: "amount") else { die("food_nutrient.csv missing columns") }

var perFood: [Int: [Int: Double]] = [:]
for line in fnLines.dropFirst() where !line.isEmpty {
    let f = line.split(separator: ",", omittingEmptySubsequences: false)
    guard f.count > max(fnFdcIdx, fnNutIdx, fnAmtIdx),
          let fdc = Int(unquote(f[fnFdcIdx])), foodNames[fdc] != nil,
          let nid = Int(unquote(f[fnNutIdx])), caredIds.contains(nid),
          let amt = Double(unquote(f[fnAmtIdx])) else { continue }
    perFood[fdc, default: [:]][nid] = amt
}

// MARK: - Build records

var records: [OutRecord] = []
for (id, name) in foodNames {
    guard let raw = perFood[id] else { continue }
    let nutrients = resolve(raw)
    guard let kcal = nutrients["energy"], kcal > 0 else { continue }   // need energy
    records.append(OutRecord(name: name, brand: "", fdcId: id, nutrients: nutrients, portions: defaultPortions))
}
// When capping, keep the N most data-complete foods (most nutrients populated),
// not an alphabetical slice — so a smaller catalog still spans A–Z.
if let limit, records.count > limit {
    records = Array(records.sorted { $0.nutrients.count > $1.nutrients.count }.prefix(limit))
}
records.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
log("Built \(records.count) catalog records.")

// MARK: - Output

if verify {
    let cols = ["energy", "protein", "carbs", "fat", "fiber", "vitaminA", "vitaminC",
                "vitaminD", "vitaminK", "folate", "calcium", "iron", "potassium", "sodium"]
    for r in records.prefix(25) {
        let panel = cols.compactMap { k in r.nutrients[k].map { "\(k)=\(($0 * 100).rounded() / 100)" } }
            .joined(separator: " ")
        print("• \(r.name) [fdc \(r.fdcId)]\n    \(panel)")
    }
    print("(\(records.count) records)")
}
if let outputPath {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? enc.encode(records) else { die("encode failed") }
    do { try data.write(to: URL(fileURLWithPath: outputPath)) }
    catch { die("write failed: \(error.localizedDescription)") }
    log("Wrote \(records.count) records -> \(outputPath)")
} else if !verify {
    log("Nothing to do: pass --output <path> and/or --verify.")
}
