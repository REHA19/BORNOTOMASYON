import SwiftUI

// MARK: - İskonto & Net Kar Analizi

struct IskontoAnalizView: View {
    let rows:         [(formula: BlendFormula, meta: ProductPricingMeta?)]
    let ipCuval:      Double
    let firePct:      Double
    let elektrik:     Double
    let nakliye:      Double
    let iscilik:      Double
    let globalKarPct: Double
    var extraItems: [(value: Double, isPercent: Bool)] = []

    @Environment(\.dismiss) private var dismiss

    // Vade % — FiyatListesiView ile aynı AppStorage anahtarları
    @AppStorage("pricing_vade_tek_cekim") private var vadeTekCekim: Double = 2.8
    @AppStorage("pricing_vade_30gun")     private var vade30:       Double = 4.5
    @AppStorage("pricing_vade_60gun")     private var vade60:       Double = 9.2
    @AppStorage("pricing_vade_90gun")     private var vade90:       Double = 14.1

    @State private var selectedBarem: Int    = 0      // 0=Peşin 1=TekÇekim 2=30g 3=60g 4=90g
    @State private var iskontoStr:    String = "0"
    @State private var birimTon:      Bool   = false  // false=çuval  true=ton

    private let baremAdlari = ["Peşin", "Tek Çekim", "30 Gün", "60 Gün", "90 Gün"]

