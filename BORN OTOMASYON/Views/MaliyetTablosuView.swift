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
    @AppStorage("maliyet_tablosu_column_order_v2")   private var columnOrderRaw:  String = ""
    @AppStorage("maliyet_tablosu_hidden_columns_v1") private var hiddenColumnsRaw: String = ""
    @AppStorage("maliyet_tablosu_zoom_v1")           private var tableZoom: Double = 1.0
    @State private var tableNaturalH: CGFloat = 0
    @State private var columnOrder:   [String]    = []
    @State private var hiddenColumns: Set<String> = []
    @State private var showColumnPicker = false

    // Sütun genişlikleri — başlıktaki tutamaç sürüklenerek ayarlanır, cihazda kalıcı
    @StateObject private var colWidths = ColumnWidthStore(tableID: "maliyetTablosu")

    // PDF'e özel sütun seçimi — ekrandaki gizleme durumundan bağımsız, sadece bu paylaşım için
    @State private var showPDFColumnPicker = false
    @State private var pdfHiddenColumns: Set<String> = []

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
        let hesaplanan:         Double   // güncel rasyon + kar% ile HER ZAMAN hesaplanan fiyat (manualPesin'den bağımsız)
        let yeniFiyat:          Double   // pesin + bulkDeltaTL (henüz kaydedilmemiş önizleme)
        let yeniKarPct:         Double
        let lastPublishedPesin: Double?
        let oncekiKarlilikPct:  Double?  // lastPublishedPesin'in GÜNCEL toplamMaliyet'e göre kâr oranı
        /// Son yayınlanan listedeki rasyon maliyeti ₺/ton (o alan eklenmeden önceki arşivlerde nil)
        let oncekiRasyon:       Double?
        /// Güncel rasyon − yayınlanan rasyon (₺/ton)
        var rasyonFark: Double? { oncekiRasyon.map { rasyon - $0 } }
        /// Rasyon maliyetindeki değişim oranı
        var rasyonFarkPct: Double? {
            guard let o = oncekiRasyon, o > 0 else { return nil }
            return (rasyon - o) / o * 100
        }
    }

    private var lastPublished: PriceListArchive? {
        PriceListArchive.lastPublished(brand: brand, in: allArchives)
    }

    /// Ölçülen tablo yüksekliğini yalnızca anlamlı değişimde yazar.
    /// Eşik olmadan, kayan nokta gürültüsü bile yeniden layout tetikleyip
    /// "observation tracking feedback loop" hatasına ve donmaya yol açar.
    private func updateNaturalH(_ h: CGFloat) {
        guard h.isFinite, h > 0, abs(h - tableNaturalH) > 1.0 else { return }
        tableNaturalH = h
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
            (lastPublished?.prices ?? []).map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a }
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
            let snap      = publishedByCode[row.formula.code]
            let lastPub   = snap?.pesin
            // rasyon alanı sonradan eklendi — 0 ise o arşivde veri yok demektir
            let oncekiRas = (snap?.rasyon).flatMap { $0 > 0 ? $0 : nil }
            return CostRow(
                code: row.formula.code, name: row.formula.name, rasyon: rasyon,
                ipCuval: ipCuval, fire: fire, elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                giderValues: giderVals, toplamMaliyet: calc.toplam, bagKg: bagKg, karPct: effKar,
                brutKarPct: Self.brutKarPct(pesin: pesin, rasyon: rasyon, bagKg: bagKg),
                pesin: pesin,
                isManual: manual >= 0,
                hesaplanan: calc.pesin,   // her zaman güncel maliyet × kar% hesabı
                yeniFiyat: yeniFiyat,
                yeniKarPct: Self.realKarPct(price: yeniFiyat, toplamMaliyet: calc.toplam, bagKg: bagKg),
                lastPublishedPesin: lastPub,
                oncekiKarlilikPct: lastPub.map { Self.realKarPct(price: $0, toplamMaliyet: calc.toplam, bagKg: bagKg) },
                oncekiRasyon: oncekiRas
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
                    Button {
                        showColumnPicker = true
                    } label: {
                        Label("Sütunları Göster/Gizle", systemImage: "rectangle.lefthalf.inset.filled.arrow.left")
                    }
                    ColumnWidthResetButton(store: colWidths)
                } footer: {
                    Text("\(visibleColumnOrder.count)/\(columnOrder.count) sütun görünüyor. Sütun genişliğini değiştirmek için başlığın sağ kenarındaki çizgiyi sürükleyin; çift dokunuş o sütunu varsayılana döndürür.")
                        .font(.caption2)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: true) {
                        let snapshot = costRows
                        let naturalW = visibleColumnOrder.reduce(CGFloat(0)) { $0 + width(for: $1) }
                        VStack(alignment: .leading, spacing: 0) {
                            tableHeaderRow
                            // enumerated: alt-satır rengi için O(n²) firstIndex araması yapılmaz
                            ForEach(Array(snapshot.enumerated()), id: \.element.id) { idx, r in
                                tableDataRow(r, alt: idx % 2 == 1)
                            }
                        }
                        // fixedSize: tablo doğal boyutunu korur — dışarıdaki padding onu
                        // sıkıştıramaz, dolayısıyla ölçüm → padding → ölçüm döngüsü oluşmaz.
                        .fixedSize()
                        .background(GeometryReader { geo in
                            Color.clear.onAppear { updateNaturalH(geo.size.height) }
                                       .onChange(of: geo.size.height) { _, h in updateNaturalH(h) }
                        })
                        .scaleEffect(tableZoom, anchor: .topLeading)
                        // scaleEffect görsel boyutu büyütür ama layout değişmez —
                        // büyüme payını padding ile layout'a ekliyoruz.
                        .padding(.bottom,   max(0, (tableZoom - 1) * tableNaturalH))
                        .padding(.trailing, max(0, (tableZoom - 1) * naturalW))
                    }
                } header: {
                    HStack {
                        Text("\(brand) — \(rows.count) ürün")
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
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 2) {
                        Button { tableZoom = max(0.6, tableZoom - 0.1) } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .disabled(tableZoom <= 0.6)
                        Text(String(format: "%.0f%%", tableZoom * 100))
                            .font(.caption.monospacedDigit())
                            .frame(minWidth: 36)
                        Button { tableZoom = min(2.0, tableZoom + 0.1) } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .disabled(tableZoom >= 2.0)
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        pdfHiddenColumns    = hiddenColumns
                        showPDFColumnPicker = true
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
            .sheet(isPresented: $showColumnPicker) {
                ColumnVisibilitySheet(
                    title: "Sütunları Göster/Gizle",
                    message: "Gizlenen sütunlar hem ekranda hem varsayılan PDF paylaşımında görünmez.",
                    columnOrder: columnOrder,
                    titleFor: title(for:),
                    hidden: $hiddenColumns,
                    onDone: saveHiddenColumns
                )
            }
            .sheet(isPresented: $showPDFColumnPicker) {
                ColumnVisibilitySheet(
                    title: "PDF'de Görünecek Sütunlar",
                    message: "Sütunlar sığmazsa rapor otomatik olarak yatay düzene geçer ve tam sığacak şekilde ölçeklenir.",
                    columnOrder: columnOrder,
                    titleFor: title(for:),
                    hidden: $pdfHiddenColumns,
                    confirmLabel: "PDF Oluştur ve Paylaş",
                    onDone: sharePDF
                )
            }
            .onAppear { loadColumnOrder(); loadHiddenColumns() }
        }
    }

    private var visibleColumnOrder: [String] {
        columnOrder.filter { !hiddenColumns.contains($0) }
    }

    // ── Sütun tanımları (dinamik — marka gider kalemlerine göre değişir) ───

    private func defaultColumnKeys() -> [String] {
        var keys = ["kod", "urun", "oncekiRasyon", "rasyon", "rasyonFark", "rasyonFarkPct",
                    "ipCuval", "fire", "elektrik", "nakliye", "iscilik"]
        keys += giderKalemleri.map { "gider:\($0.name)" }
        keys += ["toplamMaliyet", "kar", "brutKar", "pesin", "hesaplanan", "hesaplananFark", "yeniFiyat", "yeniKar", "onceki", "oncekiKarlilik", "fark"]
        return keys
    }

    private func loadColumnOrder() {
        let defaults = defaultColumnKeys()
        let valid    = Set(defaults)
        let saved    = columnOrderRaw.split(separator: ",").map(String.init).filter { valid.contains($0) }
        guard !saved.isEmpty else { columnOrder = defaults; return }

        // Sonradan eklenen sütunlar listenin sonuna atılmaz; varsayılan düzendeki
        // komşusunun yanına yerleştirilir. Kullanıcının kendi sıralaması korunur.
        var result = saved
        for (defIdx, key) in defaults.enumerated() where !result.contains(key) {
            // Varsayılan sırada bu sütundan önce gelen, kullanıcıda da bulunan ilk sütun
            let anchor = defaults[..<defIdx].last { result.contains($0) }
            if let anchor, let at = result.firstIndex(of: anchor) {
                result.insert(key, at: result.index(after: at))
            } else {
                result.insert(key, at: 0)   // öncesinde hiçbir şey yoksa başa
            }
        }
        columnOrder = result
        saveColumnOrder()
    }

    private func saveColumnOrder() {
        columnOrderRaw = columnOrder.joined(separator: ",")
    }

    private func loadHiddenColumns() {
        let valid = Set(defaultColumnKeys())
        hiddenColumns = Set(hiddenColumnsRaw.split(separator: ",").map(String.init))
            .intersection(valid)
            .subtracting(["kod", "urun"])   // kimlik sütunları her zaman görünür
    }

    private func saveHiddenColumns() {
        hiddenColumnsRaw = hiddenColumns.joined(separator: ",")
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
        case "oncekiRasyon":   return "Eski Rasyon ₺/t"
        case "rasyon":         return "Yeni Rasyon ₺/t"
        case "rasyonFark":     return "Rasyon Fark ₺/t"
        case "rasyonFarkPct":  return "Rasyon Fark%"
        case "ipCuval":        return label1
        case "fire":           return label2
        case "elektrik":       return label3
        case "nakliye":        return label4
        case "iscilik":        return label5
        case "toplamMaliyet":    return "Toplam Maliyet ₺/t"
        case "kar":              return "Kar%"
        case "brutKar":          return "Brüt Kar%"
        case "pesin":            return "Peşin ₺"
        case "hesaplanan":       return "Hesap ₺"
        case "hesaplananFark":   return "Hesap Fark ₺"
        case "yeniFiyat":        return "Yeni Fiyat ₺"
        case "yeniKar":          return "Yeni Kar%"
        case "onceki":           return "Önceki ₺"
        case "oncekiKarlilik":   return "Önceki Karlılık%"
        case "fark":             return "Fark ₺"
        default:
            return key.hasPrefix("gider:") ? String(key.dropFirst(6)) : key
        }
    }

    /// Kodda tanımlı varsayılan genişlik — kullanıcı ayarı yoksa bu kullanılır.
    private func defaultWidth(for key: String) -> CGFloat {
        switch key {
        case "kod":                    return 56
        case "urun":                   return 150
        case "kar", "brutKar", "yeniKar", "oncekiKarlilik", "rasyonFarkPct": return 60
        case "hesaplananFark":  return 76
        case "oncekiRasyon", "rasyonFark": return 88
        default:                       return 84
        }
    }

    /// Ekranda kullanılan genişlik — kullanıcı tutamaçla değiştirdiyse onun değeri.
    private func width(for key: String) -> CGFloat {
        colWidths.width(key, default: defaultWidth(for: key))
    }

    private func align(for key: String) -> TextAlignment { key == "urun" ? .leading : .center }

    // ── Tablo ────────────────────────────────────────────────────────────

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(visibleColumnOrder, id: \.self) { key in headerCell(key) }
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
        .resizableColumn(key, default: defaultWidth(for: key), store: colWidths)
    }

    @ViewBuilder
    private func tableDataRow(_ r: CostRow, alt: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(visibleColumnOrder, id: \.self) { key in cell(for: key, row: r) }
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
        case "oncekiRasyon":
            dataCell(r.oncekiRasyon.map { String(format: "%.0f", $0) } ?? "—", w,
                     color: r.oncekiRasyon == nil ? .secondary : .primary)
        case "rasyon":        dataCell(String(format: "%.0f", r.rasyon), w, bold: true)
        case "rasyonFark":
            let d = r.rasyonFark
            dataCell(d.map { String(format: "%+.0f", $0) } ?? "—", w,
                     color: (d ?? 0) > 0.5 ? .red : (d ?? 0) < -0.5 ? .green : .secondary)
        case "rasyonFarkPct":
            let p = r.rasyonFarkPct
            dataCell(p.map { String(format: "%+.1f", $0) } ?? "—", w,
                     color: (p ?? 0) > 0.05 ? .red : (p ?? 0) < -0.05 ? .green : .secondary)
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
        case "hesaplanan":
            let drift = r.isManual && abs(r.hesaplanan - r.pesin) > 0.005
            dataCell(String(format: "%.2f", r.hesaplanan), w, bold: drift,
                     color: drift ? .orange : .secondary)
        case "hesaplananFark":
            let diff = r.hesaplanan - r.pesin
            if r.isManual && abs(diff) > 0.005 {
                dataCell(String(format: "%+.2f", diff), w, color: diff > 0 ? .red : .green)
            } else {
                dataCell("—", w, color: .secondary)
            }
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
        // Kar% değişince manualPesin'i yeni oran ile yeniden hesapla
        // (manualPesin olmadan da overrideKarPct kaydedilsin)
        let rasyon = row.formula.currentCostTL > 0 ? row.formula.currentCostTL : row.formula.recordedCostTL
        let bagKg  = row.meta?.bagKg ?? 50
        let extra  = giderKalemleri.map { (value: $0.value, isPercent: $0.isPercent) }
        let calc   = PricingCalc.calculate(
            rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
            karPct: value, bagKg: bagKg, extraItems: extra
        )
        if let meta = row.meta {
            meta.overrideKarPct = value
            meta.manualPesin    = calc.pesin   // her zaman yeni kar'a göre güncelle
        } else {
            let m = ProductPricingMeta(formulaCode: row.formula.code, overrideKarPct: value, brand: brand)
            m.manualPesin = calc.pesin
            context.insert(m)
        }
        try? context.save()
    }

    private func applyBulkKarPct() {
        guard let value = parsedBulkKar else { return }
        for row in rows {
            let rasyon = row.formula.currentCostTL > 0 ? row.formula.currentCostTL : row.formula.recordedCostTL
            let bagKg  = row.meta?.bagKg ?? 50
            let extra  = giderKalemleri.map { (v: $0.value, ip: $0.isPercent) }
            let calc   = PricingCalc.calculate(
                rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                karPct: value, bagKg: bagKg, extraItems: extra.map { (value: $0.v, isPercent: $0.ip) }
            )
            if let meta = row.meta {
                meta.overrideKarPct = value
                meta.manualPesin    = calc.pesin
            } else {
                let m = ProductPricingMeta(formulaCode: row.formula.code, overrideKarPct: value, brand: brand)
                m.manualPesin = calc.pesin
                context.insert(m)
            }
        }
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
                ipCuval: $0.ipCuval, fire: $0.fire, elektrik: $0.elektrik,
                nakliye: $0.nakliye, iscilik: $0.iscilik, giderValues: $0.giderValues,
                toplamMaliyet: $0.toplamMaliyet, karPct: $0.karPct, brutKarPct: $0.brutKarPct,
                pesin: $0.pesin, lastPublishedPesin: $0.lastPublishedPesin,
                yeniFiyat: bulkDeltaTL != 0 ? $0.yeniFiyat : nil,
                yeniKarPct: bulkDeltaTL != 0 ? $0.yeniKarPct : nil,
                oncekiKarlilikPct: $0.oncekiKarlilikPct,
                oncekiRasyon: $0.oncekiRasyon
            )
        }
        let selectedColumns = columnOrder.filter { !pdfHiddenColumns.contains($0) }
        let capturedBrand = brand
        let l1 = label1, l2 = label2, l3 = label3, l4 = label4, l5 = label5
        Task.detached(priority: .userInitiated) {
            let data = MaliyetTabloPDFService.generateMaliyetTablosu(
                rows: pdfRows, brand: capturedBrand, columns: selectedColumns,
                label1: l1, label2: l2, label3: l3, label4: l4, label5: l5
            )
            let url  = PricingPDFService.writeToTemp(data: data, filename: "MaliyetTablosu")
            await MainActor.run {
                isGenerating = false
                shareURL     = url
                showShare    = url != nil
            }
        }
    }
}

// MARK: - Sütun görünürlük seçim sayfası (göster/gizle + PDF'e özel seçim için ortak)

private struct ColumnVisibilitySheet: View {
    let title:       String
    let message:     String
    let columnOrder: [String]
    let titleFor:    (String) -> String
    @Binding var hidden: Set<String>
    var confirmLabel: String = "Tamam"
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    private let alwaysVisible: Set<String> = ["kod", "urun"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(columnOrder, id: \.self) { key in
                        let forced = alwaysVisible.contains(key)
                        Toggle(titleFor(key), isOn: Binding(
                            get: { forced || !hidden.contains(key) },
                            set: { isOn in
                                guard !forced else { return }
                                if isOn { hidden.remove(key) } else { hidden.insert(key) }
                            }
                        ))
                        .disabled(forced)
                    }
                } footer: {
                    Text(message).font(.caption2)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) { onDone(); dismiss() }.fontWeight(.semibold)
                }
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
            .onChange(of: initial) { _, newVal in
                if !isFocused { text = String(format: "%.1f", newVal) }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
    }

    private func commit() {
        let clean = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(clean) { onCommit(v) } else { text = String(format: "%.1f", initial) }
    }
}
