import UIKit
import Foundation

// MARK: - Thread-safe data snapshot

struct FormulaSnapshot: @unchecked Sendable {
    struct LibEntry: @unchecked Sendable {
        let code: String
        let priceTL: Double?
        let dryMatter: Double?;    let crudeProtein: Double?
        let crudeFat: Double?;     let crudeFiber: Double?
        let crudeAsh: Double?;     let starch: Double?
        let ndf: Double?;          let nel: Double?
        let calcium: Double?;      let phosphorus: Double?
        let lysine: Double?;       let methionine: Double?
    }

    let code: String;        let name: String;     let totalKg: Double
    let createdAt: Date;     let updatedAt: Date;  let costTL: Double
    let ingredients: [BFIngredient]
    let constraints: [BFConstraint]
    let libMap: [String: LibEntry]

    static func make(formula: BlendFormula, library: [FeedIngredient]) -> FormulaSnapshot {
        let map = Dictionary(
            library.map { i in
                (i.code, LibEntry(
                    code: i.code, priceTL: i.priceTL,
                    dryMatter: i.dryMatter, crudeProtein: i.crudeProtein,
                    crudeFat: i.crudeFat, crudeFiber: i.crudeFiber,
                    crudeAsh: i.crudeAsh, starch: i.starch,
                    ndf: i.ndf, nel: i.nel,
                    calcium: i.calcium, phosphorus: i.phosphorus,
                    lysine: i.lysine, methionine: i.methionine))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let cost = formula.currentCostTL > 0 ? formula.currentCostTL : formula.recordedCostTL
        return FormulaSnapshot(
            code: formula.code, name: formula.name, totalKg: formula.totalKg,
            createdAt: formula.createdAt, updatedAt: formula.updatedAt, costTL: cost,
            ingredients: formula.ingredients, constraints: formula.constraints, libMap: map)
    }

    var activeIngredients: [BFIngredient] {
        ingredients
            .filter { $0.isActive && $0.mixPct > 0.001 }
            .sorted { $0.mixPct > $1.mixPct }
    }
    var allConstraints: [BFConstraint]    { constraints }
    func lib(_ code: String) -> LibEntry? { libMap[code] }
}

// MARK: - Shared PDF canvas

final class BornPDFCanvas {
    let W: CGFloat; let H: CGFloat; let M: CGFloat = 36
    var CW: CGFloat { W - 2 * M }
    let blue    = UIColor(red: 0.00, green: 0.20, blue: 0.50, alpha: 1)
    let blueHdr = UIColor(red: 0.83, green: 0.90, blue: 0.97, alpha: 1)
    let altRow  = UIColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 1)
    private(set) var y: CGFloat = 36
    private weak var ctx: UIGraphicsPDFRendererContext?

    init(landscape: Bool = false) { W = landscape ? 841.8 : 595.2; H = landscape ? 595.2 : 841.8 }

    func render(_ block: (BornPDFCanvas) -> Void) -> Data {
        let r = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: W, height: H))
        return r.pdfData { c in self.ctx = c; c.beginPage(); self.y = M; block(self) }
    }

    func newPage()               { ctx?.beginPage(); y = M }
    func checkPage(_ h: CGFloat) { if y + h > H - M { newPage() } }
    func space(_ h: CGFloat = 8) { y += h }
    func fillR(_ r: CGRect, _ c: UIColor) { c.setFill(); UIRectFill(r) }

    func drawText(_ text: String, in rect: CGRect,
                  size: CGFloat, weight: UIFont.Weight,
                  color: UIColor = .black, align: NSTextAlignment = .left) {
        let ps = NSMutableParagraphStyle(); ps.alignment = align; ps.lineBreakMode = .byTruncatingTail
        let a: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: ps]
        NSAttributedString(string: text, attributes: a).draw(in: rect)
    }

    func banner(title: String, subtitle: String = "") {
        fillR(CGRect(x: 0, y: 0, width: W, height: 50), blue)
        drawText(title,    in: CGRect(x: M,          y: 13, width: CW * 0.75, height: 26), size: 14, weight: .bold,    color: .white)
        drawText(subtitle, in: CGRect(x: M + CW*0.75, y: 16, width: CW * 0.23, height: 20), size: 12, weight: .semibold, color: UIColor(white: 1, alpha: 0.7), align: .right)
        y = 58
    }

    func metaBox(_ pairs: [(String, String)]) {
        let rowH: CGFloat = 18; let rows = Int(ceil(Double(pairs.count) / 2.0))
        let boxH = CGFloat(rows) * rowH + 16
        fillR(CGRect(x: M, y: y, width: CW, height: boxH), UIColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1))
        let halfW = CW / 2
        for (i, (lbl, val)) in pairs.enumerated() {
            let col = CGFloat(i % 2); let row = CGFloat(i / 2)
            let rx = M + col * halfW + 6; let ry = y + 8 + row * rowH
            drawText(lbl, in: CGRect(x: rx, y: ry, width: 84, height: 14), size: 8, weight: .semibold, color: blue)
            drawText(val, in: CGRect(x: rx + 88, y: ry, width: halfW - 98, height: 14), size: 8, weight: .regular)
        }
        y += boxH + 4
    }

    func sectionHeader(_ title: String) {
        checkPage(22)
        fillR(CGRect(x: M, y: y, width: CW, height: 18), blue)
        drawText(title, in: CGRect(x: M + 6, y: y + 3, width: CW - 8, height: 13), size: 8.5, weight: .bold, color: .white)
        y += 18
    }

    func tableHeader(_ cols: [(String, CGFloat)]) {
        fillR(CGRect(x: M, y: y, width: CW, height: 14), blueHdr)
        var x: CGFloat = M + 2
        for (t, w) in cols { drawText(t, in: CGRect(x: x, y: y + 2, width: w - 3, height: 11), size: 7, weight: .semibold, color: blue); x += w }
        y += 14
    }

    func tableRow(_ cells: [String], _ cols: [(String, CGFloat)], idx: Int, rowColors: [UIColor]? = nil) {
        checkPage(12)
        if idx % 2 == 0 { fillR(CGRect(x: M, y: y, width: CW, height: 12), altRow) }
        var x: CGFloat = M + 2
        for (ci, (_, w)) in cols.enumerated() {
            guard ci < cells.count else { break }
            drawText(cells[ci], in: CGRect(x: x, y: y + 2, width: w - 3, height: 10), size: 7, weight: .regular, color: rowColors?[ci] ?? .black)
            x += w
        }
        y += 12
    }

    func tableTotalRow(_ cells: [String], _ cols: [(String, CGFloat)]) {
        checkPage(14)
        fillR(CGRect(x: M, y: y, width: CW, height: 14), blueHdr)
        var x: CGFloat = M + 2
        for (ci, (_, w)) in cols.enumerated() {
            guard ci < cells.count else { break }
            drawText(cells[ci], in: CGRect(x: x, y: y + 2, width: w - 3, height: 11), size: 7.5, weight: .bold, color: blue)
            x += w
        }
        y += 14
    }

    func footer() {
        y += 6; checkPage(14)
        UIColor(white: 0.8, alpha: 1).setFill(); UIRectFill(CGRect(x: M, y: y, width: CW, height: 0.5)); y += 4
        let df = DateFormatter(); df.locale = Locale(identifier: "tr_TR"); df.dateStyle = .short; df.timeStyle = .short
        drawText("Oluşturulma: \(df.string(from: Date()))  •  BORN OTOMASYON",
                 in: CGRect(x: M, y: y, width: CW, height: 12), size: 7, weight: .regular, color: .gray, align: .right)
    }
}

