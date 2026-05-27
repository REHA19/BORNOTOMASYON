import Foundation

// MARK: - Alapala YEM Formula TXT Parser
// Supports the "FORMÜL ANALİZ SONUCU" report format exported from Alapala YEM software.

struct AlapalaFormulaParser {

    enum ParserError: LocalizedError {
        case cannotRead
        case notAlapalaFormat
        var errorDescription: String? {
            switch self {
            case .cannotRead:        return "Dosya okunamadı. Farklı bir kodlama deneyin."
            case .notAlapalaFormat:  return "Alapala YEM formatı tanınamadı. Hammadde satırları bulunamadı."
            }
        }
    }

    struct ParseResult {
        var formulaCode:  String
        var formulaName:  String
        var totalKg:      Double
        var ingredients:  [BFIngredient]
        var constraints:  [BFConstraint]
    }

    // MARK: - Public API

    static func isAlapalaFormat(url: URL) -> Bool {
        guard let text = readText(from: url) else { return false }
        let u = text.uppercased(with: Locale(identifier: "en_US"))
        return u.contains("HAMMADDE") || u.contains("ALAPALA") || u.contains("BESIN MADDESI") || u.contains("FORMUL")
    }

    static func parse(url: URL) throws -> ParseResult {
        guard let text = readText(from: url) else { throw ParserError.cannotRead }
        return try parseText(text)
    }

    // MARK: - File reading (multiple encodings)

    private static func readText(from url: URL) -> String? {
        let encs: [String.Encoding] = [.utf8, .windowsCP1254, .windowsCP1252, .isoLatin1, .ascii]
        for enc in encs {
            if let s = try? String(contentsOf: url, encoding: enc) { return s }
        }
        return nil
    }

    // MARK: - Main parser

    static func parseText(_ text: String) throws -> ParseResult {
        let lines = text.components(separatedBy: .newlines)

        var formulaCode = ""
        var formulaName = ""
        var totalKgRaw: Double = 1000

        struct RawIng  { var code: String; var name: String; var minKg: Double; var maxKg: Double; var priceTL: Double? }
        struct RawCon  { var code: String; var name: String; var unit: String
                         var curVal: Double?; var minVal: Double?; var maxVal: Double? }

        var rawIngs:  [RawIng]  = []
        var rawCons:  [RawCon]  = []

        for line in lines {
            let lineU = enUS(line)

            // ── Formula metadata (plain text lines with ":" separator) ──────────────
            // Use "FORM" (ASCII-safe prefix of "Formül") to avoid Ü vs U mismatch
            if formulaCode.isEmpty && lineU.contains("FORM") && lineU.contains("KOD") {
                let val = afterLastColon(line)
                if !val.isEmpty { formulaCode = val }
                continue
            }
            if formulaName.isEmpty && lineU.contains("FORM") && !lineU.contains("KOD")
                && lineU.contains("AD") && line.contains(":") {
                let val = afterLastColon(line)
                if !val.isEmpty { formulaName = val }
                continue
            }

            // ── Toplam (batch size) ───────────────────────────────────────────────
            let tabs = tabTokens(line)
            if tabs.count >= 2 && enUS(tabs[0]) == "TOPLAM" {
                totalKgRaw = turkishDouble(tabs[1]) ?? 1000
                continue
            }

            // ── Data rows: first token must be integer ────────────────────────────
            guard tabs.count >= 4, Int(tabs[0]) != nil else { continue }

            let code  = tabs[0]
            let name  = tabs[1]
            let third = tabs[2]

            if isUnitToken(third) {
                // Nutrient row: [code, name, unit, değer, (altSınır), (üstSınır)]
                // tabs[3] = current formula value; tabs[4] = min; tabs[5] = max
                let curV = turkishDouble(tabs[3])
                let minV = tabs.count >= 5 ? strictPositive(turkishDouble(tabs[4])) : nil
                let maxV = tabs.count >= 6 ? strictPositive(turkishDouble(tabs[5])) : nil
                rawCons.append(RawCon(code: code, name: name, unit: third,
                                      curVal: curV, minVal: minV, maxVal: maxV))
            } else {
                // Ingredient row: [code, name, karışım, altSınır, üstSınır, (fiyat)]
                guard tabs.count >= 5 else { continue }
                let minKg  = turkishDouble(tabs[3]) ?? 0
                let maxKg  = turkishDouble(tabs[4]) ?? 0
                let priceTL = tabs.count >= 6 ? turkishDouble(tabs[5]) : nil
                rawIngs.append(RawIng(code: code, name: name, minKg: minKg, maxKg: maxKg, priceTL: priceTL))
            }
        }

        guard !rawIngs.isEmpty else { throw ParserError.notAlapalaFormat }

        let tk = totalKgRaw > 0 ? totalKgRaw : 1000

        // Convert kg → %
        let ingredients: [BFIngredient] = rawIngs.map { r in
            let minPct = r.minKg / tk * 100
            let maxPct = r.maxKg > 0 ? r.maxKg / tk * 100 : 100
            return BFIngredient(
                code: r.code,
                name: r.name,
                minPct: minPct,
                maxPct: min(maxPct, 100),
                overridePriceTLPerTon: r.priceTL
            )
        }

        // Map Alapala numeric code → nutrient key.
        // Import ALL recognised rows, including those with no min/max limit:
        //   - rows WITH min/max → active LP constraints (isActive = true)
        //   - rows WITHOUT min/max but WITH a current value → display-only (isActive = false)
        //   - rows without any useful data → skip
        let constraints: [BFConstraint] = rawCons.compactMap { r in
            guard let def = nutrientDef(forAlapalaCode: r.code) else { return nil }
            let hasLimit = r.minVal != nil || r.maxVal != nil
            let hasValue = r.curVal != nil
            guard hasLimit || hasValue else { return nil }
            return BFConstraint(
                nutrientKey:  def.key,
                displayName:  def.displayName,
                unit:         r.unit.isEmpty ? def.unit : r.unit,
                isActive:     hasLimit,          // non-constrained rows don't enter LP
                minValue:     r.minVal,
                maxValue:     r.maxVal,
                currentValue: r.curVal           // pre-fill with TXT analysis value
            )
        }

        return ParseResult(
            formulaCode: formulaCode,
            formulaName: formulaName,
            totalKg:     tk,
            ingredients: ingredients,
            constraints: constraints
        )
    }

