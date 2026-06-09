import SwiftUI
import SwiftData

// MARK: - Yem Bayi Fiyat Listesi Ekranı

struct FiyatListesiView: View {
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
    var extraItems:   [(value: Double, isPercent: Bool)] = []
    var antetImage:   UIImage?                          = nil
    var kategoriler:  [KategoriTanim]                   = []

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage("pricing_vade_tek_cekim") private var vadeTekCekim: Double = 2.8
    @AppStorage("pricing_vade_30gun")     private var vade30:       Double = 4.5
    @AppStorage("pricing_vade_60gun")     private var vade60:       Double = 9.2
    @AppStorage("pricing_vade_90gun")     private var vade90:       Double = 14.1
    @AppStorage("pricing_list_period")    private var period:        String = ""

    @State private var isGenerating        = false
    @State private var shareURL:           URL?  = nil
    @State private var showShare                 = false
    @State private var pendingArchiveFile: String? = nil

    private var vadeConfig: PricingPDFService.VadeConfig {
        PricingPDFService.VadeConfig(
            tekCekim: vadeTekCekim, gun30: vade30, gun60: vade60, gun90: vade90
        )
    }

    private var visibleCount: Int {
        rows.filter { $0.meta?.isVisible ?? true }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Liste Bilgisi") {
                    LabeledContent("Marka") {
                        Text(brand).bold().foregroundStyle(.orange)
                    }
                    HStack {
                        Text("Dönem / Tarih")
                        Spacer()
                        TextField("örn: Haziran 2026", text: $period)
                            .multilineTextAlignment(.trailing)
                            .font(.subheadline)
                    }
                    LabeledContent("Listede Ürün Sayısı", value: "\(visibleCount) ürün")
                }

                Section {
                    VadeRow(label: "Tek Çekim Kredi Kartı", value: $vadeTekCekim)
                    VadeRow(label: "30 Gün Vadeli",          value: $vade30)
                    VadeRow(label: "60 Gün Vadeli",          value: $vade60)
                    VadeRow(label: "90 Gün Vadeli",          value: $vade90)
                } header: {
                    Text("Vade Farkları")
                } footer: {
                    Text("Her vade için peşin fiyata eklenecek yüzde farkıdır.")
                        .font(.caption2)
                }

                Section("Örnek Hesap (ilk ürün)") {
                    if let first = rows.first(where: { $0.meta?.isVisible ?? true }) {
                        let rasyon = first.formula.currentCostTL > 0 ? first.formula.currentCostTL : first.formula.recordedCostTL
                        let effKar = (first.meta?.overrideKarPct ?? -1) >= 0 ? first.meta!.overrideKarPct : globalKarPct
                        let bagKg  = first.meta?.bagKg ?? 50
                        let calc   = PricingCalc.calculate(
                            rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                            karPct: effKar, bagKg: bagKg
                        )
                        Group {
                            LabeledContent(first.formula.name) { EmptyView() }
                                .font(.caption2).foregroundStyle(.secondary)
                            LabeledContent("Peşin")     { Text(fmt(calc.pesin) + " ₺").bold().foregroundStyle(.orange) }
                            LabeledContent("Tek Çekim") { Text(fmt(calc.vadePrice(pct: vadeTekCekim)) + " ₺") }
                            LabeledContent("30 Gün")    { Text(fmt(calc.vadePrice(pct: vade30)) + " ₺") }
                            LabeledContent("60 Gün")    { Text(fmt(calc.vadePrice(pct: vade60)) + " ₺") }
                            LabeledContent("90 Gün")    { Text(fmt(calc.vadePrice(pct: vade90)) + " ₺") }
                        }
                        .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        generateAndShare()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView().scaleEffect(0.8)
                                Text("Oluşturuluyor…")
                            } else {
                                Image(systemName: "doc.richtext.fill").foregroundStyle(.orange)
                                Text("PDF Oluştur ve Paylaş").fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(isGenerating || visibleCount == 0)
                }
            }
            .navigationTitle("\(brand) Fiyat Listesi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL { ShareSheet(url: url) }
            }
            .onChange(of: pendingArchiveFile) { _, filename in
                guard let filename else { return }
                let archive = PriceListArchive(brand: brand, period: period, fileName: filename)
                context.insert(archive)
                try? context.save()
                pendingArchiveFile = nil
            }
        }
    }

    // MARK: - PDF üret + arşivle + paylaş

    private func generateAndShare() {
        isGenerating = true

        // Tüm SwiftData model verileri ve view property'leri main thread'de yakala
        let capturedRows   = rows
        let capturedBrand  = brand
        let capturedPeriod = period
        let config         = vadeConfig
        let vals           = (ipCuval, firePct, elektrik, nakliye, iscilik, globalKarPct)
        let capturedExtra  = extraItems
        let capturedAntet  = antetImage
        let katInfo        = kategoriler.map { (name: $0.name, color: $0.uiColor, order: $0.orderIndex) }

        Task.detached(priority: .userInitiated) {
            let data = PricingPDFService.generate(
                rows: capturedRows, brand: capturedBrand,
                antetImage: capturedAntet,
                kategoriInfo: katInfo.isEmpty ? nil : katInfo,
                ipCuval: vals.0, firePct: vals.1,
                elektrik: vals.2, nakliye: vals.3,
                iscilik: vals.4, globalKarPct: vals.5,
                vade: config, period: capturedPeriod,
                extraItems: capturedExtra
            )

            // Arşiv dosyası: Documents/FiyatListesi_Alapala_2026-06-08_1430.pdf
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HHmm"
            let dateStr  = df.string(from: Date())
            let filename = "FiyatListesi_\(capturedBrand)_\(dateStr).pdf"
            if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? data.write(to: docsDir.appendingPathComponent(filename))
            }

            // Paylaşım için geçici URL
            let periodStr = capturedPeriod.isEmpty ? "" : "_\(capturedPeriod)"
            let tempURL   = PricingPDFService.writeToTemp(data: data,
                                                          filename: "FiyatListesi\(periodStr)")
            await MainActor.run {
                isGenerating       = false
                shareURL           = tempURL
                showShare          = tempURL != nil
                pendingArchiveFile = filename
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = Locale(identifier: "tr_TR")
        n.numberStyle = .decimal
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }
}

// MARK: - Vade yüzde satırı

private struct VadeRow: View {
    let label:    String
    @Binding var value: Double
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            TextField("0.0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .focused($focused)
                .onChange(of: focused) { _, f in if !f { commit() } }
                .onSubmit { commit() }
            Text("%").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { text = String(format: "%.1f", value) }
        .onChange(of: value) { _, v in if !focused { text = String(format: "%.1f", v) } }
    }

    private func commit() {
        let clean = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(clean) { value = v } else { text = String(format: "%.1f", value) }
    }
}

// MARK: - UIActivityViewController köprüsü

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad / macOS Catalyst: popover anchor gerekiyor
        if let scene  = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }) {
            vc.popoverPresentationController?.sourceView = window
            vc.popoverPresentationController?.sourceRect = CGRect(
                x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0
            )
            vc.popoverPresentationController?.permittedArrowDirections = []
        }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