// MARK: - FormulaExportService

struct FormulaExportService {
    let snap: FormulaSnapshot

    // MARK: TXT

    func generateTXT() -> String {
        let df = makeDf(style: .medium); let dfS = makeDf(style: .short, time: true)
        var lines: [String] = []
        lines.append("════════════════════════════════════════════════════════")
        lines.append("          BORN OTOMASYON — FORMÜL RAPORU")
        lines.append("════════════════════════════════════════════════════════")
        lines.append("")
        lines.append("Kod              : \(snap.code)")
        lines.append("Ad               : \(snap.name)")
        lines.append("Formülasyon T.   : \(df.string(from: snap.createdAt))")
        lines.append("Son Güncelleme   : \(df.string(from: snap.updatedAt))")
        lines.append("Parti Büyüklüğü  : \(Int(snap.totalKg)) kg")
        if snap.costTL > 0 { lines.append("Maliyet          : \(f2(snap.costTL)) TL/ton") }

        lines.append("")
        lines.append("────────────────────────────────────────────────────────")
        lines.append("HAMMADDE KULLANIM MİKTARLARI")
        lines.append("────────────────────────────────────────────────────────")
        lines.append(pad("Hammadde", 30) + col("Min%", 7) + col("Max%", 7) + col("Mix%", 7) + col("Kg", 9))
        lines.append(String(repeating: "─", count: 63))

        for ing in snap.activeIngredients {
            let kg = ing.mixPct / 100.0 * snap.totalKg
            let minS = ing.minPct > 0 ? f1(ing.minPct) : "—"
            let maxS = ing.maxPct < 99.9 ? f1(ing.maxPct) : "—"
            let mixS = ing.mixPct > 0.001 ? f2(ing.mixPct) : "—"
            let kgS  = ing.mixPct > 0.001 ? f1(kg) : "—"
            lines.append(pad(ing.name, 30) + col(minS, 7) + col(maxS, 7) + col(mixS, 7) + col(kgS, 9))
        }

        if !snap.allConstraints.isEmpty {
            lines.append("")
            lines.append("────────────────────────────────────────────────────────")
            lines.append("BESİN DEĞERLERİ / KRİTERLER")
            lines.append("────────────────────────────────────────────────────────")
            lines.append(pad("Besin Maddesi", 32) + col("Min", 10) + col("Max", 10) + col("Sonuç", 10))
            lines.append(String(repeating: "─", count: 65))
            for c in snap.allConstraints {
                let minS = c.minValue.map { f3($0) } ?? "—"
                let maxS = c.maxValue.map { f3($0) } ?? "—"
                let curS = c.currentValue.map { f3($0) } ?? "—"
                lines.append(pad(c.resolvedDisplayName, 32) + col(minS, 10) + col(maxS, 10) + col(curS, 10))
            }
        }

        lines.append("")
        lines.append("════════════════════════════════════════════════════════")
        lines.append("Rapor: \(dfS.string(from: Date()))  •  BORN OTOMASYON")
        lines.append("════════════════════════════════════════════════════════")
        return lines.joined(separator: "\n")
    }

