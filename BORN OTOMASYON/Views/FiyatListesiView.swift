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

    @Query(sort: \PriceListArchive.savedAt, order: .reverse) private var allArchives: [PriceListArchive]

    @AppStorage("pricing_vade_tek_cekim") private var vadeTekCekim: Double = 2.8
    @AppStorage("pricing_vade_30gun")     private var vade30:       Double = 4.5
    @AppStorage("pricing_vade_60gun")     private var vade60:       Double = 9.2
    @AppStorage("pricing_vade_90gun")     private var vade90:       Double = 14.1
    @AppStorage("pricing_list_period")    private var period:        String = ""

    @State private var revision:           String = ""
    @State private var isGenerating        = false
    @State private var shareURL:           URL?  = nil
    @State private var showShare                 = false
    // Üretim sonrası arşivlenecek yayın bilgisi (nil = sadece taslak, kayıt yok)
    @State private var pendingPublish:     (file: String, prices: [PriceSnap])? = nil

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
                    HStack {
                        Text("Revizyon No")
                        Spacer()
                        TextField("örn: 2026-07", text: $revision)
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
                    // Taslak — sadece paylaş, kayıt etme
                    Button {
                        generate(publish: false)
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

                    // Yayınla — piyasaya sun + arşive kaydet (karşılaştırma için fiyat snapshot'ı)
                    Button {
                        generate(publish: true)
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill").foregroundStyle(.white)
                            Text("Yayınla ve Kaydet").fontWeight(.bold).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(visibleCount == 0 ? Color.gray : Color.green)
                    .disabled(isGenerating || visibleCount == 0)
                } footer: {
                    Text("“Yayınla” listeyi resmi olarak kaydeder; bir sonraki yayınla karşılaştırılıp fiyat değişim raporu üretilir.")
                        .font(.caption2)
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
            .onAppear { suggestRevisionIfNeeded() }
            .onChange(of: pendingPublish?.file) { _, _ in
                guard let pub = pendingPublish else { return }
                let archive = PriceListArchive(
                    brand:       brand,
                    period:      period,
                    fileName:    pub.file,
                    revision:    revision.trimmingCharacters(in: .whitespaces),
                    isPublished: true,
                    prices:      pub.prices
                )
                context.insert(archive)
                try? context.save()
                pendingPublish = nil
            }
        }
    }

    // İlk açılışta revizyon önerisi: "YIL-NN" (NN = bu yıl yayınlanan liste sayısı + 1)
    private func suggestRevisionIfNeeded() {
        guard revision.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let year = Calendar.current.component(.year, from: Date())
        let publishedThisYear = allArchives.filter {
            $0.brand == brand && $0.isPublished &&
            Calendar.current.component(.year, from: $0.savedAt) == year
        }.count
        revision = String(format: "%d-%02d", year, publishedThisYear + 1)
    }

    // PDF'teki peşin fiyatla birebir aynı hesap — karşılaştırma snapshot'ı
    private func buildPriceSnaps() -> [PriceSnap] {
        rows.filter { $0.meta?.isVisible ?? true }.map { row in
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
            return PriceSnap(code: row.formula.code, name: row.formula.name, pesin: pesin)
        }
    }

    // MARK: - PDF üret + paylaş (+ publish ise arşivle)

    private func generate(publish: Bool) {
        isGenerating = true

        // Tüm SwiftData model verileri ve view property'leri main thread'de yakala
        let capturedRows   = rows
        let capturedBrand  = brand
        let capturedPeriod = period
        let capturedRev    = revision.trimmingCharacters(in: .whitespaces)
        let config         = vadeConfig
        let vals           = (ipCuval, firePct, elektrik, nakliye, iscilik, globalKarPct)
        let capturedExtra  = extraItems
        let capturedAntet  = antetImage
        let katInfo        = kategoriler.map { (name: $0.name, color: $0.uiColor, order: $0.orderIndex) }
        let snaps          = publish ? buildPriceSnaps() : []

        Task.detached(priority: .userInitiated) {
            let data = PricingPDFService.generate(
                rows: capturedRows, brand: capturedBrand,
                antetImage: capturedAntet,
                kategoriInfo: katInfo.isEmpty ? nil : katInfo,
                ipCuval: vals.0, firePct: vals.1,
                elektrik: vals.2, nakliye: vals.3,
                iscilik: vals.4, globalKarPct: vals.5,
                vade: config, period: capturedPeriod,
                revision: capturedRev,
                extraItems: capturedExtra
            )

            // Yayınlanıyorsa kalıcı dosya olarak Documents'a yaz
            var savedFile: String? = nil
            if publish {
                let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HHmm"
                let dateStr  = df.string(from: Date())
                let filename = "FiyatListesi_\(capturedBrand)_\(dateStr).pdf"
                if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? data.write(to: docsDir.appendingPathComponent(filename))
                    savedFile = filename
                }
            }

            // Paylaşım için geçici URL
            let periodStr = capturedPeriod.isEmpty ? "" : "_\(capturedPeriod)"
            let tempURL   = PricingPDFService.writeToTemp(data: data,
                                                          filename: "FiyatListesi\(periodStr)")
            await MainActor.run {
                isGenerating = false
                shareURL     = tempURL
                showShare    = tempURL != nil
                if publish, let savedFile { pendingPublish = (file: savedFile, prices: snaps) }
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
