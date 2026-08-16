import SwiftUI
import SwiftData

// MARK: - Toplu Fiyat Güncelleme (TL bazlı zam/indirim)
//
// Akış: ürün seç (serbest çoklu seçim) → TL tutar gir → Önizle (hesapla, henüz kaydetme) →
// Kaydet (ProductPricingMeta.manualPesin'e kalıcı yaz) → PDF paylaş.
// Önizleme, Maliyet Tablosu'ndaki gibi geniş/yatay kaydırmalı bir tablo olarak gösterilir:
// her ürün için rasyon+gider+toplam maliyet, eski/yeni fiyat ve kar%, ve peşin/kredi kartı/
// 30/60/90 gün vade baremlerinde hem çuval hem ton bazında fiyat + kar%.
// "Eski peşin" hesabı FiyatListesiView.buildPriceSnaps() ile birebir aynı mantığı kullanır.
// PDF raporu kasıtlı olarak sade kalır (eski/yeni/fark/son-liste-farkı) — 20+ sütunluk
// vade/çuval/ton matrisi ekranda gösterilir, PDF'e basılmaz (okunaklılık için).

struct TopluFiyatGuncellemeView: View {
    let rows:         [(formula: BlendFormula, meta: ProductPricingMeta?)]
    let brand:        String
    let ipCuval:      Double
    let firePct:      Double
    let elektrik:     Double
    let nakliye:      Double
    let iscilik:      Double
    let globalKarPct: Double
    var extraItems:   [(value: Double, isPercent: Bool)] = []

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \PriceListArchive.savedAt, order: .reverse) private var allArchives: [PriceListArchive]

    // Vade baremleri — FiyatListesiView ile aynı AppStorage anahtarları (tek kaynak)
    @AppStorage("pricing_vade_tek_cekim") private var vadeTekCekim: Double = 2.8
    @AppStorage("pricing_vade_30gun")     private var vade30:       Double = 4.5
    @AppStorage("pricing_vade_60gun")     private var vade60:       Double = 9.2
    @AppStorage("pricing_vade_90gun")     private var vade90:       Double = 14.1

    @State private var selectedCodes: Set<String> = []
    @State private var deltaText:     String      = ""
    @State private var isPercentMode  = false      // false = ₺ tutar, true = % oran
    @State private var previewRows:   [BulkChangeRow] = []
    @State private var isSaved        = false
    @State private var isGenerating   = false
    @State private var shareURL:      URL?  = nil
    @State private var showShare      = false

    // Sütun genişlikleri — başlıktaki tutamaç sürüklenerek ayarlanır, cihazda kalıcı
    @StateObject private var colWidths = ColumnWidthStore(tableID: "topluFiyatOnizleme")

    /// Karşılaştırma bazı olarak seçilen arşiv (nil = en son yayınlanan).
    @State private var baseArchiveID: PersistentIdentifier? = nil

    // Bir vade baremi için fiyat + kar% çifti (çuval cinsinden fiyat; ton fiyatı bagKg ile türetilir)
    struct TierValue {
        let cuval: Double
        let ton:   Double
        let karPct: Double
    }

    struct BulkChangeRow: Identifiable {
        var id: String { code }
        let code:          String
        let name:          String
        let rasyon:        Double   // ₺/ton
        let giderToplam:   Double   // ₺/ton
        let toplamMaliyet: Double   // ₺/ton
        let bagKg:         Int
        let oldPesinCuval: Double
        let oldKarPct:     Double?  // son yayınlanan yoksa nil
        let newPesinCuval: Double
        let newKarPct:     Double
        let lastPublishedPesin: Double?

        func tier(_ vadePct: Double, toplamMaliyet: Double, bagKg: Int) -> TierValue {
            let cuval = newPesinCuval * (1 + vadePct / 100)
            let ton   = cuval / Double(bagKg) * 1000
            let kar   = (cuval / (toplamMaliyet * Double(bagKg) / 1000) - 1) * 100
            return TierValue(cuval: cuval, ton: ton, karPct: kar)
        }
    }

    /// Kullanıcının girdiği ham değer — mode'a göre ₺ tutar veya % oran.
    private var deltaInput: Double {
        Double(deltaText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Bir ürünün mevcut fiyatına uygulanacak ₺ farkı (yüzde modunda fiyata göre türetilir).
    private func deltaFor(basePrice: Double) -> Double {
        isPercentMode ? basePrice * deltaInput / 100.0 : deltaInput
    }

    /// PDF özetinde gösterilecek temsilî ₺ fark (yüzde modunda ortalama).
    private var reportDeltaTL: Double {
        guard !previewRows.isEmpty else { return deltaInput }
        let diffs = previewRows.map { $0.newPesinCuval - $0.oldPesinCuval }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    /// Bu markanın tüm yayınlanmış listeleri — en yeniden eskiye.
    private var publishedArchives: [PriceListArchive] {
        allArchives.filter { $0.brand == brand && $0.isPublished }
                   .sorted { $0.savedAt > $1.savedAt }
    }

    private var lastPublished: PriceListArchive? {
        PriceListArchive.lastPublished(brand: brand, in: allArchives)
    }

    /// Karşılaştırma bazı: seçili arşiv, seçim yoksa en son yayınlanan liste.
    private var baseArchive: PriceListArchive? {
        if let baseArchiveID,
           let found = publishedArchives.first(where: { $0.persistentModelID == baseArchiveID }) {
            return found
        }
        return lastPublished
    }

    /// Baz listedeki fiyatlar — kod → peşin ₺/çuval.
    private var basePricesByCode: [String: Double] {
        Dictionary((baseArchive?.prices ?? []).map { ($0.code, $0.pesin) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// Maliyetlendirme sırasını koruyan ürün kodu listesi (ForEach tip çıkarımını sadeleştirir).
    private var productCodes: [String] {
        rows.map { $0.formula.code }
    }

    private func rowFor(code: String) -> (formula: BlendFormula, meta: ProductPricingMeta?)? {
        rows.first { $0.formula.code == code }
    }

    @ViewBuilder
    private func productRow(code: String) -> some View {
        if let row = rowFor(code: code) {
            let isPicked  = selectedCodes.contains(code)
            let published = basePricesByCode[code]
            let current   = currentPesin(row)
            let category  = (row.meta?.categoryGroup).flatMap { $0.isEmpty ? nil : $0 } ?? "Kategorisiz"
            Button {
                if isPicked { selectedCodes.remove(code) } else { selectedCodes.insert(code) }
            } label: {
                HStack {
                    Image(systemName: isPicked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isPicked ? Color.blue : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.formula.name).font(.subheadline).foregroundStyle(.primary)
                        Text(category).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        // Baz listedeki (yayınlanmış) fiyat — ana değer
                        Text(String(format: "%.2f ₺", published ?? current))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(published == nil ? Color.secondary : Color.orange)
                        if published == nil {
                            Text("listede yok")
                                .font(.caption2).foregroundStyle(.tertiary)
                        } else if abs(current - (published ?? 0)) > 0.005 {
                            // Yayınlanmış fiyat ile güncel maliyet hesabı ayrışmışsa göster
                            Text(String(format: "güncel %.2f ₺", current))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func archiveLabel(_ a: PriceListArchive) -> String {
        var parts: [String] = []
        if !a.revision.isEmpty { parts.append("Rev \(a.revision)") }
        if !a.period.isEmpty   { parts.append(a.period) }
        parts.append(a.displayDate)
        return parts.joined(separator: " · ")
    }

    private static func karPct(price: Double, toplamMaliyet: Double, bagKg: Int) -> Double {
        guard toplamMaliyet > 0, bagKg > 0 else { return 0 }
        return (price / (toplamMaliyet * Double(bagKg) / 1000) - 1) * 100
    }

    // FiyatListesiView.buildPriceSnaps() ile aynı hesap — şu an geçerli (kaydedilmemiş) peşin fiyat
    private func currentPesin(_ row: (formula: BlendFormula, meta: ProductPricingMeta?)) -> Double {
        calc(row).pesin0
    }

    private func calc(_ row: (formula: BlendFormula, meta: ProductPricingMeta?))
        -> (rasyon: Double, toplam: Double, bagKg: Int, pesin0: Double) {
        let rasyon = row.formula.currentCostTL > 0 ? row.formula.currentCostTL : row.formula.recordedCostTL
        let effKar = (row.meta?.overrideKarPct ?? -1) >= 0 ? row.meta!.overrideKarPct : globalKarPct
        let bagKg  = row.meta?.bagKg ?? 50
        let c = PricingCalc.calculate(
            rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
            karPct: effKar, bagKg: bagKg, extraItems: extraItems
        )
        let manual = row.meta?.manualPesin ?? -1
        return (rasyon, c.toplam, bagKg, manual >= 0 ? manual : c.pesin)
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Baz liste seçici (geçmişe dönük listeler dâhil) ──────────
                Section {
                    if publishedArchives.isEmpty {
                        Text("\(brand) için henüz yayınlanmış liste yok — karşılaştırma güncel hesaba göre yapılır.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Menu {
                            Button {
                                baseArchiveID = nil
                            } label: {
                                HStack {
                                    Text("En Son Yayınlanan (otomatik)")
                                    if baseArchiveID == nil { Image(systemName: "checkmark") }
                                }
                            }
                            Divider()
                            ForEach(publishedArchives) { arc in
                                Button {
                                    baseArchiveID = arc.persistentModelID
                                } label: {
                                    HStack {
                                        Text(archiveLabel(arc))
                                        if arc.persistentModelID == baseArchiveID {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Baz Liste")
                                Spacer()
                                Text(baseArchive.map(archiveLabel) ?? "—")
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }
                        }
                        .onChange(of: baseArchiveID) { _, _ in
                            previewRows = []; isSaved = false
                        }
                    }
                } header: {
                    Text("Karşılaştırma Bazı")
                } footer: {
                    Text("Ürün fiyatları seçili yayınlanmış listeye göre gösterilir ve karşılaştırılır. Geçmiş listelerinizi de seçebilirsiniz.")
                        .font(.caption2)
                }

                Section {
                    Picker("Uygulama", selection: $isPercentMode) {
                        Text("₺ Tutar").tag(false)
                        Text("% Oran").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isPercentMode) { _, _ in
                        previewRows = []; isSaved = false
                    }

                    HStack {
                        Text(isPercentMode ? "Zam / İndirim Oranı (%)" : "Zam / İndirim Tutarı (₺)")
                        Spacer()
                        TextField(isPercentMode ? "örn. 5 veya -3" : "örn. 50 veya -30", text: $deltaText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                } header: {
                    Text("Zam / İndirim")
                } footer: {
                    Text(isPercentMode
                         ? "Pozitif oran zam, negatif oran indirim uygular. Oran, her ürünün baz fiyatı üzerinden hesaplanır."
                         : "Pozitif tutar zam, negatif tutar indirim uygular. Tutar, seçili ürünlerin baz fiyatına doğrudan eklenir.")
                        .font(.caption2)
                }

                Section {
                    HStack {
                        Button(selectedCodes.count == rows.count ? "Hiçbirini Seçme" : "Tümünü Seç") {
                            selectedCodes = selectedCodes.count == rows.count
                                ? [] : Set(rows.map { $0.formula.code })
                        }
                        .font(.caption)
                        Spacer()
                        Text("\(selectedCodes.count)/\(rows.count) ürün seçili")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(productCodes, id: \.self) { code in
                        productRow(code: code)
                    }
                } header: {
                    Text("Ürünler")
                } footer: {
                    Text(baseArchive == nil
                         ? "Yayınlanmış liste bulunmadığı için güncel maliyet hesabından türetilen fiyatlar gösteriliyor."
                         : "Turuncu fiyatlar seçili baz listeden gelir. Farklıysa güncel maliyet hesabı ayrıca belirtilir.")
                        .font(.caption2)
                }

                Section {
                    Button {
                        buildPreview()
                    } label: {
                        Label("Önizle", systemImage: "eye")
                    }
                    .disabled(selectedCodes.isEmpty || deltaInput == 0)
                } footer: {
                    Text("Önizle, hesaplar ve aşağıda geniş tabloda gösterir — henüz hiçbir şey kaydedilmez.")
                        .font(.caption2)
                }

                if !previewRows.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 0) {
                                tableHeaderRow
                                ForEach(Array(previewRows.enumerated()), id: \.element.id) { idx, r in
                                    tableDataRow(r, alt: idx % 2 == 1)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Önizleme (\(previewRows.count) ürün) — Peşin/Kredi Kartı/30-60-90 Gün, Çuval+Ton")
                            Spacer()
                            if colWidths.hasCustomWidths {
                                Menu {
                                    ColumnWidthResetButton(store: colWidths)
                                } label: {
                                    Image(systemName: "arrow.left.and.right.square").font(.caption)
                                }
                            }
                        }
                    } footer: {
                        Text("Baz liste: \(baseArchive.map(archiveLabel) ?? "—"). Eski Fiyat ve Eski Kar% bu listeye göre hesaplanır; zam/indirim de bu fiyat üzerine uygulanır. Sütun genişliğini değiştirmek için başlığın sağ kenarındaki çizgiyi sürükleyin.")
                            .font(.caption2)
                    }

                    Section {
                        Button {
                            saveChanges()
                        } label: {
                            HStack {
                                Image(systemName: isSaved ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                                Text(isSaved ? "Kaydedildi" : "Kaydet").fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(isSaved)
                        .listRowBackground(isSaved ? Color.gray.opacity(0.3) : Color.green)
                        .foregroundStyle(.white)

                        Button {
                            sharePDF()
                        } label: {
                            HStack {
                                if isGenerating {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Oluşturuluyor…")
                                } else {
                                    Image(systemName: "doc.richtext.fill").foregroundStyle(.orange)
                                    Text("PDF Olarak Paylaş (özet)")
                                }
                            }
                        }
                        .disabled(isGenerating)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Toplu Fiyat Güncelleme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL { ShareSheet(url: url) }
            }
        }
    }

    // ── Geniş tablo ────────────────────────────────────────────────────────

    // Varsayılan genişlikler — kullanıcı başlıktaki tutamacı sürükleyerek her sütunu
    // ayrı ayrı değiştirebilir (ColumnWidthStore ile kalıcı saklanır).
    private let wCode: CGFloat = 50, wName: CGFloat = 140, wMoney: CGFloat = 64, wKar: CGFloat = 48

    /// Vade baremleri — sütun anahtarı öneki ve ekranda görünen etiketi.
    private static let tiers: [(key: String, label: String)] = [
        ("pesin", "Peşin"), ("kk", "Kredi K."), ("g30", "30 Gün"), ("g60", "60 Gün"), ("g90", "90 Gün")
    ]

    private func width(_ key: String, _ fallback: CGFloat) -> CGFloat {
        colWidths.width(key, default: fallback)
    }

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            headerCell("Kod", "kod", wCode)
            headerCell("Ürün", "urun", wName, align: .leading)
            headerCell("Rasyon ₺/t", "rasyon", wMoney)
            headerCell("Gider ₺/t", "gider", wMoney)
            headerCell("Toplam ₺/t", "toplam", wMoney)
            headerCell("Eski Çuval", "eskiCuval", wMoney)
            headerCell("Eski Ton", "eskiTon", wMoney)
            headerCell("Eski Kar%", "eskiKar", wKar)
            ForEach(Self.tiers, id: \.key) { tier in
                tierHeader(tier.label, tier.key)
            }
        }
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    @ViewBuilder
    private func tierHeader(_ label: String, _ key: String) -> some View {
        headerCell("\(label) Çuval", "\(key).cuval", wMoney)
        headerCell("\(label) Ton",   "\(key).ton",   wMoney)
        headerCell("\(label) Kar%",  "\(key).kar",   wKar)
    }

    private func headerCell(_ text: String, _ key: String, _ fallback: CGFloat,
                            align: TextAlignment = .center) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(.secondary)
            .frame(width: width(key, fallback), alignment: align == .leading ? .leading : .center)
            .multilineTextAlignment(align)
            .resizableColumn(key, default: fallback, store: colWidths)
    }

    @ViewBuilder
    private func tableDataRow(_ r: BulkChangeRow, alt: Bool) -> some View {
        HStack(spacing: 0) {
            dataCell(r.code, "kod", wCode)
            dataCell(r.name, "urun", wName, align: .leading)
            dataCell(String(format: "%.0f", r.rasyon), "rasyon", wMoney)
            dataCell(String(format: "%.0f", r.giderToplam), "gider", wMoney)
            dataCell(String(format: "%.0f", r.toplamMaliyet), "toplam", wMoney)
            dataCell(String(format: "%.2f", r.oldPesinCuval), "eskiCuval", wMoney)
            dataCell(String(format: "%.0f", r.oldPesinCuval / Double(r.bagKg) * 1000), "eskiTon", wMoney)
            dataCell(r.oldKarPct.map { String(format: "%.1f", $0) } ?? "—", "eskiKar", wKar)
            ForEach(Self.tiers, id: \.key) { tier in
                tierCells(r.tier(vadePct(tier.key), toplamMaliyet: r.toplamMaliyet, bagKg: r.bagKg),
                          tier.key)
            }
        }
        .padding(.vertical, 4)
        .background(alt ? Color(.systemGroupedBackground) : Color.clear)
    }

    private func vadePct(_ key: String) -> Double {
        switch key {
        case "kk":  return vadeTekCekim
        case "g30": return vade30
        case "g60": return vade60
        case "g90": return vade90
        default:    return 0        // peşin
        }
    }

    @ViewBuilder
    private func tierCells(_ t: TierValue, _ key: String) -> some View {
        dataCell(String(format: "%.2f", t.cuval), "\(key).cuval", wMoney, bold: true)
        dataCell(String(format: "%.0f", t.ton),   "\(key).ton",   wMoney)
        dataCell(String(format: "%.1f", t.karPct), "\(key).kar",  wKar,
                 color: t.karPct < 0 ? .red : .green)
    }

    private func dataCell(_ text: String, _ key: String, _ fallback: CGFloat,
                          align: TextAlignment = .center,
                          bold: Bool = false, color: Color = .primary) -> some View {
        Text(text)
            .font(bold ? .caption.bold().monospacedDigit() : .caption.monospacedDigit())
            .foregroundStyle(color)
            .frame(width: width(key, fallback), alignment: align == .leading ? .leading : .center)
            .lineLimit(1)
    }

    // ── Hesaplama / kaydetme / paylaşma ────────────────────────────────────

    private func buildPreview() {
        let publishedByCode = basePricesByCode
        previewRows = rows
            .filter { selectedCodes.contains($0.formula.code) }
            .map { row -> BulkChangeRow in
                let c = calc(row)
                let basePub = publishedByCode[row.formula.code]
                // Zam/indirim DAİMA baz listedeki yayınlanmış fiyat üzerine uygulanır;
                // o üründe yayınlanmış fiyat yoksa güncel hesaba düşülür.
                let oldPesinCuval = basePub ?? c.pesin0
                let newPesinCuval = max(0, oldPesinCuval + deltaFor(basePrice: oldPesinCuval))
                let oldKar = Self.karPct(price: oldPesinCuval, toplamMaliyet: c.toplam, bagKg: c.bagKg)
                let newKar = Self.karPct(price: newPesinCuval, toplamMaliyet: c.toplam, bagKg: c.bagKg)
                return BulkChangeRow(
                    code: row.formula.code, name: row.formula.name,
                    rasyon: c.rasyon, giderToplam: c.toplam - c.rasyon, toplamMaliyet: c.toplam,
                    bagKg: c.bagKg,
                    oldPesinCuval: oldPesinCuval, oldKarPct: oldKar,
                    newPesinCuval: newPesinCuval, newKarPct: newKar,
                    lastPublishedPesin: basePub
                )
            }
        isSaved = false
    }

    private func saveChanges() {
        for r in previewRows {
            guard let row = rows.first(where: { $0.formula.code == r.code }) else { continue }
            if let meta = row.meta {
                meta.manualPesin = r.newPesinCuval
            } else {
                let m = ProductPricingMeta(formulaCode: r.code, brand: brand)
                m.manualPesin = r.newPesinCuval
                context.insert(m)
            }
        }
        try? context.save()
        isSaved = true
    }

    private func sharePDF() {
        isGenerating = true
        let pdfRows = previewRows.map {
            MaliyetTabloPDFService.BulkRow(
                code: $0.code, name: $0.name,
                oldPesin: $0.oldPesinCuval, newPesin: $0.newPesinCuval,
                lastPublishedPesin: $0.lastPublishedPesin
            )
        }
        let capturedBrand = brand
        let capturedDelta = reportDeltaTL
        Task.detached(priority: .userInitiated) {
            let data = MaliyetTabloPDFService.generateTopluGuncellemeRaporu(
                rows: pdfRows, brand: capturedBrand, deltaTL: capturedDelta
            )
            let url = PricingPDFService.writeToTemp(data: data, filename: "TopluFiyatGuncelleme")
            await MainActor.run {
                isGenerating = false
                shareURL     = url
                showShare    = url != nil
            }
        }
    }
}