    // MARK: CSV

    func generateCSV() -> String {
        let df = makeDf(style: .medium); let dfS = makeDf(style: .short, time: true)
        var rows: [String] = []
        func row(_ cells: String...) { rows.append(cells.map(csvCell).joined(separator: ";")) }

        row("BORN OTOMASYON — FORMÜL RAPORU")
        row("Kod", snap.code); row("Ad", snap.name)
        row("Tarih", df.string(from: snap.createdAt))
        row("Parti (kg)", f0(snap.totalKg))
        if snap.costTL > 0 { row("Maliyet (TL/ton)", f2(snap.costTL)) }

        row(""); row("HAMMADDE KULLANIM MİKTARLARI")
        row("Kod", "Ad", "Min%", "Max%", "Mix%", "Miktar (kg)", "Fiyat TL/ton", "Tutar TL")
        for ing in snap.activeIngredients {
            let kg    = ing.mixPct / 100.0 * snap.totalKg
            let price = snap.lib(ing.code)?.priceTL ?? 0
            let tutar = (price / 1000.0) * kg
            row(ing.code, ing.name,
                ing.minPct > 0     ? f2(ing.minPct) : "",
                ing.maxPct < 99.9  ? f2(ing.maxPct) : "",
                ing.mixPct > 0.001 ? f4(ing.mixPct) : "",
                ing.mixPct > 0.001 ? f2(kg) : "",
                price > 0          ? f0(price) : "",
                (price > 0 && ing.mixPct > 0.001) ? f2(tutar) : "")
        }

        if !snap.allConstraints.isEmpty {
            row(""); row("BESİN DEĞERLERİ KRİTERLERİ")
            row("Besin Maddesi", "Min", "Max", "Hesaplanan")
            for c in snap.allConstraints {
                row(c.resolvedDisplayName,
                    c.minValue.map    { f4($0) } ?? "",
                    c.maxValue.map    { f4($0) } ?? "",
                    c.currentValue.map { f4($0) } ?? "")
            }
        }

        row(""); row("Rapor", dfS.string(from: Date())); row("BORN OTOMASYON")
        return rows.joined(separator: "\n")
    }

    // MARK: PDF

