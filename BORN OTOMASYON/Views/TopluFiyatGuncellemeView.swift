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
    @State private var previewRows:   [BulkChangeRow] = []
    @State private var isSaved        = false
    @State private var isGenerating   = false
    @State private var shareURL:      URL?  = nil
    @State private var showShare      = false

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

    private var deltaTL: Double {
        Double(deltaText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var lastPublished: PriceListArchive? {
        PriceListArchive.lastPublished(brand: brand, in: allArchives)
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
                Section {
                    HStack {
                        Text("Zam / İndirim Tutarı (₺)")
                        Spacer()
                        TextField("örn. 50 veya -30", text: $deltaText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                } footer: {
                    Text("Pozitif tutar zam, negatif tutar indirim uygular. Tutar, seçili ürünlerin güncel peşin fiyatına doğrudan eklenir.")
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
                    ForEach(rows, id: \.formula.code) { row in
                        Button {
                            if selectedCodes.contains(row.formula.code) {
                                selectedCodes.remove(row.formula.code)
                            } else {
                                selectedCodes.insert(row.formula.code)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedCodes.contains(row.formula.code) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedCodes.contains(row.formula.code) ? .blue : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.formula.name).font(.subheadline).foregroundStyle(.primary)
                                    Text(row.meta?.categoryGroup.isEmpty == false ? row.meta!.categoryGroup : "Kategorisiz")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.2f ₺", currentPesin(row)))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Ürünler")
                }

                Section {
                    Button {
                        buildPreview()
                    } label: {
                        Label("Önizle", systemImage: "eye")
                    }
                    .disabled(selectedCodes.isEmpty || deltaTL == 0)
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
                        Text("Önizleme (\(previewRows.count) ürün) — Peşin/Kredi Kartı/30-60-90 Gün, Çuval+Ton")
                    } footer: {
                        Text("Son yayınlanan liste: \(lastPublished?.revision ?? lastPublished?.period ?? "—"). Eski Kar% ve Eski Fiyat, son yayınlanan listeye göre hesaplanır.")
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

    private let wCode: CGFloat = 50, wName: CGFloat = 140, wMoney: CGFloat = 64, wKar: CGFloat = 48

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            headerCell("Kod", wCode)
            headerCell("Ürün", wName, align: .leading)
            headerCell("Rasyon ₺/t", wMoney)
            headerCell("Gider ₺/t", wMoney)
            headerCell("Toplam ₺/t", wMoney)
            headerCell("Eski Çuval", wMoney)
            headerCell("Eski Ton", wMoney)
            headerCell("Eski Kar%", wKar)
            tierHeader("Peşin")
            tierHeader("Kredi K.")
            tierHeader("30 Gün")
            tierHeader("60 Gün")
            tierHeader("90 Gün")
        }
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    @ViewBuilder
    private func tierHeader(_ label: String) -> some View {
        headerCell("\(label) Çuval", wMoney)
        headerCell("\(label) Ton", wMoney)
        headerCell("\(label) Kar%", wKar)
    }

    private func headerCell(_ text: String, _ width: CGFloat, align: TextAlignment = .center) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(.secondary)
            .frame(width: width, alignment: align == .leading ? .leading : .center)
            .multilineTextAlignment(align)
    }

    @ViewBuilder
    private func tableDataRow(_ r: BulkChangeRow, alt: Bool) -> some View {
        let pesinTier = r.tier(0, toplamMaliyet: r.toplamMaliyet, bagKg: r.bagKg)
        let kkTier    = r.tier(vadeTekCekim, toplamMaliyet: r.toplamMaliyet, bagKg: r.bagKg)
        let g30Tier   = r.tier(vade30, toplamMaliyet: r.toplamMaliyet, bagKg: r.bagKg)
        let g60Tier   = r.tier(vade60, toplamMaliyet: r.toplamMaliyet, bagKg: r.bagKg)
        let g90Tier   = r.tier(vade90, toplamMaliyet: r.toplamMaliyet, bagKg: r.bagKg)
        HStack(spacing: 0) {
            dataCell(r.code, wCode)
            dataCell(r.name, wName, align: .leading)
            dataCell(String(format: "%.0f", r.rasyon), wMoney)
            dataCell(String(format: "%.0f", r.giderToplam), wMoney)
            dataCell(String(format: "%.0f", r.toplamMaliyet), wMoney)
            dataCell(String(format: "%.2f", r.oldPesinCuval), wMoney)
            dataCell(String(format: "%.0f", r.oldPesinCuval / Double(r.bagKg) * 1000), wMoney)
            dataCell(r.oldKarPct.map { String(format: "%.1f", $0) } ?? "—", wKar)
            tierCells(pesinTier)
            tierCells(kkTier)
            tierCells(g30Tier)
            tierCells(g60Tier)
            tierCells(g90Tier)
        }
        .padding(.vertical, 4)
        .background(alt ? Color(.systemGroupedBackground) : Color.clear)
    }

    @ViewBuilder
    private func tierCells(_ t: TierValue) -> some View {
        dataCell(String(format: "%.2f", t.cuval), wMoney, bold: true)
        dataCell(String(format: "%.0f", t.ton), wMoney)
        dataCell(String(format: "%.1f", t.karPct), wKar,
                 color: t.karPct < 0 ? .red : .green)
    }

    private func dataCell(_ text: String, _ width: CGFloat, align: TextAlignment = .center,
                          bold: Bool = false, color: Color = .primary) -> some View {
        Text(text)
            .font(bold ? .caption.bold().monospacedDigit() : .caption.monospacedDigit())
            .foregroundStyle(color)
            .frame(width: width, alignment: align == .leading ? .leading : .center)
            .lineLimit(1)
    }

    // ── Hesaplama / kaydetme / paylaşma ────────────────────────────────────

    private func buildPreview() {
        let archive = lastPublished
        let publishedByCode = Dictionary(
            (archive?.prices ?? []).map { ($0.code, $0.pesin) }, uniquingKeysWith: { a, _ in a }
        )
        previewRows = rows
            .filter { selectedCodes.contains($0.formula.code) }
            .map { row -> BulkChangeRow in
                let c = calc(row)
                let lastPub = publishedByCode[row.formula.code]
                let oldPesinCuval = lastPub ?? c.pesin0
                let newPesinCuval = max(0, c.pesin0 + deltaTL)
                let oldKar = lastPub.map { Self.karPct(price: $0, toplamMaliyet: c.toplam, bagKg: c.bagKg) }
                let newKar = Self.karPct(price: newPesinCuval, toplamMaliyet: c.toplam, bagKg: c.bagKg)
                return BulkChangeRow(
                    code: row.formula.code, name: row.formula.name,
                    rasyon: c.rasyon, giderToplam: c.toplam - c.rasyon, toplamMaliyet: c.toplam,
                    bagKg: c.bagKg,
                    oldPesinCuval: oldPesinCuval, oldKarPct: oldKar,
                    newPesinCuval: newPesinCuval, newKarPct: newKar,
                    lastPublishedPesin: lastPub
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
        let capturedDelta = deltaTL
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
