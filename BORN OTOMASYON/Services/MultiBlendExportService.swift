import UIKit
import Foundation
import Combine

// MARK: - Report Settings (persisted in UserDefaults)

final class ReportSettings: ObservableObject {
    static let shared = ReportSettings()
    private init() {}
    private let ud = UserDefaults.standard

    enum IngSort: String, CaseIterable, Identifiable {
        case usageDesc    = "Kullanım Miktarı ↓ (Büyükten Küçüğe)"
        case usageAsc     = "Kullanım Miktarı ↑ (Küçükten Büyüğe)"
        case alphabetical = "Alfabetik (A–Z)"
        var id: String { rawValue }
    }

    // MARK: Sort
    var sortSharedBy: IngSort {
        get { IngSort(rawValue: ud.string(forKey: "rpt.sortShared") ?? "") ?? .usageDesc }
        set { ud.set(newValue.rawValue, forKey: "rpt.sortShared"); objectWillChange.send() }
    }
    var sortFormulaBy: IngSort {
        get { IngSort(rawValue: ud.string(forKey: "rpt.sortFormula") ?? "") ?? .usageDesc }
        set { ud.set(newValue.rawValue, forKey: "rpt.sortFormula"); objectWillChange.send() }
    }

    // MARK: Column visibility (default: all visible)
    var show1000kg: Bool {
        get { ud.object(forKey: "rpt.show1000kg") == nil ? true : ud.bool(forKey: "rpt.show1000kg") }
        set { ud.set(newValue, forKey: "rpt.show1000kg"); objectWillChange.send() }
    }
    var showKgDay: Bool {
        get { ud.object(forKey: "rpt.showKgDay") == nil ? true : ud.bool(forKey: "rpt.showKgDay") }
        set { ud.set(newValue, forKey: "rpt.showKgDay"); objectWillChange.send() }
    }
    var showMinMax: Bool {
        get { ud.object(forKey: "rpt.showMinMax") == nil ? true : ud.bool(forKey: "rpt.showMinMax") }
        set { ud.set(newValue, forKey: "rpt.showMinMax"); objectWillChange.send() }
    }
    var showPrice: Bool {
        get { ud.object(forKey: "rpt.showPrice") == nil ? true : ud.bool(forKey: "rpt.showPrice") }
        set { ud.set(newValue, forKey: "rpt.showPrice"); objectWillChange.send() }
    }
    var showCost: Bool {
        get { ud.object(forKey: "rpt.showCost") == nil ? true : ud.bool(forKey: "rpt.showCost") }
        set { ud.set(newValue, forKey: "rpt.showCost"); objectWillChange.send() }
    }
    var showCostPct: Bool {
        get { ud.object(forKey: "rpt.showCostPct") == nil ? true : ud.bool(forKey: "rpt.showCostPct") }
        set { ud.set(newValue, forKey: "rpt.showCostPct"); objectWillChange.send() }
    }

    // MARK: Hidden nutrients (stored as ‖-joined display names)
    var hiddenNutrients: Set<String> {
        get { Set((ud.string(forKey: "rpt.hiddenNutrients") ?? "").split(separator: "‖").map(String.init).filter { !$0.isEmpty }) }
        set { ud.set(newValue.sorted().joined(separator: "‖"), forKey: "rpt.hiddenNutrients"); objectWillChange.send() }
    }
    func isNutrientVisible(_ name: String) -> Bool { !hiddenNutrients.contains(name) }
    func toggleNutrient(_ name: String) {
        var h = hiddenNutrients
        if h.contains(name) { h.remove(name) } else { h.insert(name) }
        hiddenNutrients = h
    }

    func resetToDefaults() {
        sortSharedBy     = .usageDesc
        sortFormulaBy    = .usageDesc
        show1000kg       = true
        showKgDay        = true
        showMinMax       = true
        showPrice        = true
        showCost         = true
        showCostPct      = true
        hiddenNutrients  = []
    }
}

// MARK: - Report Config (thread-safe snapshot of settings)

struct ReportConfig: Sendable {
    let sortSharedBy:    ReportSettings.IngSort
    let sortFormulaBy:   ReportSettings.IngSort
    let show1000kg:      Bool
    let showKgDay:       Bool
    let showMinMax:      Bool
    let showPrice:       Bool
    let showCost:        Bool
    let showCostPct:     Bool
    let hiddenNutrients: Set<String>

