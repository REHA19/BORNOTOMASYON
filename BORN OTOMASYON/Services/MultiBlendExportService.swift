import UIKit
import Foundation

// MARK: - Thread-safe MultiBlend snapshot

struct MultiBlendSnapshot: @unchecked Sendable {
    struct FormulaEntry: @unchecked Sendable {
        let code:           String
        let name:           String
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
                code: f.code, name: f.name, costTL: cost,
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
        return result.sorted { $0.name < $1.name }
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
    let snap: MultiBlendSnapshot

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

        // Shared ingredient table (KARIŞIM in tons)
        lines += [
            divider("ORTAK HAMMADDE AYLIK KARIŞIM KULLANIMI"),
            pad("KOD", 8) + pad("HAMMADDE", 32) + col("KARIŞIM (ton)", 16) + col("FİYAT (TL/t)", 16) + col("TOPLAM MALİYET", 18) + col("%", 8),
            String(repeating: "─", count: 100)
        ]
        var grandCost = 0.0
        var grandTons = 0.0
        // Pre-calculate costs for percentages
        var sharedCosts: [(code: String, name: String, tons: Double, price: Double, cost: Double)] = []
        for (code, name) in snap.combinedIngredients {
            let tons  = snap.totalUsageTons(ingCode: code)
            let price = snap.lib(code)?.priceTL ?? 0
            let cost  = price > 0 ? tons * price : 0
            grandCost += cost
            grandTons += tons
            sharedCosts.append((code, name, tons, price, cost))
        }
        for item in sharedCosts {
            let priceS = item.price > 0 ? fmtTL(item.price) : "—"
            let costS  = item.cost  > 0 ? fmtTL(item.cost)  : "—"
            let pct    = grandCost > 0 ? item.cost / grandCost * 100 : 0
            let pctS   = pct > 0 ? f1(pct) + "%" : "—"
            lines.append(pad(item.code, 8) + pad(item.name, 32) + col(f2(item.tons), 16) + col(priceS, 16) + col(costS, 18) + col(pctS, 8))
        }
        lines.append(String(repeating: "─", count: 100))
        let totRow = pad("", 8) + pad("TOPLAM", 32) + col(f2(grandTons), 16) + col("—", 16) + col(grandCost > 0 ? fmtTL(grandCost) : "—", 18) + col("100%", 8)
        lines.append(totRow)

        // Per-formula detail
        for e in snap.entries {
            let activeIngs = e.ingredients.filter { $0.isActive && $0.mixPct > 0.001 }
            lines += [
                "", "",
                divider("[\(e.code)] \(e.name)  —  \(f1(e.productionTons)) ton/ay"),
                pad("HAMMADDE", 28) + col("Mix%", 8) + col("Kg/ay", 10) + col("Min%", 8) + col("Max%", 8) + col("TL/ton", 12) + col("Tutar TL", 14) + col("%Mal.", 8),
                String(repeating: "─", count: 98)
            ]
            // Pre-calculate tutars for percentage
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
                let minS   = ing.minPct > 0    ? f1(ing.minPct) : "—"
                let maxS   = ing.maxPct < 99.9 ? f1(ing.maxPct) : "—"
                let priceS = price > 0 ? fmtTL(price) : "—"
                let tutarS = tutar > 0 ? fmtTL(tutar) : "—"
                let pct    = fTutar > 0 ? tutar / fTutar * 100 : 0
                let pctS   = pct > 0 ? f1(pct) + "%" : "—"
                let detRow = pad(ing.name, 28) + col(f2(ing.mixPct), 8) + col(f1(kg), 10) + col(minS, 8) + col(maxS, 8) + col(priceS, 12) + col(tutarS, 14) + col(pctS, 8)
                lines.append(detRow)
            }
            lines.append(String(repeating: "─", count: 98))
            lines.append(pad("TOPLAM", 28) + col("", 8) + col("", 10) + col("", 8) + col("", 8) + col("—", 12) + col(fTutar > 0 ? fmtTL(fTutar) : "—", 14) + col("100%", 8))

            if !e.constraints.isEmpty {
                lines += [
                    "",
                    "  BESİN DEĞERLERİ KRİTERLERİ:",
                    "  " + pad("Besin Maddesi", 28) + col("Min", 10) + col("Max", 10) + col("Hesaplanan", 12),
                    "  " + String(repeating: "─", count: 62)
                ]
                for c in e.constraints {
                    let minS  = c.minValue.map { f3($0) } ?? "—"
                    let maxS  = c.maxValue.map { f3($0) } ?? "—"
                    let curS  = c.currentValue.map { f3($0) } ?? "—"
                    let crow  = "  " + pad(c.resolvedDisplayName, 28) + col(minS, 10) + col(maxS, 10) + col(curS, 12)
                    lines.append(crow)
                }
            }
        }

