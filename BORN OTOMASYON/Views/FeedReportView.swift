import SwiftUI
import SwiftData
import UIKit

// MARK: - Row types

private struct IngRow: Identifiable {
    let id:            String
    let code:          String
    let name:          String
    let usageTons:     Double
    let priceTLPerTon: Double?

    var subtotalTL: Double? {
        guard let p = priceTLPerTon, p > 0, usageTons > 0.001 else { return nil }
        return usageTons * p
    }
}

private struct FeedRow: Identifiable {
    let id:         String
    let code:       String
    let name:       String
    let tonsMes:    Double
    let costPerTon: Double

    var totalCost: Double { tonsMes * costPerTon }
}

// MARK: - UIKit share sheet bridge

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return vc
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - FeedReportView

struct FeedReportView: View {
    @Query private var allGroups:   [MultiBlendGroup]
    @Query private var allFormulas: [BlendFormula]
    @Query private var library:     [FeedIngredient]

    @State private var reportType:    ReportType  = .ingredient
    @State private var selectedCodes: Set<String> = []
    @State private var shareURL:      URL?        = nil
    @State private var showShare                  = false
    @State private var isExporting                = false
    @State private var showSettings               = false

    @ObservedObject private var settings = ReportSettings.shared

    enum ReportType: String, CaseIterable {
        case ingredient = "Hammadde"
        case feed       = "Yem Üretim"
    }

    enum ExportFormat { case txt, csv, pdf }

    // MARK: - Computed rows

    private var ingredientRows: [IngRow] {
        var usageMap: [String: Double] = [:]
        var nameMap:  [String: String] = [:]
        for group in allGroups {
            let prodTons = group.productionTons
            for fCode in group.formulaCodes {
                guard let formula = allFormulas.first(where: { $0.code == fCode }) else { continue }
                let fTons = prodTons[fCode] ?? 0
                guard fTons > 0 else { continue }
                for ing in formula.ingredients where ing.isActive && ing.hasStock {
                    usageMap[ing.code, default: 0] += ing.mixPct / 100.0 * fTons
                    if nameMap[ing.code] == nil { nameMap[ing.code] = ing.name }
                }
            }
        }
        let rows = usageMap.compactMap { (code, tons) -> IngRow? in
            guard tons > 0.001 else { return nil }
            let libIng = library.first { $0.code == code }
            return IngRow(id: code, code: code,
                          name: nameMap[code] ?? code,
                          usageTons: tons,
                          priceTLPerTon: libIng?.priceTL)
        }
        switch settings.sortSharedBy {
        case .usageDesc:    return rows.sorted { $0.usageTons > $1.usageTons }
        case .usageAsc:     return rows.sorted { $0.usageTons < $1.usageTons }
        case .alphabetical: return rows.sorted { $0.name < $1.name }
        }
    }

    private var feedRows: [FeedRow] {
        var tonsMap: [String: Double] = [:]
        for group in allGroups {
            let prodTons = group.productionTons
            for fCode in group.formulaCodes {
                tonsMap[fCode, default: 0] += prodTons[fCode] ?? 0
            }
        }
        let rows = tonsMap.compactMap { (code, tons) -> FeedRow? in
            guard tons > 0.001 else { return nil }
            guard let formula = allFormulas.first(where: { $0.code == code }) else { return nil }
            let cost = formula.lastSolve?.costPerTon ?? formula.recordedCostTL
            return FeedRow(id: code, code: code, name: formula.name,
                           tonsMes: tons, costPerTon: cost)
        }
        switch settings.sortFormulaBy {
        case .usageDesc:    return rows.sorted { $0.tonsMes > $1.tonsMes }
        case .usageAsc:     return rows.sorted { $0.tonsMes < $1.tonsMes }
        case .alphabetical: return rows.sorted { $0.name < $1.name }
        }
    }