    func isNutrientVisible(_ name: String) -> Bool { !hiddenNutrients.contains(name) }

    static func current() -> ReportConfig {
        let s = ReportSettings.shared
        return ReportConfig(
            sortSharedBy:    s.sortSharedBy,
            sortFormulaBy:   s.sortFormulaBy,
            show1000kg:      s.show1000kg,
            showKgDay:       s.showKgDay,
            showMinMax:      s.showMinMax,
            showPrice:       s.showPrice,
            showCost:        s.showCost,
            showCostPct:     s.showCostPct,
            hiddenNutrients: s.hiddenNutrients
        )
    }
}

// MARK: - Thread-safe MultiBlend snapshot

struct MultiBlendSnapshot: @unchecked Sendable {
    struct FormulaEntry: @unchecked Sendable {
        let code:           String
        let name:           String
        let totalKg:        Double
        let costTL:         Double
        let productionTons: Double
        let ingredients:    [BFIngredient]
        let constraints:    [BFConstraint]
    }

    let groupName:  String
    let entries:    [FormulaEntry]
    let ingLimits:  [String: MonthlyIngLimit]
    let libMap:     [String: FormulaSnapshot.LibEntry]

    // MARK: Factory — call on @MainActor

    static func make(group: MultiBlendGroup,
                     selectedCodes: [String],
                     allFormulas: [BlendFormula],
                     library: [FeedIngredient]) -> MultiBlendSnapshot {
        let libMap = Dictionary(
            library.map { ing in
                (ing.code, FormulaSnapshot.LibEntry(
                    code: ing.code, priceTL: ing.priceTL,
                    dryMatter: ing.dryMatter, crudeProtein: ing.crudeProtein,
                    crudeFat: ing.crudeFat, crudeFiber: ing.crudeFiber,
                    crudeAsh: ing.crudeAsh, starch: ing.starch,
                    ndf: ing.ndf, nel: ing.nel,
                    calcium: ing.calcium, phosphorus: ing.phosphorus,
                    lysine: ing.lysine, methionine: ing.methionine
                ))
            },
            uniquingKeysWith: { first, _ in first }
        )

        let entries: [FormulaEntry] = selectedCodes.compactMap { code in
            guard let f = allFormulas.first(where: { $0.code == code }) else { return nil }
            let cost = f.currentCostTL > 0 ? f.currentCostTL : f.recordedCostTL
            return FormulaEntry(
                code: f.code, name: f.name, totalKg: f.totalKg, costTL: cost,
                productionTons: group.productionTons[f.code] ?? 0,
                ingredients: f.ingredients, constraints: f.constraints
            )
        }

        return MultiBlendSnapshot(
            groupName: group.name,
            entries: entries,
            ingLimits: group.monthlyIngLimits,
            libMap: libMap
        )
    }

    // MARK: Helpers

    func lib(_ code: String) -> FormulaSnapshot.LibEntry? { libMap[code] }

    // Returns unique active ingredients in insertion order (sorting done by ExportService based on config)
    var combinedIngredients: [(code: String, name: String)] {
        var seen = Set<String>()
        var result: [(code: String, name: String)] = []
        for e in entries {
            for ing in e.ingredients where ing.isActive {
                if seen.insert(ing.code).inserted {
                    result.append((code: ing.code, name: ing.name))
                }
            }
        }
        return result
    }

    func usageKg(ingCode: String, entry: FormulaEntry) -> Double {
        let pct = entry.ingredients.first { $0.code == ingCode }?.mixPct ?? 0
        return pct / 100.0 * entry.productionTons * 1000.0
    }

    func usageTons(ingCode: String, entry: FormulaEntry) -> Double {
        let pct = entry.ingredients.first { $0.code == ingCode }?.mixPct ?? 0
        return pct / 100.0 * entry.productionTons
    }

    func totalUsageTons(ingCode: String) -> Double {
        entries.reduce(0.0) { acc, e in acc + usageTons(ingCode: ingCode, entry: e) }
    }

    func totalUsageKg(ingCode: String) -> Double {
        entries.reduce(0.0) { acc, e in acc + usageKg(ingCode: ingCode, entry: e) }
    }

    var totalProductionTons: Double { entries.map(\.productionTons).reduce(0, +) }
}

// MARK: - MultiBlendExportService (thread-safe)