    // MARK: - Helpers

    private static func tabTokens(_ line: String) -> [String] {
        line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func enUS(_ s: String) -> String {
        s.uppercased(with: Locale(identifier: "en_US"))
    }

    private static func afterLastColon(_ line: String) -> String {
        guard let r = line.range(of: ":", options: .backwards) else { return "" }
        return String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private static func isUnitToken(_ s: String) -> Bool {
        let u = enUS(s.trimmingCharacters(in: .whitespaces))
        return u == "%" || u.contains("KG") || u.contains("GR/") || u.contains("KCAL") || u.contains("MEQ")
    }

    private static func turkishDouble(_ s: String) -> Double? {
        // "13.000,27" → remove thousands "." → "13000,27" → swap "," → "13000.27"
        let cleaned = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private static func strictPositive(_ v: Double?) -> Double? {
        guard let v, v > 1e-9 else { return nil }
        return v
    }

    // MARK: - Alapala code → NutrientDef mapping

    private static func nutrientDef(forAlapalaCode code: String) -> NutrientDef? {
        alapalaCodeMap[code]
    }

    private static let alapalaCodeMap: [String: NutrientDef] = [
        "1":   NutrientDef(key: "dryMatter",       displayName: "Kuru Madde",          unit: "%"),
        "2":   NutrientDef(key: "crudeProtein",     displayName: "Ham Protein",         unit: "%"),
        "7":   NutrientDef(key: "crudeAsh",         displayName: "Ham Kül",             unit: "%"),
        "6":   NutrientDef(key: "crudeFiber",       displayName: "Ham Selüloz",         unit: "%"),
        "5":   NutrientDef(key: "crudeFat",         displayName: "Ham Yağ",             unit: "%"),
        "54":  NutrientDef(key: "starch",           displayName: "Nişasta",             unit: "%"),
        "53":  NutrientDef(key: "sugar",            displayName: "Şeker",               unit: "%"),
        "111": NutrientDef(key: "ndf",              displayName: "NDF",                 unit: "%"),
        "112": NutrientDef(key: "adf",              displayName: "ADF",                 unit: "%"),
        "113": NutrientDef(key: "adl",              displayName: "ADL",                 unit: "%"),
        "114": NutrientDef(key: "nel",              displayName: "NEL 3x NRC",          unit: "KCal/Kg"),
        "115": NutrientDef(key: "me1xNRC",          displayName: "ME 1x NRC",           unit: "KCal/Kg"),
        "116": NutrientDef(key: "tse9610",          displayName: "TSE 9610",            unit: "KCal/Kg"),
        "117": NutrientDef(key: "ufl",              displayName: "UFL INRA",            unit: ""),
        "118": NutrientDef(key: "ufv",              displayName: "UFV INRA",            unit: ""),
        "155": NutrientDef(key: "pdie",             displayName: "PDIE",                unit: "Gr/Kg"),
        "156": NutrientDef(key: "pdia",             displayName: "PDIA",                unit: "Gr/Kg"),
        "154": NutrientDef(key: "pdin",             displayName: "PDIN",                unit: "Gr/Kg"),
        "119": NutrientDef(key: "nfc",              displayName: "NFC",                 unit: "%"),
        "120": NutrientDef(key: "nsc",              displayName: "NSC",                 unit: "%"),
        "85":  NutrientDef(key: "nfe",              displayName: "NFE",                 unit: "%"),
        "160": NutrientDef(key: "organicMatter",    displayName: "Organik Madde",       unit: "%"),
        "16":  NutrientDef(key: "calcium",          displayName: "Kalsiyum (Ca)",       unit: "%"),
        "17":  NutrientDef(key: "phosphorus",       displayName: "Fosfor (P)",          unit: "%"),
        "18":  NutrientDef(key: "totalPhosphorus",  displayName: "Toplam Fosfor",       unit: "%"),
        "21":  NutrientDef(key: "sodium",           displayName: "Sodyum (Na)",         unit: "%"),
        "23":  NutrientDef(key: "chlorine",         displayName: "Klor (Cl)",           unit: "%"),
        "121": NutrientDef(key: "magnesium",        displayName: "Magnezyum (Mg)",      unit: "%"),
        "122": NutrientDef(key: "potassium",        displayName: "Potasyum (K)",        unit: "%"),
        "131": NutrientDef(key: "dcap",             displayName: "DCAP",                unit: "mEq/Kg"),
        "132": NutrientDef(key: "rdp",              displayName: "RDP",                 unit: "%"),
        "133": NutrientDef(key: "rup",              displayName: "RUP",                 unit: "%"),
        "134": NutrientDef(key: "rupCP",            displayName: "RUP %CP",             unit: "%"),
        "139": NutrientDef(key: "solProtein",       displayName: "SP Soluble Protein",  unit: "%"),
        "140": NutrientDef(key: "tdn",              displayName: "TDN",                 unit: "%"),
        "141": NutrientDef(key: "rdsStarch",        displayName: "RDS Nişasta",         unit: "%"),
        "143": NutrientDef(key: "peletRenk",        displayName: "Pelet Renk",          unit: ""),
        "144": NutrientDef(key: "peletKalite",      displayName: "Pelet Kalite",        unit: ""),
        "145": NutrientDef(key: "prestKapasite",    displayName: "Prest Kapasite",      unit: ""),
        "8":   NutrientDef(key: "methionine",       displayName: "Metiyonin",           unit: "%"),
        "10":  NutrientDef(key: "lysine",           displayName: "Lizin",               unit: "%"),
        "12":  NutrientDef(key: "metCys",           displayName: "Met+Cys",             unit: "%"),
        "34":  NutrientDef(key: "tryptophan",       displayName: "Triptofan",           unit: "%"),
        "26":  NutrientDef(key: "threonine",        displayName: "Treonin",             unit: "%"),
        "24":  NutrientDef(key: "arginine",         displayName: "Arjinin",             unit: "%"),
        "9":   NutrientDef(key: "sinMethionine",    displayName: "Sin. Metiyonin",      unit: "%"),
        "11":  NutrientDef(key: "sinLysine",        displayName: "Sin. Lizin",          unit: "%"),
        "13":  NutrientDef(key: "sinMetCys",        displayName: "Sin. Met+Cys",        unit: "%"),
        "4":   NutrientDef(key: "mePoultryFixed",   displayName: "ME Kanatlı (Sabit)",  unit: "KCal/Kg"),
        "3":   NutrientDef(key: "meRuminantFixed",  displayName: "ME Ruminant (Sabit)", unit: "KCal/Kg"),
    ]
}

// MARK: - Public accessor for the code map

extension AlapalaFormulaParser {
    static var codeMap: [String: NutrientDef] { alapalaCodeMap }
}
