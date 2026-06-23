import SwiftUI
import SwiftData

// MARK: - Tüm Formüller Maliyet Tablosu
//
// Seçili markaya ait tüm ürünleri (mevcut ÜRÜNLER listesiyle aynı filtre) tek tabloda
// gösterir: rasyon maliyeti + global gider kalemleri TEK TEK (toplu değil, her kalem
// kendi sütununda) + bunların toplamı (Toplam Maliyet) + kar% + peşin fiyat + TL bazlı
// toplu indirim/zam önizlemesi + önceki kayıtlı (son yayınlanan) fiyat ve o fiyata göre
// güncel maliyetle oluşan karlılık oranı. Sütun sırası ok butonlarıyla değiştirilebilir
// (sürükle-bırak Mac'te güvenilir çalışmadığı için tercih edilmedi) ve kalıcı saklanır.
// PDF olarak paylaşılabilir.

struct MaliyetTablosuView: View {
    let rows:         [(formula: BlendFormula, meta: ProductPricingMeta?)]
    let brand:        String
    let ipCuval:      Double
    let firePct:      Double
    let elektrik:     Double
    let nakliye:      Double
    let iscilik:      Double
    let globalKarPct: Double
    let label1:       String
    let label2:       String
    let label3:       String
    let label4:       String
    let label5:       String
    let giderKalemleri: [GiderKalemi]   // marka bazlı dinamik gider kalemleri — her biri kendi sütununda

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \PriceListArchive.savedAt, order: .reverse) private var allArchives: [PriceListArchive]

    @State private var isGenerating    = false
    @State private var shareURL:       URL? = nil
    @State private var showShare       = false
    @State private var bulkKarText:    String = ""
    @State private var showBulkConfirm = false

    // TL bazlı toplu indirim/zam — Maliyet Tablosu'nun kendi bağımsız kontrolü
    @State private var bulkDeltaText:       String = ""
    @State private var showBulkDeltaConfirm = false
    @State private var deltaApplied         = false

    // Sütun sırası — ok butonlarıyla değiştirilir, cihazda kalıcı saklanır.
    // String key'ler kullanılır çünkü gider kalemi sütunları markaya göre dinamiktir.
    @AppStorage("maliyet_tablosu_column_order_v2") private var columnOrderRaw: String = ""
    @State private var columnOrder: [String] = []

    struct CostRow: Identifiable {
        var id: String { code }   // kararlı kimlik — inline TextField'ların odağı her render'da sıfırlanmasın
        let code, name:        String
        let rasyon:             Double
        let ipCuval, fire, elektrik, nakliye, iscilik: Double
        let giderValues:        [String: Double]   // gider kalemi adı → ₺/ton katkı
        let toplamMaliyet:      Double
        let bagKg:              Int
        let karPct:             Double
        let brutKarPct:         Double   // (satış fiyatı ₺/ton − rasyon maliyeti) / rasyon maliyeti × 100
        let pesin:              Double
        let isManual:           Bool     // manualPesin aktif mi — bagKg değişse de bu fiyat sabit kalır
        let yeniFiyat:          Double   // pesin + bulkDeltaTL (henüz kaydedilmemiş önizleme)
        let yeniKarPct:         Double
        let lastPublishedPesin: Double?
        let oncekiKarlilikPct:  Double?  // lastPublishedPesin'in GÜNCEL toplamMaliyet'e göre kâr oranı
    }

    private var lastPublished: PriceListArchive? {
        PriceListArchive.lastPublished(brand: brand, in: allArchives)
    }

    private var bulkDeltaTL: Double {
        Double(bulkDeltaText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func realKarPct(price: Double, toplamMaliyet: Double, bagKg: Int) -> Double {
        guard toplamMaliyet > 0, bagKg > 0 else { return 0 }
        return (price / (toplamMaliyet * Double(bagKg) / 1000) - 1) * 100
    }

    // Brüt kar%: gider kalemleri hariç, SADECE rasyon maliyeti ile satış (peşin) fiyatı arasındaki fark
    private static func brutKarPct(pesin: Double, rasyon: Double, bagKg: Int) -> Double {
        guard rasyon > 0, bagKg > 0 else { return 0 }
        let satisFiyatiTon = pesin / Double(bagKg) * 1000
        return (satisFiyatiTon - rasyon) / rasyon * 100
    }

    private var costRows: [CostRow] {
        let publishedByCode = Dictionary(
            (lastPublished?.prices ?? []).map { ($0.code, $0.pesin) }, uniquingKeysWith: { a, _ in a }
        )
        let extraTuples = giderKalemleri.map { (value: $0.value, isPercent: $0.isPercent) }
        return rows.map { row in
            let rasyon = row.formula.currentCostTL > 0 ? row.formula.currentCostTL : row.formula.recordedCostTL
            let effKar = (row.meta?.overrideKarPct ?? -1) >= 0 ? row.meta!.overrideKarPct : globalKarPct
            let bagKg  = row.meta?.bagKg ?? 50
            let fire   = rasyon * firePct / 100
            let giderVals = Dictionary(uniqueKeysWithValues: giderKalemleri.map { ($0.name, $0.contribution(rasyon: rasyon)) })
            let calc   = PricingCalc.calculate(
                rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                karPct: effKar, bagKg: bagKg, extraItems: extraTuples
            )
            let manual    = row.meta?.manualPesin ?? -1
            let pesin     = manual >= 0 ? manual : calc.pesin
            let yeniFiyat = max(0, pesin + bulkDeltaTL)
            let lastPub   = publishedByCode[row.formula.code]
            return CostRow(
                code: row.formula.code, name: row.formula.name, rasyon: rasyon,
                ipCuval: ipCuval, fire: fire, elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                giderValues: giderVals, toplamMaliyet: calc.toplam, bagKg: bagKg, karPct: effKar,
                brutKarPct: Self.brutKarPct(pesin: pesin, rasyon: rasyon, bagKg: bagKg),
                pesin: pesin,
                isManual: manual >= 0,
                yeniFiyat: yeniFiyat,
                yeniKarPct: Self.realKarPct(price: yeniFiyat, toplamMaliyet: calc.toplam, bagKg: bagKg),
                lastPublishedPesin: lastPub,
                oncekiKarlilikPct: lastPub.map { Self.realKarPct(price: $0, toplamMaliyet: calc.toplam, bagKg: bagKg) }
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Tüm Kar%'ları Ayarla")
                        Spacer()
                        TextField("örn. 18", text: $bulkKarText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                        Button("Uygula") { showBulkConfirm = true }
                            .disabled(parsedBulkKar == nil)
                    }
                } footer: {
                    Text("Girilen oran, listedeki TÜM \(costRows.count) ürüne aynı anda uygulanır. Her ürünün oranı tablodaki Kar% sütunundan tek tek de düzenlenebilir.")
                        .font(.caption2)
                }
                .alert("Tüm ürünlerin kar oranını değiştir?", isPresented: $showBulkConfirm) {
                    Button("Uygula", role: .destructive) { applyBulkKarPct() }
                    Button("Vazgeç", role: .cancel) { }
                } message: {
                    Text("\(costRows.count) ürünün kar oranı %\(bulkKarText) olarak ayarlanacak. Bu işlem geri alınamaz.")
                }

                Section {
                    HStack {
                        Text("Toplu Fiyat Ayarı (₺)")
                        Spacer()
                        TextField("örn. 50 veya -30", text: $bulkDeltaText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Button("Uygula") { showBulkDeltaConfirm = true }
                            .disabled(bulkDeltaTL == 0)
                    }
                    if deltaApplied {
                        Label("Tüm ürünlere kalıcı olarak uygulandı", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                } footer: {
                    Text("Tutarı girince \"Yeni Fiyat\" ve \"Yeni Kar%\" sütunları tabloda anında, kaydetmeden önizlenir. \"Uygula\" ile TÜM ürünlere kalıcı olarak yazılır.")
                        .font(.caption2)
                }
                .onChange(of: bulkDeltaText) { _, _ in deltaApplied = false }
                .alert("Tüm ürünlerin fiyatını güncelle?", isPresented: $showBulkDeltaConfirm) {
                    Button("Uygula", role: .destructive) { applyBulkDelta() }
                    Button("Vazgeç", role: .cancel) { }
                } message: {
                    Text(String(format: "%d ürünün fiyatına %+.2f ₺ uygulanacak.", costRows.count, bulkDeltaTL))
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            tableHeaderRow
                            ForEach(costRows) { r in
                                tableDataRow(r, alt: (costRows.firstIndex { $0.id == r.id } ?? 0) % 2 == 1)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("\(brand) — \(costRows.count) ürün")
                        Spacer()
                        if let lp = lastPublished {
                            Text("Önceki liste: \(lp.revision.isEmpty ? lp.period : lp.revision)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Sütun başlıklarındaki ‹ › oklarıyla sırayı değiştirebilirsiniz.")
                        .font(.caption2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Maliyet Tablosu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sharePDF()
                    } label: {
                        if isGenerating { ProgressView().scaleEffect(0.8) }
                        else { Image(systemName: "doc.richtext.fill").foregroundStyle(.orange) }
                    }
                    .disabled(isGenerating || costRows.isEmpty)
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL { ShareSheet(url: url) }
            }
            .onAppear { loadColumnOrder() }
        }
    }

    // ── Sütun tanımları (dinamik — marka gider kalemlerine göre değişir) ───

    private func defaultColumnKeys() -> [String] {
        var keys = ["kod", "urun", "rasyon", "ipCuval", "fire", "elektrik", "nakliye", "iscilik"]
        keys += giderKalemleri.map { "gider:\($0.name)" }
        keys += ["toplamMaliyet", "kar", "brutKar", "pesin", "yeniFiyat", "yeniKar", "onceki", "oncekiKarlilik", "fark"]
        return keys
    }

    private func loadColumnOrder() {
        let defaults = defaultColumnKeys()
        let valid    = Set(defaults)
        let saved    = columnOrderRaw.split(separator: ",").map(String.init).filter { valid.contains($0) }
        let missing  = defaults.filter { !saved.contains($0) }
        columnOrder  = saved.isEmpty ? defaults : saved + missing
    }

    private func saveColumnOrder() {
        columnOrderRaw = columnOrder.joined(separator: ",")
    }

    private func moveColumn(_ key: String, by offset: Int) {
        guard let idx = columnOrder.firstIndex(of: key) else { return }
        let newIdx = idx + offset
        guard newIdx >= 0, newIdx < columnOrder.count else { return }
        columnOrder.swapAt(idx, newIdx)
        saveColumnOrder()
    }

    private func title(for key: String) -> String {
        switch key {
        case "kod":            return "Kod"
        case "urun":           return "Ürün"
        case "rasyon":         return "Rasyon ₺/t"
        case "ipCuval":        return label1
        case "fire":           return label2
        case "elektrik":       return label3
        case "nakliye":        return label4
        case "iscilik":        return label5
        case "toplamMaliyet":  return "Toplam Maliyet ₺/t"
        case "kar":            return "Kar%"
        case "brutKar":        return "Brüt Kar%"
        case "pesin":          return "Peşin ₺"
        case "yeniFiyat":      return "Yeni Fiyat ₺"
        case "yeniKar":        return "Yeni Kar%"
        case "onceki":         return "Önceki ₺"
        case "oncekiKarlilik": return "Önceki Karlılık%"
        case "fark":           return "Fark ₺"
        default:
            return key.hasPrefix("gider:") ? String(key.dropFirst(6)) : key
        }
    }

    private func width(for key: String) -> CGFloat {
        switch key {
        case "kod":                    return 56
        case "urun":                   return 150
        case "kar", "brutKar", "yeniKar", "oncekiKarlilik": return 60
        default:                       return 84
        }
    }

    private func align(for key: String) -> TextAlignment { key == "urun" ? .leading : .center }

    // ── Tablo ────────────────────────────────────────────────────────────

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(columnOrder, id: \.self) { key in headerCell(key) }
        }
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    private func headerCell(_ key: String) -> some View {
        VStack(spacing: 1) {
            Text(title(for: key)).font(.caption2.bold()).foregroundStyle(.secondary)
                .multilineTextAlignment(align(for: key))
                .lineLimit(2)
            HStack(spacing: 4) {
                Button { moveColumn(key, by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(columnOrder.first == key)
                Button { moveColumn(key, by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(columnOrder.last == key)
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.blue)
        }
        .frame(width: width(for: key), alignment: align(for: key) == .leading ? .leading : .center)
    }

    @ViewBuilder
    private func tableDataRow(_ r: CostRow, alt: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(columnOrder, id: \.self) { key in cell(for: key, row: r) }
        }
        .padding(.vertical, 4)
        .background(alt ? Color(.systemGroupedBackground) : Color.clear)
    }

    @ViewBuilder
    private func cell(for key: String, row r: CostRow) -> some View {
        let w = width(for: key)
        switch key {
        case "kod":           dataCell(r.code, w)
        case "urun":          dataCell(r.name, w, align: .leading)
        case "rasyon":        dataCell(String(format: "%.0f", r.rasyon), w)
        case "ipCuval":       dataCell(String(format: "%.0f", r.ipCuval), w)
        case "fire":          dataCell(String(format: "%.0f", r.fire), w)
        case "elektrik":      dataCell(String(format: "%.0f", r.elektrik), w)
        case "nakliye":       dataCell(String(format: "%.0f", r.nakliye), w)
        case "iscilik":       dataCell(String(format: "%.0f", r.iscilik), w)
        case "toplamMaliyet": dataCell(String(format: "%.0f", r.toplamMaliyet), w, bold: true)
        case "kar":
            KarPctField(initial: r.karPct) { newVal in commitKarPct(newVal, code: r.code) }
                .frame(width: w)
        case "brutKar":
            dataCell(String(format: "%.1f", r.brutKarPct), w, color: r.brutKarPct < 0 ? .red : .green)
        case "pesin":
            dataCell(r.isManual ? "M " + String(format: "%.2f", r.pesin) : String(format: "%.2f", r.pesin),
                     w, bold: true, color: r.isManual ? .purple : .primary)
        case "yeniFiyat":
            dataCell(String(format: "%.2f", r.yeniFiyat), w, bold: true,
                     color: bulkDeltaTL == 0 ? .primary : .orange)
        case "yeniKar":
            dataCell(String(format: "%.1f", r.yeniKarPct), w, color: r.yeniKarPct < 0 ? .red : .green)
        case "onceki":
            dataCell(r.lastPublishedPesin.map { String(format: "%.2f", $0) } ?? "—", w)
        case "oncekiKarlilik":
            dataCell(r.oncekiKarlilikPct.map { String(format: "%.1f", $0) } ?? "—", w,
                     color: (r.oncekiKarlilikPct ?? 0) < 0 ? .red : .green)
        case "fark":
            let fark = r.lastPublishedPesin.map { r.pesin - $0 }
            dataCell(fark.map { String(format: "%+.2f", $0) } ?? "—", w,
                     color: (fark ?? 0) > 0.001 ? .red : (fark ?? 0) < -0.001 ? .green : .secondary)
        default:
            if key.hasPrefix("gider:") {
                let name = String(key.dropFirst(6))
                dataCell(String(format: "%.0f", r.giderValues[name] ?? 0), w)
            } else {
                dataCell("—", w)
            }
        }
    }

    private func dataCell(_ text: String, _ width: CGFloat, align: TextAlignment = .center,
                          bold: Bool = false, color: Color = .primary) -> some View {
        Text(text)
            .font(bold ? .caption.bold().monospacedDigit() : .caption.monospacedDigit())
            .foregroundStyle(color)
            .frame(width: width, alignment: align == .leading ? .leading : .center)
            .lineLimit(1)
    }

    // ── Kar% yazma (ürün ürün veya toplu) ─────────────────────────────────

    private var parsedBulkKar: Double? {
        Double(bulkKarText.replacingOccurrences(of: ",", with: "."))
    }

    private func setKarPct(_ value: Double, for row: (formula: BlendFormula, meta: ProductPricingMeta?)) {
        if let meta = row.meta {
            meta.overrideKarPct = value
        } else {
            let m = ProductPricingMeta(formulaCode: row.formula.code, overrideKarPct: value, brand: brand)
            context.insert(m)
        }
    }

    private func commitKarPct(_ value: Double, code: String) {
        guard let row = rows.first(where: { $0.formula.code == code }) else { return }
        setKarPct(value, for: row)
        try? context.save()
    }

    private func applyBulkKarPct() {
        guard let value = parsedBulkKar else { return }
        for row in rows { setKarPct(value, for: row) }
        try? context.save()
        bulkKarText = ""
    }

    // ── TL bazlı toplu fiyat ayarı (ürün ürün önizlenir, Uygula'da kalıcı yazılır) ──

    private func applyBulkDelta() {
        let snapshot = costRows   // delta'yı uygulamadan ÖNCEKİ hesaplanmış yeni fiyatlar
        for r in snapshot {
            guard let row = rows.first(where: { $0.formula.code == r.code }) else { continue }
            if let meta = row.meta {
                meta.manualPesin = r.yeniFiyat
            } else {
                let m = ProductPricingMeta(formulaCode: r.code, brand: brand)
                m.manualPesin = r.yeniFiyat
                context.insert(m)
            }
        }
        try? context.save()
        bulkDeltaText = ""
        deltaApplied  = true
    }

    private func sharePDF() {
        isGenerating = true
        let pdfRows = costRows.map {
            MaliyetTabloPDFService.CostRow(
                code: $0.code, name: $0.name, rasyon: $0.rasyon,
                toplamMaliyet: $0.toplamMaliyet, karPct: $0.karPct, pesin: $0.pesin,
                lastPublishedPesin: $0.lastPublishedPesin,
                brutKarPct: $0.brutKarPct,
                yeniFiyat: bulkDeltaTL != 0 ? $0.yeniFiyat : nil,
                yeniKarPct: bulkDeltaTL != 0 ? $0.yeniKarPct : nil,
                oncekiKarlilikPct: $0.oncekiKarlilikPct
            )
        }
        let capturedBrand = brand
        Task.detached(priority: .userInitiated) {
            let data = MaliyetTabloPDFService.generateMaliyetTablosu(rows: pdfRows, brand: capturedBrand)
            let url  = PricingPDFService.writeToTemp(data: data, filename: "MaliyetTablosu")
            await MainActor.run {
                isGenerating = false
                shareURL     = url
                showShare    = url != nil
            }
        }
    }
}

// MARK: - Ürün ürün kar% düzenleme alanı (local @State odak yönetimi — CompactDoubleField deseni)

private struct KarPctField: View {
    let initial:  Double
    let onCommit: (Double) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("0.0", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.caption.bold().monospacedDigit())
            .padding(.horizontal, 4).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isFocused ? Color.blue : Color.blue.opacity(0.45), lineWidth: isFocused ? 1.5 : 1)
            )
            .padding(2)
            .focused($isFocused)
            .onAppear { text = String(format: "%.1f", initial) }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
    }

    private func commit() {
        let clean = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(clean) { onCommit(v) } else { text = String(format: "%.1f", initial) }
    }
}