struct MultiBlendExportService {
    let snap:   MultiBlendSnapshot
    let config: ReportConfig

    init(snap: MultiBlendSnapshot, config: ReportConfig = .current()) {
        self.snap   = snap
        self.config = config
    }

    // MARK: - Sorting helpers

    private func sortedSharedIngs() -> [(code: String, name: String)] {
        switch config.sortSharedBy {
        case .usageDesc:
            return snap.combinedIngredients.sorted { snap.totalUsageTons(ingCode: $0.code) > snap.totalUsageTons(ingCode: $1.code) }
        case .usageAsc:
            return snap.combinedIngredients.sorted { snap.totalUsageTons(ingCode: $0.code) < snap.totalUsageTons(ingCode: $1.code) }
        case .alphabetical:
            return snap.combinedIngredients.sorted { $0.name < $1.name }
        }
    }

    private func sortedFormulaIngs(for entry: MultiBlendSnapshot.FormulaEntry) -> [BFIngredient] {
        let base = entry.ingredients.filter { $0.isActive && $0.mixPct > 0.001 }
        switch config.sortFormulaBy {
        case .usageDesc:
            return base.sorted { snap.usageKg(ingCode: $0.code, entry: entry) > snap.usageKg(ingCode: $1.code, entry: entry) }
        case .usageAsc:
            return base.sorted { snap.usageKg(ingCode: $0.code, entry: entry) < snap.usageKg(ingCode: $1.code, entry: entry) }
        case .alphabetical:
            return base.sorted { $0.name < $1.name }
        }
    }

    private func visibleConstraints(for entry: MultiBlendSnapshot.FormulaEntry) -> [BFConstraint] {
        entry.constraints.filter { config.isNutrientVisible($0.resolvedDisplayName) }
    }

    // MARK: - TXT