        lines += [
            "", "════════════════════════════════════════════════════════════",
            "Rapor: \(dfS.string(from: Date()))  •  BORN OTOMASYON",
            "════════════════════════════════════════════════════════════"
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: - CSV

    func generateCSV() -> String {
        let df  = Self.df()
        let dfS = Self.dfShort()
        var rows: [String] = []
        func row(_ cells: String...) { rows.append(cells.map(csvCell).joined(separator: ";")) }

        // Group header
        row("BORN OTOMASYON — MULTİBLEND GRUP RAPORU")
        row("Grup Adı", snap.groupName)
        row("Rapor Tarihi", df.string(from: Date()))
        row("Seçili Formül", "\(snap.entries.count)")
        row("Toplam Üretim (ton/ay)", f1(snap.totalProductionTons))

        // Shared ingredient table
        row(""); row("ORTAK HAMMADDE AYLIK KARIŞIM KULLANIMI")
        row("KOD", "HAMMADDE", "KARIŞIM (ton)", "FİYAT (TL/Ton)", "TOPLAM MALİYET (TL)", "%Maliyet")
        var grandCost = 0.0
        var grandTons = 0.0
        var sharedCosts: [(code: String, name: String, tons: Double, price: Double, cost: Double)] = []
        for (code, name) in snap.combinedIngredients {
            let tons  = snap.totalUsageTons(ingCode: code)
            let price = snap.lib(code)?.priceTL ?? 0
            let cost  = price > 0 ? tons * price : 0
            grandCost += cost
            grandTons += tons
            sharedCosts.append((code, name, tons, price, cost))
        }
        for item in sharedCosts {
            let pct  = grandCost > 0 ? item.cost / grandCost * 100 : 0
            let pctS = pct > 0 ? f1(pct) + "%" : ""
            row(item.code, item.name, f2(item.tons),
                item.price > 0 ? fmtTL(item.price) : "",
                item.cost  > 0 ? fmtTL(item.cost)  : "",
                pctS)
        }
        row("", "TOPLAM", f2(grandTons), "", grandCost > 0 ? fmtTL(grandCost) : "", "100%")

        // Per-formula sections
        for e in snap.entries {
            let activeIngs = e.ingredients.filter { $0.isActive && $0.mixPct > 0.001 }
            row(""); row("")
            row("FORMÜL", "\(e.code) — \(e.name)")
            row("Üretim (ton/ay)", f1(e.productionTons))
            if e.costTL > 0 { row("Maliyet (TL/ton)", fmtTL(e.costTL)) }

            row(""); row("HAMMADDE KULLANIM ORANLARI")
            row("Hammadde", "Mix%", "Kg/ay", "Min%", "Max%", "TL/ton", "Tutar TL/ay", "%Maliyet")

            // Pre-calculate tutars
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
                let kg    = snap.usageKg(ingCode: ing.code, entry: e)
                let price = snap.lib(ing.code)?.priceTL ?? 0
                let tutar = tutarList[idx]
                let pct   = fTutar > 0 ? tutar / fTutar * 100 : 0
                row(ing.name, f2(ing.mixPct), f1(kg),
                    ing.minPct > 0    ? f1(ing.minPct) : "",
                    ing.maxPct < 99.9 ? f1(ing.maxPct) : "",
                    price > 0 ? fmtTL(price) : "",
                    tutar > 0 ? fmtTL(tutar) : "",
                    pct > 0 ? f1(pct) + "%" : "")
            }
            row("TOPLAM", "", "", "", "", "", fTutar > 0 ? fmtTL(fTutar) : "", "100%")

            if !e.constraints.isEmpty {
                row(""); row("BESİN DEĞERLERİ KRİTERLERİ")
                row("Besin Maddesi", "Min", "Max", "Hesaplanan")
                for c in e.constraints {
                    row(c.resolvedDisplayName,
                        c.minValue.map    { f3($0) } ?? "",
                        c.maxValue.map    { f3($0) } ?? "",
                        c.currentValue.map{ f3($0) } ?? "")
                }
            }
        }

        row(""); row("Rapor", dfS.string(from: Date())); row("BORN OTOMASYON")
        return rows.joined(separator: "\n")
    }

