import SwiftUI

// MARK: - Yem Bayi Fiyat Listesi Ekranı

struct FiyatListesiView: View {
    let rows:           [(formula: BlendFormula, meta: ProductPricingMeta?)]
    let ipCuval:        Double
    let firePct:        Double
    let elektrik:       Double
    let nakliye:        Double
    let iscilik:        Double
    let globalKarPct:   Double

    @Environment(\.dismiss) private var dismiss

    // Vade farkları (AppStorage — kalıcı)
    @AppStorage("pricing_vade_tek_cekim") private var vadeTekCekim: Double = 2.8
    @AppStorage("pricing_vade_30gun")     private var vade30:       Double = 4.5
    @AppStorage("pricing_vade_60gun")     private var vade60:       Double = 9.2
    @AppStorage("pricing_vade_90gun")     private var vade90:       Double = 14.1
    @AppStorage("pricing_list_period")    private var period:        String = ""

    @State private var isGenerating = false
    @State private var shareURL:     URL?   = nil
    @State private var showShare     = false

    private var vadeConfig: PricingPDFService.VadeConfig {
        PricingPDFService.VadeConfig(
            tekCekim: vadeTekCekim,
            gun30:    vade30,
            gun60:    vade60,
            gun90:    vade90
        )
    }

    private var visibleCount: Int {
        rows.filter { $0.meta?.isVisible ?? true }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                // Dönem
                Section("Liste Bilgisi") {
                    HStack {
                        Text("Dönem / Tarih")
                        Spacer()
                        TextField("örn: 2026-06", text: $period)
                            .multilineTextAlignment(.trailing)
                            .font(.subheadline)
                    }
                    LabeledContent("Listede Ürün Sayısı", value: "\(visibleCount) ürün")
                }

                // Vade farkları
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

                // Örnek hesap
                Section("Örnek Hesap (ilk ürün)") {
                    if let first = rows.first(where: { ($0.meta?.isVisible ?? true) }) {
                        let rasyon = first.formula.currentCostTL > 0 ? first.formula.currentCostTL : first.formula.recordedCostTL
                        let effKar = (first.meta?.overrideKarPct ?? -1) >= 0 ? first.meta!.overrideKarPct : globalKarPct
                        let bagKg  = first.meta?.bagKg ?? 50
                        let calc   = PricingCalc.calculate(
                            rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                            karPct: effKar, bagKg: bagKg
                        )
                        let pesin = calc.pesin
                        Group {
                            LabeledContent(first.formula.name) { EmptyView() }
                                .font(.caption2).foregroundStyle(.secondary)
                            LabeledContent("Peşin")        { Text(fmt(pesin) + " ₺").bold().foregroundStyle(.orange) }
                            LabeledContent("Tek Çekim")    { Text(fmt(calc.vadePrice(pct: vadeTekCekim)) + " ₺") }
                            LabeledContent("30 Gün")       { Text(fmt(calc.vadePrice(pct: vade30)) + " ₺") }
                            LabeledContent("60 Gün")       { Text(fmt(calc.vadePrice(pct: vade60)) + " ₺") }
                            LabeledContent("90 Gün")       { Text(fmt(calc.vadePrice(pct: vade90)) + " ₺") }
                        }
                        .font(.subheadline)
                    }
                }

                // PDF çıktı butonu
                Section {
                    Button {
                        generateAndShare()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView().scaleEffect(0.8)
                                Text("Oluşturuluyor…")
                            } else {
                                Image(systemName: "doc.richtext.fill")
                                    .foregroundStyle(.orange)
                                Text("PDF Oluştur ve Paylaş")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(isGenerating || visibleCount == 0)
                }
            }
            .navigationTitle("Fiyat Listesi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ActivityView(url: url)
                }
            }
        }
    }

    // MARK: - PDF üret ve paylaş

    private func generateAndShare() {
        isGenerating = true
        Task.detached(priority: .userInitiated) {
            let data = PricingPDFService.generate(
                rows: rows,
                ipCuval: ipCuval, firePct: firePct,
                elektrik: elektrik, nakliye: nakliye,
                iscilik: iscilik, globalKarPct: globalKarPct,
                vade: vadeConfig,
                period: period
            )
            let periodStr = period.isEmpty ? "" : "_\(period)"
            let url = PricingPDFService.writeToTemp(
                data: data,
                filename: "FiyatListesi\(periodStr)"
            )
            await MainActor.run {
                isGenerating = false
                shareURL     = url
                showShare    = url != nil
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale               = Locale(identifier: "tr_TR")
        n.numberStyle          = .decimal
        n.minimumFractionDigits = 2
        n.maximumFractionDigits = 2
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
        if let v = Double(clean) { value = v }
        else { text = String(format: "%.1f", value) }
    }
}

// MARK: - UIActivityViewController köprüsü

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