    func generateTXT() -> String {
        let df = Self.df()
        let dfS = Self.dfShort()
        var lines: [String] = [
            "════════════════════════════════════════════════════════════",
            "         BORN OTOMASYON — MULTİBLEND GRUP RAPORU",
            "════════════════════════════════════════════════════════════",
            "",
            "Grup Adı         : \(snap.groupName)",
            "Rapor Tarihi     : \(df.string(from: Date()))",
            "Seçili Formül    : \(snap.entries.count)",
            String(format: "Toplam Üretim    : %.1f ton/ay", snap.totalProductionTons),
            ""
        ]

        // Shared ingredient table
        lines += [
            divider("ORTAK HAMMADDE AYLIK KARIŞIM KULLANIMI"),
            pad("KOD", 8) + pad("HAMMADDE", 32) + col("KARIŞIM (ton)", 16) + col("FİYAT (TL/t)", 16) + col("TOPLAM MALİYET", 18) + col("%", 8),
            String(repeating: "─", count: 100)
        ]
        var grandCost = 0.0
        var grandTons = 0.0
        var sharedItems: [(code: String, name: String, tons: Double, price: Double, cost: Double)] = []
        for (code, name) in sortedSharedIngs() {
            let tons  = snap.totalUsageTons(ingCode: code)
            let price = snap.lib(code)?.priceTL ?? 0
            let cost  = price > 0 ? tons * price : 0
            grandCost += cost
            grandTons += tons
            sharedItems.append((code, name, tons, price, cost))
        }
        for item in sharedItems {
            let priceS = item.price > 0 ? fmtTL(item.price) : "—"
            let costS  = item.cost  > 0 ? fmtTL(item.cost)  : "—"
            let pct    = grandCost > 0 ? item.cost / grandCost * 100 : 0
            let pctS   = pct > 0 ? f1(pct) + "%" : "—"
            lines.append(pad(item.code, 8) + pad(item.name, 32) + col(f2(item.tons), 16) + col(priceS, 16) + col(costS, 18) + col(pctS, 8))
        }
        lines.append(String(repeating: "─", count: 100))
        lines.append(pad("", 8) + pad("TOPLAM", 32) + col(f2(grandTons), 16) + col("—", 16) + col(grandCost > 0 ? fmtTL(grandCost) : "—", 18) + col("100%", 8))

        // Per-formula detail
        for e in snap.entries {
            let activeIngs = sortedFormulaIngs(for: e)

            // Build dynamic header
            var hdr = pad("HAMMADDE", 28) + col("Mix%", 8)
            if config.show1000kg  { hdr += col("1000kg", 8) }
            if config.showKgDay   { hdr += col("Kg/ay", 10) }
            if config.showMinMax  { hdr += col("Min%", 8) + col("Max%", 8) }
            if config.showPrice   { hdr += col("TL/ton", 12) }
            if config.showCost    { hdr += col("Tutar TL", 14) }
            if config.showCostPct { hdr += col("%Mal.", 8) }

            var divW = 28 + 8
            if config.show1000kg  { divW += 8 }
            if config.showKgDay   { divW += 10 }
            if config.showMinMax  { divW += 16 }
            if config.showPrice   { divW += 12 }
            if config.showCost    { divW += 14 }
            if config.showCostPct { divW += 8 }

            lines += ["", "", divider("[\(e.code)] \(e.name)  —  \(f1(e.productionTons)) ton/ay"), hdr, String(repeating: "─", count: divW)]

            var tutarList: [Double] = []
            var fTutar = 0.0
            for ing in activeIngs {
                let kg    = snap.usageKg(ingCode: ing.code, entry: e)
                let price = snap.lib(ing.code)?.priceTL ?? 0
                let tutar = price > 0 ? kg * price / 1000.0 : 0
                tutarList.append(tutar)
                fTutar += tutar
            }
            for (idx, ing) in activeIngs.enumerated() {
                let kg     = snap.usageKg(ingCode: ing.code, entry: e)
                let price  = snap.lib(ing.code)?.priceTL ?? 0
                let tutar  = tutarList[idx]
                let pct    = fTutar > 0 ? tutar / fTutar * 100 : 0
                var row = pad(ing.name, 28) + col(f2(ing.mixPct), 8)
                if config.show1000kg  { row += col(f1(ing.mixPct * 10), 8) }
                if config.showKgDay   { row += col(f1(kg), 10) }
                if config.showMinMax  {
                    row += col(ing.minPct > 0    ? f1(ing.minPct) : "—", 8)
                    row += col(ing.maxPct < 99.9 ? f1(ing.maxPct) : "—", 8)
                }
                if config.showPrice   { row += col(price > 0 ? fmtTL(price) : "—", 12) }
                if config.showCost    { row += col(tutar > 0 ? fmtTL(tutar) : "—", 14) }
                if config.showCostPct { row += col(pct > 0 ? f1(pct) + "%" : "—", 8) }
                lines.append(row)
            }
            lines.append(String(repeating: "─", count: divW))
            var totRow = pad("TOPLAM", 28) + col("", 8)
            if config.show1000kg  { totRow += col("", 8) }
            if config.showKgDay   { totRow += col("", 10) }
            if config.showMinMax  { totRow += col("", 8) + col("", 8) }
            if config.showPrice   { totRow += col("—", 12) }
            if config.showCost    { totRow += col(fTutar > 0 ? fmtTL(fTutar) : "—", 14) }
            if config.showCostPct { totRow += col("100%", 8) }
            lines.append(totRow)

            let visConst = visibleConstraints(for: e)
            if !visConst.isEmpty {
                lines += ["", "  BESİN DEĞERLERİ KRİTERLERİ:",
                    "  " + pad("Besin Maddesi", 28) + col("Min", 10) + col("Max", 10) + col("Hesaplanan", 12),
                    "  " + String(repeating: "─", count: 62)]
                for c in visConst {
                    lines.append("  " + pad(c.resolvedDisplayName, 28) +
                        col(c.minValue.map { f3($0) } ?? "—", 10) +
                        col(c.maxValue.map { f3($0) } ?? "—", 10) +
                        col(c.currentValue.map { f3($0) } ?? "—", 12))
                }
            }
        }

        lines += ["", "════════════════════════════════════════════════════════════",
            "Rapor: \(dfS.string(from: Date()))  •  BORN OTOMASYON",
            "════════════════════════════════════════════════════════════"]
        return lines.joined(separator: "\n")
    }

    // MARK: - Transfer TXT (cihazlar arası formül aktarımı — Rasyon İçe Aktar ile uyumlu)
    // İnsan-okunur rapordan farklı: kayıpsız, makine tarafından parse edilen format.
    // Her formül kendi bloğunda — isim, kod, tüm hammadde min/max/mix oranları ve
    // besin değeri kriterleri (min/max/hesaplanan) ile birlikte taşınır.