    // MARK: - PDF (landscape A4 — 1 page per formula)

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
            for (code, name) in snap.combinedIngredients {
                let tons  = snap.totalUsageTons(ingCode: code)
                let price = snap.lib(code)?.priceTL ?? 0
                let cost  = price > 0 ? tons * price : 0
                grandCost += cost
                grandTons += tons
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
                let actIngs = e.ingredients.filter { $0.isActive && $0.mixPct > 0.001 }
                guard !actIngs.isEmpty else { continue }

                c.newPage()
                let costHdr = e.costTL > 0 ? "  |  \(fmtTL(e.costTL)) TL/ton" : ""
                c.banner(title: "[\(e.code)]  \(e.name)",
                         subtitle: "\(f1(e.productionTons)) ton/ay\(costHdr)")

                // Pre-calculate tutars for percentages
                var tutarList: [Double] = []
                var fTutar = 0.0
                for ing in actIngs {
                    let kg    = snap.usageKg(ingCode: ing.code, entry: e)
                    let price = snap.lib(ing.code)?.priceTL ?? 0
                    let tutar = price > 0 ? kg * price / 1000.0 : 0
                    tutarList.append(tutar)
                    fTutar += tutar
                }

                // Ingredient table
                let detCols: [(String, CGFloat)] = [
                    ("Hammadde", 165), ("Mix%", 45), ("Kg/ay", 60),
                    ("Min%", 40), ("Max%", 40), ("TL/ton", 70), ("Tutar TL/ay", 85), ("%Maliyet", 55)
                ]
                c.sectionHeader("HAMMADDE KULLANIM ORANLARI  —  \(snap.groupName)")
                c.tableHeader(detCols)

                var totMix = 0.0; var totKg = 0.0
                for (i, ing) in actIngs.enumerated() {
                    let kg     = snap.usageKg(ingCode: ing.code, entry: e)
                    let price  = snap.lib(ing.code)?.priceTL ?? 0
                    let tutar  = tutarList[i]
                    totMix += ing.mixPct; totKg += kg
                    let minS   = ing.minPct > 0    ? f1(ing.minPct) : "—"
                    let maxS   = ing.maxPct < 99.9 ? f1(ing.maxPct) : "—"
                    let priceS = price > 0 ? fmtTL(price) : "—"
                    let tutarS = tutar > 0 ? fmtTL(tutar) : "—"
                    let pct    = fTutar > 0 ? tutar / fTutar * 100 : 0
                    let pctS   = pct > 0 ? f1(pct) + "%" : "—"
                    c.tableRow([ing.name, f2(ing.mixPct), f1(kg), minS, maxS, priceS, tutarS, pctS], detCols, idx: i)
                }
                c.tableTotalRow(["TOPLAM", f2(totMix), f1(totKg), "", "", "—",
                                 fTutar > 0 ? fmtTL(fTutar) : "—", "100%"], detCols)

                // Nutritional values
                if !e.constraints.isEmpty {
                    c.space(10)
                    c.sectionHeader("BESİN DEĞERLERİ KRİTERLERİ")
                    let nutCols: [(String, CGFloat)] = [
                        ("Besin Maddesi", 230), ("Min", 90), ("Max", 90), ("Hesaplanan", 100)
                    ]
                    c.tableHeader(nutCols)
                    for (i, con) in e.constraints.enumerated() {
                        let minS = con.minValue.map     { f3($0) } ?? "—"
                        let maxS = con.maxValue.map     { f3($0) } ?? "—"
                        let curS = con.currentValue.map { f3($0) } ?? "—"
                        c.tableRow([con.resolvedDisplayName, minS, maxS, curS], nutCols, idx: i)
                    }
                }
                c.footer()
            }
        }
    }

    // MARK: - File writers

    func writeTXT() -> URL { write(generateTXT().data(using: .utf8) ?? Data(), ext: "txt") }
    func writeCSV() -> URL {
        var d = Data([0xEF, 0xBB, 0xBF])
        d.append(generateCSV().data(using: .utf8) ?? Data())
        return write(d, ext: "csv")
    }
    func writePDF() -> URL { write(generatePDF(), ext: "pdf") }

    private func write(_ data: Data, ext: String) -> URL {
        let safe = snap.groupName.replacingOccurrences(of: "/", with: "_")
        let url  = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe)_multiblend.\(ext)")
        try? data.write(to: url)
        return url
    }

    // MARK: - Helpers

    // Binlik nokta ayracı ile TL formatı (ör: 14.500 / 1.362.170)
    private func fmtTL(_ v: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.locale = Locale(identifier: "tr_TR")
        nf.maximumFractionDigits = 0
        nf.minimumFractionDigits = 0
        return nf.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    private func f0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func f3(_ v: Double) -> String { String(format: "%.3f", v) }
    private func csvCell(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    private func pad(_ s: String, _ n: Int) -> String {
        let t = String(s.prefix(n))
        return t + String(repeating: " ", count: max(0, n - t.count))
    }
    private func col(_ s: String, _ w: Int) -> String {
        let t = String(s.prefix(w))
        return String(repeating: " ", count: max(0, w - t.count)) + t
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