    private var activeIds: [String] {
        reportType == .ingredient ? ingredientRows.map(\.id) : feedRows.map(\.id)
    }
    private var allSelected: Bool {
        !activeIds.isEmpty && activeIds.allSatisfy { selectedCodes.contains($0) }
    }

    private var selIngRows:  [IngRow]  { ingredientRows.filter { selectedCodes.contains($0.id) } }
    private var selFeedRows: [FeedRow] { feedRows.filter { selectedCodes.contains($0.id) } }

    private var totalIngTons:  Double { selIngRows.reduce(0) { $0 + $1.usageTons } }
    private var totalIngTL:    Double { selIngRows.compactMap(\.subtotalTL).reduce(0, +) }
    private var totalFeedTons: Double { selFeedRows.reduce(0) { $0 + $1.tonsMes } }
    private var totalFeedTL:   Double { selFeedRows.reduce(0) { $0 + $1.totalCost } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Rapor", selection: $reportType) {
                    ForEach(ReportType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                .background(Color(.systemGroupedBackground))

                // Aktif sıralama göstergesi
                Button { showSettings = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sortIcon)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 7))
                        Text(sortLabel)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Ayarlar")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Rectangle().frame(height: 0.5).foregroundStyle(Color(.separator)),
                        alignment: .bottom
                    )
                }
                .buttonStyle(.plain)

                switch reportType {
                case .ingredient: ingredientListView
                case .feed:       feedListView
                }
            }
            .navigationTitle("Yem Rapor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .onAppear { selectAll() }
        .onChange(of: reportType) { _, _ in selectAll() }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ActivityView(items: [url])
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showSettings) {
            ReportSettingsView(availableNutrients: [])
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(allSelected ? "Seçimi Kaldır" : "Tümünü Seç") {
                if allSelected { selectedCodes.subtract(activeIds) }
                else           { selectedCodes.formUnion(activeIds) }
            }
            .font(.caption)
            .disabled(activeIds.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            if isExporting {
                ProgressView().progressViewStyle(.circular).scaleEffect(0.85)
            } else {
                Menu {
                    Button { Task { await export(.pdf) } } label: {
                        Label("PDF", systemImage: "doc.richtext")
                    }
                    Button { Task { await export(.csv) } } label: {
                        Label("Excel (CSV)", systemImage: "tablecells")
                    }
                    Button { Task { await export(.txt) } } label: {
                        Label("TXT", systemImage: "doc.plaintext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(selectedCodes.isEmpty || activeIds.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
    }

    // MARK: - Ingredient list

    @ViewBuilder
    private var ingredientListView: some View {
        if ingredientRows.isEmpty {
            ContentUnavailableView(
                "Veri Yok",
                systemImage: "chart.bar.xaxis",
                description: Text("MultiBlend gruplarında üretim tonajı girilmemiş ya da formül eklenmemiş.")
            )
        } else {
            List {
                Section {
                    ForEach(ingredientRows) { row in
                        ingRowCell(row)
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(row.id) }
                    }
                }
                summarySection(
                    count: selIngRows.count, total: ingredientRows.count,
                    tons: totalIngTons, tl: totalIngTL > 0 ? totalIngTL : nil,
                    tonsLabel: "Toplam Kullanım"
                )
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func ingRowCell(_ row: IngRow) -> some View {
        let sel = selectedCodes.contains(row.id)
        HStack(spacing: 10) {
            Image(systemName: sel ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(sel ? .blue : .secondary).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.subheadline.bold())
                if !row.code.isEmpty { Text(row.code).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.3f ton", row.usageTons))
                    .font(.subheadline.bold().monospacedDigit())
                if let p = row.priceTLPerTon, p > 0 {
                    Text(fmtTL(p) + "/ton").font(.caption2).foregroundStyle(.secondary)
                }
                if let sub = row.subtotalTL {
                    Text(fmtTL(sub)).font(.caption.bold()).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(sel ? 1.0 : 0.4)
    }

    // MARK: - Feed list

    @ViewBuilder
    private var feedListView: some View {
        if feedRows.isEmpty {
            ContentUnavailableView(
                "Veri Yok",
                systemImage: "flask.fill",
                description: Text("MultiBlend gruplarında üretim tonajı girilmemiş ya da formül eklenmemiş.")
            )
        } else {
            List {
                Section {
                    ForEach(feedRows) { row in
                        feedRowCell(row)
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(row.id) }
                    }
                }
                summarySection(
                    count: selFeedRows.count, total: feedRows.count,
                    tons: totalFeedTons, tl: totalFeedTL > 0 ? totalFeedTL : nil,
                    tonsLabel: "Toplam Üretim"
                )
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func feedRowCell(_ row: FeedRow) -> some View {
        let sel = selectedCodes.contains(row.id)
        HStack(spacing: 10) {
            Image(systemName: sel ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(sel ? .blue : .secondary).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.subheadline.bold())
                if !row.code.isEmpty { Text(row.code).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.3f ton", row.tonsMes))
                    .font(.subheadline.bold().monospacedDigit())
                if row.costPerTon > 0 {
                    Text(fmtTL(row.costPerTon) + "/ton").font(.caption2).foregroundStyle(.secondary)
                }
                if row.totalCost > 0 {
                    Text(fmtTL(row.totalCost)).font(.caption.bold()).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(sel ? 1.0 : 0.4)
    }

    // MARK: - Summary section

    @ViewBuilder
    private func summarySection(count: Int, total: Int,
                                 tons: Double, tl: Double?,
                                 tonsLabel: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(count) / \(total) seçili").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(tonsLabel, systemImage: "scalemass").font(.subheadline.bold())
                    Spacer()
                    Text(String(format: "%.3f ton", tons))
                        .font(.subheadline.bold().monospacedDigit()).foregroundStyle(.orange)
                }
                if let tl {
                    Divider()
                    HStack {
                        Label("Toplam Maliyet", systemImage: "turkishlirasign").font(.subheadline.bold())
                        Spacer()
                        Text(fmtTL(tl)).font(.title3.bold().monospacedDigit()).foregroundStyle(.green)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Export

    private func export(_ format: ExportFormat) async {
        isExporting = true

        // Snapshot all value types on the main actor before going background
        struct Pack: @unchecked Sendable {
            let ingRows:   [IngRow];  let feedRows:  [FeedRow]
            let rType:     ReportType
            let tIngTons:  Double;    let tIngTL:    Double
            let tFeedTons: Double;    let tFeedTL:   Double
            let dStr:      String;    let cDate:     String
        }
        let pack = Pack(
            ingRows:   selIngRows,    feedRows:  selFeedRows,
            rType:     reportType,
            tIngTons:  totalIngTons,  tIngTL:    totalIngTL,
            tFeedTons: totalFeedTons, tFeedTL:   totalFeedTL,
            dStr:      dateStr,       cDate:     compactDate
        )
        let baseName = pack.rType == .ingredient ? "Hammadde_Raporu" : "Yem_Uretim_Raporu"

        let (data, ext): (Data, String) = await Task.detached(priority: .userInitiated) {
            // Single NumberFormatter instance — avoid creating one per cell
            let numFmt = NumberFormatter()
            numFmt.locale = Locale(identifier: "tr_TR")
            numFmt.numberStyle = .decimal
            numFmt.maximumFractionDigits = 0
            func fmtTL(_ v: Double) -> String {
                (numFmt.string(from: NSNumber(value: v)) ?? "\(Int(v))") + " ₺"
            }

            switch format {
            case .txt:
                let sep = String(repeating: "─", count: 44)
                var lines: [String]
                if pack.rType == .ingredient {
                    lines = ["HAMMADDE KULLANIM RAPORU", "Tarih: \(pack.dStr)", sep]
                    for r in pack.ingRows {
                        lines.append("• \(r.name)\(r.code.isEmpty ? "" : " (\(r.code))")")
                        lines.append("  Kullanım : \(String(format: "%.3f", r.usageTons)) ton")
                        if let p = r.priceTLPerTon, p > 0 { lines.append("  Birim    : \(fmtTL(p))/ton") }
                        if let sub = r.subtotalTL          { lines.append("  Toplam   : \(fmtTL(sub))") }
                    }
                    lines += [sep, "Toplam Kullanım : \(String(format: "%.3f", pack.tIngTons)) ton"]
                    if pack.tIngTL > 0 { lines.append("Toplam Maliyet  : \(fmtTL(pack.tIngTL))") }
                } else {
                    lines = ["YEM ÜRETİM MALİYET RAPORU", "Tarih: \(pack.dStr)", sep]
                    for r in pack.feedRows {
                        lines.append("• \(r.name)\(r.code.isEmpty ? "" : " (\(r.code))")")
                        lines.append("  Tonaj    : \(String(format: "%.3f", r.tonsMes)) ton")
                        if r.costPerTon > 0 {
                            lines.append("  Birim    : \(fmtTL(r.costPerTon))/ton")
                            lines.append("  Toplam   : \(fmtTL(r.totalCost))")
                        }
                    }
                    lines += [sep, "Toplam Üretim  : \(String(format: "%.3f", pack.tFeedTons)) ton"]
                    if pack.tFeedTL > 0 { lines.append("Toplam Maliyet : \(fmtTL(pack.tFeedTL))") }
                }
                return (lines.joined(separator: "\n").data(using: .utf8) ?? Data(), "txt")

            case .csv:
                func esc(_ s: String) -> String {
                    s.contains(";") || s.contains("\"") || s.contains("\n")
                        ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                        : s
                }
                func num(_ v: Double) -> String { String(format: "%.3f", v).replacingOccurrences(of: ".", with: ",") }
                var lines: [String]
                if pack.rType == .ingredient {
                    lines = ["Hammadde;Kod;Kullanım (ton);Fiyat (₺/ton);Toplam (₺)"]
                    for r in pack.ingRows {
                        let price = r.priceTLPerTon.map { num($0) } ?? ""
                        let sub   = r.subtotalTL.map    { num($0) } ?? ""
                        lines.append([esc(r.name), esc(r.code), num(r.usageTons), price, sub].joined(separator: ";"))
                    }
                    lines.append(["TOPLAM", "", num(pack.tIngTons), "", pack.tIngTL > 0 ? num(pack.tIngTL) : ""].joined(separator: ";"))
                } else {
                    lines = ["Yem Adı;Kod;Üretim (ton);Birim Maliyet (₺/ton);Toplam Maliyet (₺)"]
                    for r in pack.feedRows {
                        let cost  = r.costPerTon > 0 ? num(r.costPerTon) : ""
                        let total = r.totalCost  > 0 ? num(r.totalCost)  : ""
                        lines.append([esc(r.name), esc(r.code), num(r.tonsMes), cost, total].joined(separator: ";"))
                    }
                    lines.append(["TOPLAM", "", num(pack.tFeedTons), "", pack.tFeedTL > 0 ? num(pack.tFeedTL) : ""].joined(separator: ";"))
                }
                let csv = "\u{FEFF}" + lines.joined(separator: "\n")
                return (csv.data(using: .utf8) ?? Data(), "csv")

            case .pdf:
                let pageW:  CGFloat = 595.2
                let pageH:  CGFloat = 841.8
                let margin: CGFloat = 36
                let usableW = pageW - margin * 2

                struct Col { let title: String; let x: CGFloat; let w: CGFloat; let align: NSTextAlignment }
                let ingCols: [Col] = [
                    Col(title: "Hammadde",     x: margin,       w: 185, align: .left),
                    Col(title: "Kod",          x: margin + 185, w: 55,  align: .left),
                    Col(title: "Kullanım ton", x: margin + 240, w: 85,  align: .right),
                    Col(title: "₺/ton",        x: margin + 325, w: 90,  align: .right),
                    Col(title: "Toplam ₺",     x: margin + 415, w: 100, align: .right),
                ]
                let feedCols: [Col] = [
                    Col(title: "Yem Adı",      x: margin,       w: 185, align: .left),
                    Col(title: "Kod",          x: margin + 185, w: 55,  align: .left),
                    Col(title: "Üretim ton",   x: margin + 240, w: 85,  align: .right),
                    Col(title: "₺/ton",        x: margin + 325, w: 90,  align: .right),
                    Col(title: "Toplam ₺",     x: margin + 415, w: 100, align: .right),
                ]
                let cols = pack.rType == .ingredient ? ingCols : feedCols

                let titleFont  = UIFont.systemFont(ofSize: 15, weight: .bold)
                let subFont    = UIFont.systemFont(ofSize: 10, weight: .regular)
                let headerFont = UIFont.systemFont(ofSize: 9,  weight: .semibold)
                let bodyFont   = UIFont.systemFont(ofSize: 9,  weight: .regular)
                let boldFont   = UIFont.systemFont(ofSize: 10, weight: .bold)

                func attrs(_ font: UIFont,
                           _ color: UIColor = .black,
                           _ align: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
                    let ps = NSMutableParagraphStyle(); ps.alignment = align
                    return [.font: font, .foregroundColor: color, .paragraphStyle: ps]
                }

                let rowData: [[String]]
                if pack.rType == .ingredient {
                    rowData = pack.ingRows.map { r in [
                        r.name, r.code,
                        String(format: "%.3f", r.usageTons),
                        r.priceTLPerTon.map { fmtTL($0) } ?? "—",
                        r.subtotalTL.map    { fmtTL($0) } ?? "—"
                    ]}
                } else {
                    rowData = pack.feedRows.map { r in [
                        r.name, r.code,
                        String(format: "%.3f", r.tonsMes),
                        r.costPerTon > 0 ? fmtTL(r.costPerTon) : "—",
                        r.totalCost  > 0 ? fmtTL(r.totalCost)  : "—"
                    ]}
                }

                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
                let pdfData = renderer.pdfData { ctx in
                    var y: CGFloat = 0

                    func drawLine(y lineY: CGFloat, color: UIColor = .lightGray, lw: CGFloat = 0.5) {
                        ctx.cgContext.saveGState()
                        ctx.cgContext.setStrokeColor(color.cgColor)
                        ctx.cgContext.setLineWidth(lw)
                        ctx.cgContext.move(to: CGPoint(x: margin, y: lineY))
                        ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: lineY))
                        ctx.cgContext.strokePath()
                        ctx.cgContext.restoreGState()
                    }

                    func drawHeaders() {
                        ctx.cgContext.setFillColor(UIColor.systemGray6.cgColor)
                        ctx.cgContext.fill(CGRect(x: margin, y: y, width: usableW, height: 18))
                        for col in cols {
                            col.title.draw(in: CGRect(x: col.x + 2, y: y + 3, width: col.w - 4, height: 14),
                                           withAttributes: attrs(headerFont, .darkGray, col.align))
                        }
                        y += 18
                        drawLine(y: y, color: .gray, lw: 0.5)
                        y += 2
                    }

                    func newPage() { ctx.beginPage(); y = margin }

                    func checkPageBreak(needed: CGFloat) {
                        if y + needed > pageH - margin { newPage(); drawHeaders() }
                    }

                    newPage()

                    let title = pack.rType == .ingredient ? "HAMMADDE KULLANIM RAPORU" : "YEM ÜRETİM MALİYET RAPORU"
                    title.draw(in: CGRect(x: margin, y: y, width: usableW, height: 22),
                               withAttributes: attrs(titleFont))
                    y += 22
                    "Tarih: \(pack.dStr)".draw(in: CGRect(x: margin, y: y, width: usableW, height: 14),
                                               withAttributes: attrs(subFont, .gray))
                    y += 18
                    drawLine(y: y, color: .gray, lw: 1)
                    y += 8

                    drawHeaders()

                    let rowH: CGFloat = 15
                    for (i, values) in rowData.enumerated() {
                        checkPageBreak(needed: rowH + 2)
                        let bg = i % 2 == 0 ? UIColor.white : UIColor.systemGray6.withAlphaComponent(0.4)
                        ctx.cgContext.setFillColor(bg.cgColor)
                        ctx.cgContext.fill(CGRect(x: margin, y: y, width: usableW, height: rowH))
                        for (j, col) in cols.enumerated() {
                            let val = j < values.count ? values[j] : ""
                            val.draw(in: CGRect(x: col.x + 2, y: y + 2, width: col.w - 4, height: rowH - 2),
                                     withAttributes: attrs(bodyFont, .black, col.align))
                        }
                        y += rowH
                    }

                    y += 4; drawLine(y: y, color: .gray, lw: 0.8); y += 6

                    if pack.rType == .ingredient {
                        "Toplam Kullanım: \(String(format: "%.3f", pack.tIngTons)) ton"
                            .draw(in: CGRect(x: margin, y: y, width: 300, height: 16),
                                  withAttributes: attrs(boldFont))
                        y += 18
                        if pack.tIngTL > 0 {
                            "Toplam Maliyet: \(fmtTL(pack.tIngTL))"
                                .draw(in: CGRect(x: margin, y: y, width: 300, height: 16),
                                      withAttributes: attrs(boldFont, .systemGreen))
                        }
                    } else {
                        "Toplam Üretim: \(String(format: "%.3f", pack.tFeedTons)) ton"
                            .draw(in: CGRect(x: margin, y: y, width: 300, height: 16),
                                  withAttributes: attrs(boldFont))
                        y += 18
                        if pack.tFeedTL > 0 {
                            "Toplam Maliyet: \(fmtTL(pack.tFeedTL))"
                                .draw(in: CGRect(x: margin, y: y, width: 300, height: 16),
                                      withAttributes: attrs(boldFont, .systemGreen))
                        }
                    }
                }
                return (pdfData, "pdf")
            }
        }.value

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)_\(pack.cDate).\(ext)")
        do {
            try data.write(to: url)
            shareURL  = url
            showShare = true
        } catch {
            print("Export error:", error)
        }
        isExporting = false
    }

    // MARK: - Helpers

    private var sortIcon: String {
        switch reportType == .ingredient ? settings.sortSharedBy : settings.sortFormulaBy {
        case .usageDesc:    return "arrow.down.circle.fill"
        case .usageAsc:     return "arrow.up.circle.fill"
        case .alphabetical: return "textformat.abc"
        }
    }

    private var sortLabel: String {
        let s = reportType == .ingredient ? settings.sortSharedBy : settings.sortFormulaBy
        switch s {
        case .usageDesc:    return "Kullanım miktarı: Büyükten Küçüğe"
        case .usageAsc:     return "Kullanım miktarı: Küçükten Büyüğe"
        case .alphabetical: return "Alfabetik (A–Z)"
        }
    }

    private func toggle(_ id: String) {
        if selectedCodes.contains(id) { selectedCodes.remove(id) }
        else { selectedCodes.insert(id) }
    }

    private func selectAll() { selectedCodes = Set(activeIds) }

    private func fmtTL(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = Locale(identifier: "tr_TR")
        n.numberStyle = .decimal
        n.maximumFractionDigits = 0
        return (n.string(from: NSNumber(value: v)) ?? "\(Int(v))") + " ₺"
    }

    private var dateStr: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: Date())
    }

    private var compactDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}