    func generatePDF() -> Data {
        let cv = BornPDFCanvas(landscape: false)
        let df = makeDf(style: .medium)

        return cv.render { c in
            c.banner(title: "BORN OTOMASYON — Formül Raporu", subtitle: snap.code)
            c.metaBox([
                ("Kod:", snap.code),
                ("Parti:", "\(Int(snap.totalKg)) kg"),
                ("Ad:", snap.name),
                ("Maliyet:", snap.costTL > 0 ? "\(f2(snap.costTL)) TL/ton" : "—"),
                ("Formülasyon:", df.string(from: snap.createdAt)),
                ("Güncelleme:", df.string(from: snap.updatedAt))
            ])

            let ingCols: [(String, CGFloat)] = [
                ("Kod",52),("Hammadde Adı",138),("Min%",42),("Max%",42),
                ("Mix%",42),("Miktar kg",58),("Fiyat TL/t",60),("Tutar TL",62)]
            c.sectionHeader("HAMMADDE KULLANIM MİKTARLARI")
            c.tableHeader(ingCols)

            var totKg = 0.0; var totMix = 0.0; var totTutar = 0.0
            for (i, ing) in snap.activeIngredients.enumerated() {
                let kg    = ing.mixPct / 100.0 * snap.totalKg
                let price = snap.lib(ing.code)?.priceTL ?? 0
                let tutar = (price / 1000.0) * kg
                totKg += kg; totMix += ing.mixPct
                if price > 0 { totTutar += tutar }
                let minS  = ing.minPct > 0     ? f1(ing.minPct) : "—"
                let maxS  = ing.maxPct < 99.9  ? f1(ing.maxPct) : "—"
                let mixS  = ing.mixPct > 0.001 ? f2(ing.mixPct) : "—"
                let kgS   = ing.mixPct > 0.001 ? f1(kg)         : "—"
                let prS   = price > 0          ? f0(price)       : "—"
                let tuS   = (price > 0 && ing.mixPct > 0.001) ? f2(tutar) : "—"
                c.tableRow([ing.code, ing.name, minS, maxS, mixS, kgS, prS, tuS], ingCols, idx: i)
            }
            c.tableTotalRow(["","TOPLAM","—","—",f2(totMix),f1(totKg),"—",totTutar > 0 ? f2(totTutar):"—"], ingCols)

            if !snap.allConstraints.isEmpty {
                let nutCols: [(String, CGFloat)] = [
                    ("Besin Maddesi",185),("Birim",52),("Min",72),("Max",72),("Hesaplanan",80),("Durum",62)]
                c.sectionHeader("BESİN DEĞERLERİ KRİTERLERİ")
                c.tableHeader(nutCols)
                for (i, con) in snap.allConstraints.enumerated() {
                    let minS = con.minValue.map    { f3($0) } ?? "—"
                    let maxS = con.maxValue.map    { f3($0) } ?? "—"
                    let curS = con.currentValue.map { f3($0) } ?? "—"
                    var st = "—"; var stCol = UIColor.black
                    if let cur = con.currentValue {
                        let okMin = con.minValue.map { cur >= $0 - 1e-4 } ?? true
                        let okMax = con.maxValue.map { cur <= $0 + 1e-4 } ?? true
                        st = (okMin && okMax) ? "✓ Tamam" : "✗ Hata"
                        stCol = (okMin && okMax) ? UIColor(red: 0, green: 0.5, blue: 0, alpha: 1) : .red
                    }
                    c.tableRow([con.resolvedDisplayName,con.unit,minS,maxS,curS,st], nutCols, idx: i,
                               rowColors: [.black,.darkGray,.black,.black,.black,stCol])
                }
            }

            c.footer()
        }
    }

    // MARK: Writers

    func writeTXT() -> URL { write(generateTXT().data(using: .utf8) ?? Data(), ext: "txt") }
    func writeCSV() -> URL {
        var d = Data([0xEF, 0xBB, 0xBF]); d.append(generateCSV().data(using: .utf8) ?? Data())
        return write(d, ext: "csv")
    }
    func writePDF() -> URL { write(generatePDF(), ext: "pdf") }
    private func write(_ data: Data, ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(snap.code)_formul.\(ext)")
        try? data.write(to: url); return url
    }

    // MARK: Format helpers

    private func f0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func f3(_ v: Double) -> String { String(format: "%.3f", v) }
    private func f4(_ v: Double) -> String { String(format: "%.4f", v) }
    private func opt2(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "—" }
    private func opt3(_ v: Double?) -> String { v.map { String(format: "%.3f", $0) } ?? "—" }
    private func csvCell(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }

    private func pad(_ s: String, _ n: Int) -> String {
        let t = String(s.prefix(n))
        return t + String(repeating: " ", count: max(0, n - t.count))
    }
    private func col(_ s: String, _ w: Int) -> String {
        let t = String(s.prefix(w))
        return String(repeating: " ", count: max(0, w - t.count)) + t
    }

    private func makeDf(style: DateFormatter.Style, time: Bool = false) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateStyle = style; f.timeStyle = time ? .short : .none; return f
    }
}
