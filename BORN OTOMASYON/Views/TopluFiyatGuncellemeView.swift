import SwiftUI
import SwiftData

// MARK: - Toplu Fiyat Güncelleme (TL bazlı zam/indirim)
//
// Akış: ürün seç (serbest çoklu seçim) → TL tutar gir → Önizle (hesapla, henüz kaydetme) →
// Kaydet (ProductPricingMeta.manualPesin'e kalıcı yaz) → PDF paylaş.
// "Eski peşin" hesabı FiyatListesiView.buildPriceSnaps() ile birebir aynı mantığı kullanır.

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

    @State private var selectedCodes: Set<String> = []
    @State private var deltaText:     String      = ""
    @State private var previewRows:   [BulkChangeRow] = []
    @State private var isSaved        = false
    @State private var isGenerating   = false
    @State private var shareURL:      URL?  = nil
    @State private var showShare      = false

    struct BulkChangeRow: Identifiable {
        let id = UUID()
        let code:               String
        let name:               String
        let oldPesin:           Double
        let newPesin:           Double
        let lastPublishedPesin: Double?
    }

    private var deltaTL: Double {
        Double(deltaText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var lastPublished: PriceListArchive? {
        PriceListArchive.lastPublished(brand: brand, in: allArchives)
    }

    // FiyatListesiView.buildPriceSnaps() ile aynı hesap — şu an geçerli (kaydedilmemiş) peşin fiyat
    private func currentPesin(_ row: (formula: BlendFormula, meta: ProductPricingMeta?)) -> Double {
        let rasyon = row.formula.currentCostTL > 0 ? row.formula.currentCostTL : row.formula.recordedCostTL
        let effKar = (row.meta?.overrideKarPct ?? -1) >= 0 ? row.meta!.overrideKarPct : globalKarPct
        let bagKg  = row.meta?.bagKg ?? 50
        let calc   = PricingCalc.calculate(
            rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
            karPct: effKar, bagKg: bagKg, extraItems: extraItems
        )
        let manual = row.meta?.manualPesin ?? -1
        return manual >= 0 ? manual : calc.pesin
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
                    Text("Önizle, hesaplar ve aşağıda gösterir — henüz hiçbir şey kaydedilmez.")
                        .font(.caption2)
                }

                if !previewRows.isEmpty {
                    Section {
                        ForEach(previewRows) { r in previewRowView(r) }
                    } header: {
                        Text("Önizleme (\(previewRows.count) ürün)")
                    } footer: {
                        Text("\"Liste Farkı\" sütunu, son yayınlanan (\(lastPublished?.revision ?? lastPublished?.period ?? "—")) fiyat listesine göre farkı gösterir.")
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
                                    Text("PDF Olarak Paylaş")
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

    @ViewBuilder
    private func previewRowView(_ r: BulkChangeRow) -> some View {
        let fark = r.newPesin - r.oldPesin
        let pct  = r.oldPesin > 0 ? fark / r.oldPesin * 100 : 0
        VStack(alignment: .leading, spacing: 4) {
            Text(r.name).font(.subheadline.bold())
            HStack(spacing: 6) {
                Text(String(format: "%.2f ₺", r.oldPesin)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                Text(String(format: "%.2f ₺", r.newPesin)).font(.subheadline.bold().monospacedDigit())
                Text(String(format: "(%+.2f ₺, %+.1f%%)", fark, pct))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(fark > 0 ? .red : fark < 0 ? .green : .secondary)
            }
            if let lp = r.lastPublishedPesin {
                let listFark = r.newPesin - lp
                Text(String(format: "Son listeye göre: %.2f ₺ → %+.2f ₺", lp, listFark))
                    .font(.caption2).foregroundStyle(.indigo)
            } else {
                Text("Son yayınlanan listede yok").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func buildPreview() {
        let archive = lastPublished
        let publishedByCode = Dictionary(
            (archive?.prices ?? []).map { ($0.code, $0.pesin) }, uniquingKeysWith: { a, _ in a }
        )
        previewRows = rows
            .filter { selectedCodes.contains($0.formula.code) }
            .map { row in
                let old = currentPesin(row)
                return BulkChangeRow(
                    code: row.formula.code, name: row.formula.name,
                    oldPesin: old, newPesin: max(0, old + deltaTL),
                    lastPublishedPesin: publishedByCode[row.formula.code]
                )
            }
        isSaved = false
    }

    private func saveChanges() {
        for r in previewRows {
            guard let row = rows.first(where: { $0.formula.code == r.code }) else { continue }
            if let meta = row.meta {
                meta.manualPesin = r.newPesin
            } else {
                let m = ProductPricingMeta(formulaCode: r.code, brand: brand)
                m.manualPesin = r.newPesin
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
                oldPesin: $0.oldPesin, newPesin: $0.newPesin,
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