    private var iskontoPct: Double {
        Double(iskontoStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func vadePct(_ idx: Int) -> Double {
        switch idx {
        case 1: return vadeTekCekim
        case 2: return vade30
        case 3: return vade60
        case 4: return vade90
        default: return 0
        }
    }

    // ── Hesaplama ──────────────────────────────────────────────────────

    private var analizSatirlar: [AnalizSatir] {
        rows.filter { $0.meta?.isVisible ?? true }.compactMap { formula, meta in
            let rasyon = formula.currentCostTL > 0 ? formula.currentCostTL : formula.recordedCostTL
            guard rasyon > 0 else { return nil }

            let effKar = (meta?.overrideKarPct ?? -1) >= 0 ? meta!.overrideKarPct : globalKarPct
            let bagKg  = meta?.bagKg ?? 50

            let calc = PricingCalc.calculate(
                rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                karPct: effKar, bagKg: bagKg, extraItems: extraItems
            )

            // Seçili barem (çuval cinsinden)
            let baremCuval = calc.vadePrice(pct: vadePct(selectedBarem))
            let baremTon   = baremCuval / (Double(bagKg) / 1000)
            let baremFiyat = birimTon ? baremTon : baremCuval

            // Net satış fiyatı (iskonto uygulandıktan sonra)
            let netSatis = baremFiyat * (1 - iskontoPct / 100)

            // Maliyet (rasyon + tüm giderler, karsız) — aynı birimde
            let maliyetTon   = calc.toplam
            let maliyetCuval = calc.toplam * Double(bagKg) / 1000
            let maliyet      = birimTon ? maliyetTon : maliyetCuval

            let netKar    = netSatis - maliyet
            let netKarPct = maliyet > 0 ? (netKar / maliyet) * 100 : 0

            return AnalizSatir(
                formula:       formula,
                meta:          meta,
                baremFiyat:    baremFiyat,
                iskonto:       baremFiyat - netSatis,
                netSatis:      netSatis,
                maliyet:       maliyet,
                netKar:        netKar,
                netKarPct:     netKarPct,
                bagKg:         bagKg
            )
        }
    }

    // ── Body ───────────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            List {

                // ── Parametreler ───────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("İskonto Uygulanacak Barem")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Barem", selection: $selectedBarem) {
                            ForEach(0..<baremAdlari.count, id: \.self) { i in
                                Text(baremAdlari[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("İskonto %")
                        Spacer()
                        TextField("0", text: $iskontoStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("%").font(.caption).foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Hesaplama Birimi")
                        Spacer()
                        Picker("Birim", selection: $birimTon) {
                            Text("Çuval").tag(false)
                            Text("Ton").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                } header: {
                    Text("Analiz Parametreleri")
                }

                // ── Ürün analiz listesi ────────────────────────────────
                let satirlar = analizSatirlar

                if satirlar.isEmpty {
                    ContentUnavailableView(
                        "Ürün Yok",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Bu marka için görünür ürün bulunmuyor.")
                    )
                } else {
                    Section {
                        ForEach(satirlar, id: \.formula.code) { satir in
                            AnalizSatirRow(satir: satir, birimTon: birimTon)
                        }
                    } header: {
                        HStack {
                            Text("Ürünler (\(satirlar.count))")
                            Spacer()
                            Text(birimTon ? "₺ / ton" : "₺ / çuval")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    // ── Özet ──────────────────────────────────────────
                    Section("Özet") {
                        let avgPct   = satirlar.map { $0.netKarPct }.reduce(0, +) / Double(satirlar.count)
                        let posCount = satirlar.filter { $0.netKarPct > 0 }.count
                        let negCount = satirlar.count - posCount

                        LabeledContent("Ortalama Net Kar %") {
                            Text(String(format: "%+.2f%%", avgPct))
                                .font(.headline)
                                .foregroundStyle(avgPct >= 0 ? Color.green : Color.red)
                        }
                        LabeledContent("Kârlı / Zararlı Ürün") {
                            HStack(spacing: 6) {
                                Label("\(posCount)", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Label("\(negCount)", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .font(.subheadline)
                        }
                        LabeledContent("Uygulanan İskonto") {
                            Text(String(format: "%.2f%%", iskontoPct))
                                .foregroundStyle(.orange)
                        }
                        LabeledContent("Barem") {
                            Text(baremAdlari[selectedBarem])
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("İskonto & Net Kar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Veri modeli

struct AnalizSatir {
    let formula:    BlendFormula
    let meta:       ProductPricingMeta?
    let baremFiyat: Double
    let iskonto:    Double
    let netSatis:   Double
    let maliyet:    Double
    let netKar:     Double
    let netKarPct:  Double
    let bagKg:      Int
}

// MARK: - Satır görünümü

private struct AnalizSatirRow: View {
    let satir:    AnalizSatir
    let birimTon: Bool

    private var karRenk: Color { satir.netKarPct >= 0 ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {

            // Başlık satırı
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(satir.formula.name).font(.subheadline.bold())
                    HStack(spacing: 5) {
                        Text(satir.formula.code)
                            .font(.caption2).foregroundStyle(.secondary)
                        if let m = satir.meta, !m.form.isEmpty {
                            Text(m.form).font(.caption2).foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.blue.opacity(0.7), in: Capsule())
                        }
                        Text("\(satir.bagKg) kg")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // Net Kar % — büyük badge
                VStack(spacing: 1) {
                    Text(String(format: "%+.2f%%", satir.netKarPct))
                        .font(.title3.bold())
                        .foregroundStyle(karRenk)
                    Text("Net Kar")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            // Fiyat şeridi: Barem → İskonto → Net Satış | Maliyet | Net Kar ₺
            HStack(spacing: 3) {
                chip("Barem",     fmt(satir.baremFiyat), .primary)
                arrowMinus
                chip("İskonto",   fmt(satir.iskonto),    .orange)
                arrowEquals
                chip("Net Satış", fmt(satir.netSatis),   .blue)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Text("Maliyet:").font(.caption2).foregroundStyle(.secondary)
                        Text(fmt(satir.maliyet) + " ₺").font(.caption2.bold())
                    }
                    HStack(spacing: 3) {
                        Text("Kar:").font(.caption2).foregroundStyle(.secondary)
                        Text(fmt(satir.netKar) + " ₺")
                            .font(.caption.bold())
                            .foregroundStyle(karRenk)
                    }
                }
            }
        }
        .padding(.vertical, 5)
        // Zararlıysa hafif kırmızı arka plan
        .listRowBackground(satir.netKarPct < 0
            ? Color.red.opacity(0.06)
            : Color.clear)
    }

    // ── Yardımcı ──────────────────────────────────────────────────────

    private func chip(_ label: String, _ val: String, _ clr: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 7.5)).foregroundStyle(.secondary)
            Text(val).font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(clr)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 4))
    }

    private var arrowMinus: some View {
        Image(systemName: "minus")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 1)
    }

    private var arrowEquals: some View {
        Image(systemName: "equal")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 1)
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = Locale(identifier: "tr_TR")
        n.numberStyle = .decimal
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }
}