    func generateTransferTXT() -> String {
        var lines: [String] = []
        for e in snap.entries {
            lines.append("@@@FORMUL@@@")
            lines.append("KOD: \(e.code)")
            lines.append("AD: \(e.name)")
            lines.append("TOPLAM_KG: \(e.totalKg)")
            lines.append("HAMMADDE_SAYISI: \(e.ingredients.count)")
            lines.append("---HAMMADDE---")
            lines.append("KOD|AD|AKTIF|MIN|MAX|MIX|URETIM_MIX|FIYAT_TL")
            for ing in e.ingredients {
                let activeStr: String = ing.isActive ? "1" : "0"
                let priceStr:  String = ing.overridePriceTLPerTon.map { String($0) } ?? ""
                let fields: [String] = [
                    ing.code, ing.name, activeStr,
                    String(ing.minPct), String(ing.maxPct), String(ing.mixPct),
                    String(ing.productionMixPct), priceStr
                ]
                lines.append(fields.joined(separator: "|"))
            }
            lines.append("---BESIN---")
            lines.append("ANAHTAR|AD|BIRIM|MIN|MAX|HESAPLANAN")
            for c in e.constraints {
                let minStr: String = c.minValue.map { String($0) } ?? ""
                let maxStr: String = c.maxValue.map { String($0) } ?? ""
                let curStr: String = c.currentValue.map { String($0) } ?? ""
                let fields: [String] = [c.nutrientKey, c.resolvedDisplayName, c.unit, minStr, maxStr, curStr]
                lines.append(fields.joined(separator: "|"))
            }
            lines.append("@@@SON@@@")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - CSV

    func generateCSV() -> String {
        let df  = Self.df()
        let dfS = Self.dfShort()
        var rows: [String] = []

        // Calculate max columns for consistent grid
        var COLS = 2  // Hammadde + Mix% always present
        if config.show1000kg  { COLS += 1 }
        if config.showKgDay   { COLS += 1 }
        if config.showMinMax  { COLS += 2 }
        if config.showPrice   { COLS += 1 }
        if config.showCost    { COLS += 1 }
        if config.showCostPct { COLS += 1 }
        COLS = max(COLS, 6)  // at least as wide as shared table

        func row(_ cells: String...) {
            var padded = cells
            while padded.count < COLS { padded.append("") }
            rows.append(padded.map(csvCell).joined(separator: ";"))
        }

        // Group header
        row("BORN OTOMASYON — MULTİBLEND GRUP RAPORU")
        row("Grup Adı", snap.groupName)
        row("Rapor Tarihi", df.string(from: Date()))
        row("Seçili Formül", "\(snap.entries.count)")
        row("Toplam Üretim (ton/ay)", csvNum(snap.totalProductionTons, 1))

        // Shared ingredient table
        row()
        row("ORTAK HAMMADDE AYLIK KARIŞIM KULLANIMI")
        row("KOD", "HAMMADDE", "KARIŞIM (ton)", "FİYAT (TL/Ton)", "TOPLAM MALİYET (TL)", "%Maliyet")
        var grandCost = 0.0
        var grandTons = 0.0
        var sharedData: [(code: String, name: String, tons: Double, price: Double, cost: Double)] = []
        for (code, name) in sortedSharedIngs() {
            let tons  = snap.totalUsageTons(ingCode: code)
            let price = snap.lib(code)?.priceTL ?? 0
            let cost  = price > 0 ? tons * price : 0
            grandCost += cost; grandTons += tons
            sharedData.append((code, name, tons, price, cost))
        }
        for item in sharedData {
            let pct  = grandCost > 0 ? item.cost / grandCost * 100 : 0
            row(item.code, item.name, csvNum(item.tons, 2),
                item.price > 0 ? fmtTL(item.price) : "",
                item.cost  > 0 ? fmtTL(item.cost)  : "",
                pct > 0 ? csvNum(pct, 1) + "%" : "")
        }
        row("", "TOPLAM", csvNum(grandTons, 2), "", grandCost > 0 ? fmtTL(grandCost) : "", "100%")

        // Per-formula sections
        for e in snap.entries {
            let activeIngs = sortedFormulaIngs(for: e)
            row(); row()
            row("FORMÜL", "\(e.code) — \(e.name)")
            row("Üretim (ton/ay)", csvNum(e.productionTons, 1))
            if e.costTL > 0 { row("Maliyet (TL/ton)", fmtTL(e.costTL)) }

            row(); row("HAMMADDE KULLANIM ORANLARI")

            // Dynamic header
            var hdrCells = ["Hammadde", "Mix%"]
            if config.show1000kg  { hdrCells.append("1000 kg") }
            if config.showKgDay   { hdrCells.append("Kg/ay") }
            if config.showMinMax  { hdrCells += ["Min%", "Max%"] }
            if config.showPrice   { hdrCells.append("TL/ton") }
            if config.showCost    { hdrCells.append("Tutar TL/ay") }
            if config.showCostPct { hdrCells.append("%Maliyet") }
            row(hdrCells[0], hdrCells[1], hdrCells.count > 2 ? hdrCells[2] : "",
                hdrCells.count > 3 ? hdrCells[3] : "", hdrCells.count > 4 ? hdrCells[4] : "",
                hdrCells.count > 5 ? hdrCells[5] : "", hdrCells.count > 6 ? hdrCells[6] : "",
                hdrCells.count > 7 ? hdrCells[7] : "", hdrCells.count > 8 ? hdrCells[8] : "")

            var tutarList: [Double] = []
            var fTutar = 0.0
            for ing in activeIngs {
                let kg    = snap.usageKg(ingCode: ing.code, entry: e)
                let price = snap.lib(ing.code)?.priceTL ?? 0
                let tutar = price > 0 ? kg * price / 1000.0 : 0
                tutarList.append(tutar); fTutar += tutar
            }
            for (idx, ing) in activeIngs.enumerated() {
                let kg    = snap.usageKg(ingCode: ing.code, entry: e)
                let price = snap.lib(ing.code)?.priceTL ?? 0
                let tutar = tutarList[idx]
                let pct   = fTutar > 0 ? tutar / fTutar * 100 : 0
                var cells = [ing.name, csvNum(ing.mixPct, 2)]
                if config.show1000kg  { cells.append(csvNum(ing.mixPct * 10, 1)) }
                if config.showKgDay   { cells.append(csvNum(kg, 1)) }
                if config.showMinMax  {
                    cells.append(ing.minPct > 0    ? csvNum(ing.minPct, 1) : "")
                    cells.append(ing.maxPct < 99.9 ? csvNum(ing.maxPct, 1) : "")
                }
                if config.showPrice   { cells.append(price > 0 ? fmtTL(price) : "") }
                if config.showCost    { cells.append(tutar > 0 ? fmtTL(tutar) : "") }
                if config.showCostPct { cells.append(pct > 0 ? csvNum(pct, 1) + "%" : "") }
                row(cells[0], cells[1],
                    cells.count > 2 ? cells[2] : "", cells.count > 3 ? cells[3] : "",
                    cells.count > 4 ? cells[4] : "", cells.count > 5 ? cells[5] : "",
                    cells.count > 6 ? cells[6] : "", cells.count > 7 ? cells[7] : "",
                    cells.count > 8 ? cells[8] : "")
            }
            var totCells = ["TOPLAM", ""]
            if config.show1000kg  { totCells.append("") }
            if config.showKgDay   { totCells.append("") }
            if config.showMinMax  { totCells += ["", ""] }
            if config.showPrice   { totCells.append("") }
            if config.showCost    { totCells.append(fTutar > 0 ? fmtTL(fTutar) : "") }
            if config.showCostPct { totCells.append("100%") }
            row(totCells[0], totCells[1],
                totCells.count > 2 ? totCells[2] : "", totCells.count > 3 ? totCells[3] : "",
                totCells.count > 4 ? totCells[4] : "", totCells.count > 5 ? totCells[5] : "",
                totCells.count > 6 ? totCells[6] : "", totCells.count > 7 ? totCells[7] : "",
                totCells.count > 8 ? totCells[8] : "")

            let visConst = visibleConstraints(for: e)
            if !visConst.isEmpty {
                row(); row("BESİN DEĞERLERİ KRİTERLERİ")
                row("Besin Maddesi", "Min", "Max", "Hesaplanan")
                for c in visConst {
                    row(c.resolvedDisplayName,
                        c.minValue.map     { csvNum($0, 3) } ?? "",
                        c.maxValue.map     { csvNum($0, 3) } ?? "",
                        c.currentValue.map { csvNum($0, 3) } ?? "")
                }
            }
        }

        row(); row("Rapor", dfS.string(from: Date())); row("BORN OTOMASYON")
        return rows.joined(separator: "\r\n")
    }

    // MARK: - PDF (landscape A4)

    func generatePDF() -> Data {
        let cv = BornPDFCanvas(landscape: true)
        let df = Self.df()

        return cv.render { c in

            // ── Page 1: Shared ingredient usage ──────────────────────────
            c.banner(title: "BORN OTOMASYON — MultiBlend Grup Raporu", subtitle: snap.groupName)
            c.metaBox([
                ("Grup Adı:",       snap.groupName),
                ("Formül Sayısı:",  "\(snap.entries.count)"),
                ("Rapor Tarihi:",   df.string(from: Date())),
                ("Toplam Üretim:", "\(f1(snap.totalProductionTons)) ton/ay"),
                ("", ""), ("", "")
            ])

            let ingCols: [(String, CGFloat)] = [
                ("KOD", 45), ("HAMMADDE", 185), ("KARIŞIM (ton)", 90),
                ("FİYAT (TL/ton)", 100), ("TOPLAM MALİYET (TL)", 110), ("%Maliyet", 60)
            ]
            c.sectionHeader("ORTAK HAMMADDE AYLIK KARIŞIM KULLANIMI")
            c.tableHeader(ingCols)

            var grandCost = 0.0
            var grandTons = 0.0
            var sharedItems: [(code: String, name: String, tons: Double, price: Double, cost: Double)] = []
            for (code, name) in sortedSharedIngs() {
                let tons  = snap.totalUsageTons(ingCode: code)
                let price = snap.lib(code)?.priceTL ?? 0
                let cost  = price > 0 ? tons * price : 0
                grandCost += cost; grandTons += tons
                sharedItems.append((code, name, tons, price, cost))
            }
            for (i, item) in sharedItems.enumerated() {
                let priceS = item.price > 0 ? fmtTL(item.price) : "—"
                let costS  = item.cost  > 0 ? fmtTL(item.cost)  : "—"
                let pct    = grandCost > 0 ? item.cost / grandCost * 100 : 0
                let pctS   = pct > 0 ? f1(pct) + "%" : "—"
                c.tableRow([item.code, item.name, f2(item.tons), priceS, costS, pctS], ingCols, idx: i)
            }
            c.tableTotalRow(["", "TOPLAM", f2(grandTons), "—", grandCost > 0 ? fmtTL(grandCost) : "—", "100%"], ingCols)
            c.footer()

            // ── Per-formula pages ─────────────────────────────────────────
            for e in snap.entries {
                let actIngs = sortedFormulaIngs(for: e)
                guard !actIngs.isEmpty else { continue }

                c.newPage()
                let costHdr = e.costTL > 0 ? "  |  \(fmtTL(e.costTL)) TL/ton" : ""
                c.banner(title: "[\(e.code)]  \(e.name)",
                         subtitle: "\(f1(e.productionTons)) ton/ay\(costHdr)")

                var tutarList: [Double] = []
                var fTutar = 0.0
                for ing in actIngs {
                    let kg    = snap.usageKg(ingCode: ing.code, entry: e)
                    let price = snap.lib(ing.code)?.priceTL ?? 0
                    let tutar = price > 0 ? kg * price / 1000.0 : 0
                    tutarList.append(tutar); fTutar += tutar
                }

                // Dynamic column definitions
                var detCols: [(String, CGFloat)] = [("Hammadde", 145), ("Mix%", 42)]
                if config.show1000kg  { detCols.append(("1000 kg", 52)) }
                if config.showKgDay   { detCols.append(("Kg/ay", 55)) }
                if config.showMinMax  { detCols += [("Min%", 35), ("Max%", 35)] }
                if config.showPrice   { detCols.append(("TL/ton", 68)) }
                if config.showCost    { detCols.append(("Tutar TL/ay", 80)) }
                if config.showCostPct { detCols.append(("%Maliyet", 52)) }

                c.sectionHeader("HAMMADDE KULLANIM ORANLARI  —  \(snap.groupName)")
                c.tableHeader(detCols)

                var totMix = 0.0; var totKg = 0.0
                for (i, ing) in actIngs.enumerated() {
                    let kg     = snap.usageKg(ingCode: ing.code, entry: e)
                    let price  = snap.lib(ing.code)?.priceTL ?? 0
                    let tutar  = tutarList[i]
                    totMix += ing.mixPct; totKg += kg
                    var vals: [String] = [ing.name, f2(ing.mixPct)]
                    if config.show1000kg  { vals.append(f1(ing.mixPct * 10)) }
                    if config.showKgDay   { vals.append(f1(kg)) }
                    if config.showMinMax  {
                        vals.append(ing.minPct > 0    ? f1(ing.minPct) : "—")
                        vals.append(ing.maxPct < 99.9 ? f1(ing.maxPct) : "—")
                    }
                    if config.showPrice   { vals.append(price > 0 ? fmtTL(price) : "—") }
                    if config.showCost    { vals.append(tutar > 0 ? fmtTL(tutar) : "—") }
                    if config.showCostPct {
                        let pct = fTutar > 0 ? tutar / fTutar * 100 : 0
                        vals.append(pct > 0 ? f1(pct) + "%" : "—")
                    }
                    c.tableRow(vals, detCols, idx: i)
                }
                var totVals: [String] = ["TOPLAM", f2(totMix)]
                if config.show1000kg  { totVals.append("") }
                if config.showKgDay   { totVals.append(f1(totKg)) }
                if config.showMinMax  { totVals += ["", ""] }
                if config.showPrice   { totVals.append("—") }
                if config.showCost    { totVals.append(fTutar > 0 ? fmtTL(fTutar) : "—") }
                if config.showCostPct { totVals.append("100%") }
                c.tableTotalRow(totVals, detCols)

                let visConst = visibleConstraints(for: e)
                if !visConst.isEmpty {
                    c.space(10)
                    c.sectionHeader("BESİN DEĞERLERİ KRİTERLERİ")
                    let nutCols: [(String, CGFloat)] = [
                        ("Besin Maddesi", 230), ("Min", 90), ("Max", 90), ("Hesaplanan", 100)
                    ]
                    c.tableHeader(nutCols)
                    for (i, con) in visConst.enumerated() {
                        c.tableRow([con.resolvedDisplayName,
                                    con.minValue.map     { f3($0) } ?? "—",
                                    con.maxValue.map     { f3($0) } ?? "—",
                                    con.currentValue.map { f3($0) } ?? "—"],
                                   nutCols, idx: i)
                    }
                }
                c.footer()
            }
        }
    }

    // MARK: - File writers

    func writeTXT() -> URL { write(generateTXT().data(using: .utf8) ?? Data(), ext: "txt") }
    func writeTransferTXT() -> URL {
        write(generateTransferTXT().data(using: .utf8) ?? Data(), ext: "txt", suffix: "_aktarim")
    }
    func writeCSV() -> URL {
        var d = Data([0xEF, 0xBB, 0xBF])
        d.append("sep=;\r\n".data(using: .utf8) ?? Data())
        d.append(generateCSV().data(using: .utf8) ?? Data())
        return write(d, ext: "csv")
    }
    func writePDF() -> URL { write(generatePDF(), ext: "pdf") }

    private func write(_ data: Data, ext: String, suffix: String = "") -> URL {
        let safe = snap.groupName.replacingOccurrences(of: "/", with: "_")
        let url  = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe)_multiblend\(suffix).\(ext)")
        try? data.write(to: url)
        return url
    }

    // MARK: - Helpers

    private func fmtTL(_ v: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.locale = Locale(identifier: "tr_TR")
        nf.maximumFractionDigits = 0
        nf.minimumFractionDigits = 0
        return nf.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    private func csvNum(_ v: Double, _ decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", v).replacingOccurrences(of: ".", with: ",")
    }
    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func f3(_ v: Double) -> String { String(format: "%.3f", v) }
    private func csvCell(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
    private func pad(_ s: String, _ n: Int) -> String {
        let t = String(s.prefix(n)); return t + String(repeating: " ", count: max(0, n - t.count))
    }
    private func col(_ s: String, _ w: Int) -> String {
        let t = String(s.prefix(w)); return String(repeating: " ", count: max(0, w - t.count)) + t
    }
    private func divider(_ title: String) -> String {
        "──── \(title) \(String(repeating: "─", count: max(0, 56 - title.count)))"
    }
    private static func df() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateStyle = .medium; f.timeStyle = .none; return f
    }
    private static func dfShort() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateStyle = .short; f.timeStyle = .short; return f
    }
}
