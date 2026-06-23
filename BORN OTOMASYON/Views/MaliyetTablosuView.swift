import SwiftUI
import SwiftData

// MARK: - Tüm Formüller Maliyet Tablosu
//
// Seçili markaya ait tüm ürünleri (mevcut ÜRÜNLER listesiyle aynı filtre) tek tabloda
// gösterir: rasyon maliyeti + gider kalemleri + kar% + peşin fiyat + önceki kayıtlı
// (son yayınlanan listedeki) fiyat. PDF olarak paylaşılabilir.

struct MaliyetTablosuView: View {
    let rows:         [(formula: BlendFormula, meta: ProductPricingMeta?)]
    let brand:        String
    let ipCuval:      Double
    let firePct:      Double
    let elektrik:     Double
    let nakliye:      Double
    let iscilik:      Double
    let globalKarPct: Double
    var extraItems:   [(value: Double, isPercent: Bool)] = []

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PriceListArchive.savedAt, order: .reverse) private var allArchives: [PriceListArchive]

    @State private var isGenerating = false
    @State private var shareURL:    URL? = nil
    @State private var showShare    = false

    struct CostRow: Identifiable {
        let id = UUID()
        let code:               String
        let name:               String
        let rasyon:              Double
        let toplamMaliyet:       Double
        let karPct:              Double
        let pesin:               Double
        let lastPublishedPesin:  Double?
    }

    private var lastPublished: PriceListArchive? {
        PriceListArchive.lastPublished(brand: brand, in: allArchives)
    }

    private var costRows: [CostRow] {
        let publishedByCode = Dictionary(
            (lastPublished?.prices ?? []).map { ($0.code, $0.pesin) }, uniquingKeysWith: { a, _ in a }
        )
        return rows.map { row in
            let rasyon = row.formula.currentCostTL > 0 ? row.formula.currentCostTL : row.formula.recordedCostTL
            let effKar = (row.meta?.overrideKarPct ?? -1) >= 0 ? row.meta!.overrideKarPct : globalKarPct
            let bagKg  = row.meta?.bagKg ?? 50
            let calc   = PricingCalc.calculate(
                rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                karPct: effKar, bagKg: bagKg, extraItems: extraItems
            )
            let manual = row.meta?.manualPesin ?? -1
            let pesin  = manual >= 0 ? manual : calc.pesin
            return CostRow(
                code: row.formula.code, name: row.formula.name,
                rasyon: rasyon, toplamMaliyet: calc.toplam, karPct: effKar, pesin: pesin,
                lastPublishedPesin: publishedByCode[row.formula.code]
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            tableHeaderRow
                            ForEach(Array(costRows.enumerated()), id: \.element.id) { idx, r in
                                tableDataRow(r, alt: idx % 2 == 1)
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
        }
    }

    // ── Sabit sütun genişlikleri ──────────────────────────────────────────
    private let wCode: CGFloat = 56, wName: CGFloat = 150, wRasyon: CGFloat = 80,
                wToplam: CGFloat = 80, wKar: CGFloat = 50, wPesin: CGFloat = 80,
                wOnceki: CGFloat = 80, wFark: CGFloat = 80

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            headerCell("Kod", wCode)
            headerCell("Ürün", wName, align: .leading)
            headerCell("Rasyon ₺/t", wRasyon)
            headerCell("Toplam ₺/t", wToplam)
            headerCell("Kar%", wKar)
            headerCell("Peşin ₺", wPesin)
            headerCell("Önceki ₺", wOnceki)
            headerCell("Fark ₺", wFark)
        }
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground))
    }

    private func headerCell(_ text: String, _ width: CGFloat, align: TextAlignment = .center) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(.secondary)
            .frame(width: width, alignment: align == .leading ? .leading : .center)
            .multilineTextAlignment(align)
    }

    @ViewBuilder
    private func tableDataRow(_ r: CostRow, alt: Bool) -> some View {
        let fark = r.lastPublishedPesin.map { r.pesin - $0 }
        HStack(spacing: 0) {
            dataCell(r.code, wCode)
            dataCell(r.name, wName, align: .leading)
            dataCell(String(format: "%.0f", r.rasyon), wRasyon)
            dataCell(String(format: "%.0f", r.toplamMaliyet), wToplam)
            dataCell(String(format: "%.1f", r.karPct), wKar)
            dataCell(String(format: "%.2f", r.pesin), wPesin, bold: true)
            dataCell(r.lastPublishedPesin.map { String(format: "%.2f", $0) } ?? "—", wOnceki)
            dataCell(fark.map { String(format: "%+.2f", $0) } ?? "—", wFark,
                     color: (fark ?? 0) > 0.001 ? .red : (fark ?? 0) < -0.001 ? .green : .secondary)
        }
        .padding(.vertical, 4)
        .background(alt ? Color(.systemGroupedBackground) : Color.clear)
    }

    private func dataCell(_ text: String, _ width: CGFloat, align: TextAlignment = .center,
                          bold: Bool = false, color: Color = .primary) -> some View {
        Text(text)
            .font(bold ? .caption.bold().monospacedDigit() : .caption.monospacedDigit())
            .foregroundStyle(color)
            .frame(width: width, alignment: align == .leading ? .leading : .center)
            .lineLimit(1)
    }

    private func sharePDF() {
        isGenerating = true
        let pdfRows = costRows.map {
            MaliyetTabloPDFService.CostRow(
                code: $0.code, name: $0.name, rasyon: $0.rasyon,
                toplamMaliyet: $0.toplamMaliyet, karPct: $0.karPct, pesin: $0.pesin,
                lastPublishedPesin: $0.lastPublishedPesin
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
