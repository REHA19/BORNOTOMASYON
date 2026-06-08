import SwiftUI
import SwiftData

// MARK: - Ana Maliyetlendirme Ekranı

struct MaliyetlendirmeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BlendFormula.code)   private var formulas:     [BlendFormula]
    @Query(sort: \ProductPricingMeta.orderIndex) private var metas: [ProductPricingMeta]

    // Global maliyet bileşenleri (AppStorage — cihazda kalıcı)
    @AppStorage("pricing_ip_cuval")     private var ipCuval:  Double = 262
    @AppStorage("pricing_fire_pct")     private var firePct:  Double = 2.0
    @AppStorage("pricing_elektrik_gaz") private var elektrik: Double = 270
    @AppStorage("pricing_nakliye")      private var nakliye:  Double = 700
    @AppStorage("pricing_iscilik")      private var iscilik:  Double = 2000
    @AppStorage("pricing_kar_pct")      private var karPct:   Double = 17

    @State private var showSettings    = false
    @State private var editTarget:     BlendFormula?      = nil
    @State private var showFiyatListesi = false

    // Formül + meta birleştirme
    private var rows: [(formula: BlendFormula, meta: ProductPricingMeta?)] {
        let metaByCode = Dictionary(metas.map { ($0.formulaCode, $0) },
                                    uniquingKeysWith: { first, _ in first })
        return formulas
            .filter { $0.currentCostTL > 0 || $0.recordedCostTL > 0 }
            .sorted { (metaByCode[$0.code]?.orderIndex ?? 999) < (metaByCode[$1.code]?.orderIndex ?? 999) }
            .map { ($0, metaByCode[$0.code]) }
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Global gider ayarları ──────────────────────────────────
                Section {
                    DisclosureGroup(isExpanded: $showSettings) {
                        globalSettingsContent
                    } label: {
                        Label("Global Gider Ayarları", systemImage: "slider.horizontal.3")
                            .font(.subheadline.bold())
                    }
                }

                // ── Ürün listesi ───────────────────────────────────────────
                Section {
                    if rows.isEmpty {
                        ContentUnavailableView(
                            "Maliyet Verisi Yok",
                            systemImage: "chart.bar.doc.horizontal",
                            description: Text("Formüller çözüldükten sonra rasyon maliyetleri burada görünür.")
                        )
                    } else {
                        ForEach(rows, id: \.formula.code) { row in
                            PricingProductRow(
                                formula: row.formula,
                                meta:    row.meta,
                                ipCuval: ipCuval, firePct: firePct,
                                elektrik: elektrik, nakliye: nakliye,
                                iscilik: iscilik, karPct: karPct
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { editTarget = row.formula }
                        }
                    }
                } header: {
                    HStack {
                        Text("Ürünler (\(rows.count))")
                        Spacer()
                        Text("₺/ton → ₺/çuval")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Maliyetlendirme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFiyatListesi = true
                    } label: {
                        Label("Fiyat Listesi", systemImage: "doc.richtext.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .sheet(item: $editTarget) { formula in
                ProductPricingMetaSheet(
                    formula: formula,
                    existingMeta: metas.first { $0.formulaCode == formula.code },
                    ipCuval: ipCuval, firePct: firePct,
                    elektrik: elektrik, nakliye: nakliye,
                    iscilik: iscilik, globalKarPct: karPct
                )
            }
            .sheet(isPresented: $showFiyatListesi) {
                FiyatListesiView(
                    rows: rows,
                    ipCuval: ipCuval, firePct: firePct,
                    elektrik: elektrik, nakliye: nakliye,
                    iscilik: iscilik, globalKarPct: karPct
                )
            }
        }
    }

    // MARK: - Global ayarlar içeriği

    private var globalSettingsContent: some View {
        VStack(spacing: 0) {
            PricingInputRow(label: "İP ÇUVAL",     unit: "₺/ton",  value: $ipCuval)
            PricingInputRow(label: "% Fire",        unit: "%",       value: $firePct)
            PricingInputRow(label: "Elektrik/GAZ",  unit: "₺/ton",  value: $elektrik)
            PricingInputRow(label: "Nakliye",       unit: "₺/ton",  value: $nakliye)
            PricingInputRow(label: "İşçilik",       unit: "₺/ton",  value: $iscilik)
            Divider().padding(.vertical, 4)
            PricingInputRow(label: "Kar Marjı",     unit: "%",       value: $karPct, accent: .orange)
        }
    }
}

// MARK: - Global ayar satırı

private struct PricingInputRow: View {
    let label:  String
    let unit:   String
    @Binding var value: Double
    var accent: Color = .blue

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(accent)
                .frame(minWidth: 110, alignment: .leading)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospacedDigit())
                .focused($focused)
                .onChange(of: focused) { _, nowFocused in if !nowFocused { commit() } }
                .onSubmit { commit() }
            Text(unit)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
        .padding(.vertical, 2)
        .onAppear { text = fmt(value) }
        .onChange(of: value) { _, v in if !focused { text = fmt(v) } }
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.1f", v)
    }

    private func commit() {
        let clean = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(clean) { value = v } else { text = fmt(value) }
    }
}

// MARK: - Ürün satırı

private struct PricingProductRow: View {
    let formula:  BlendFormula
    let meta:     ProductPricingMeta?
    let ipCuval:  Double
    let firePct:  Double
    let elektrik: Double
    let nakliye:  Double
    let iscilik:  Double
    let karPct:   Double

    private var rasyon: Double { formula.currentCostTL > 0 ? formula.currentCostTL : formula.recordedCostTL }
    private var bagKg:  Int    { meta?.bagKg ?? 50 }
    private var effKar: Double { (meta?.overrideKarPct ?? -1) >= 0 ? (meta!.overrideKarPct) : karPct }

    private var calc: PricingCalc {
        PricingCalc.calculate(
            rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
            karPct: effKar, bagKg: bagKg
        )
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = Locale(identifier: "tr_TR")
        n.numberStyle = .decimal
        n.minimumFractionDigits = 2
        n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Başlık satırı
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formula.name)
                        .font(.subheadline.bold())
                    HStack(spacing: 6) {
                        Text(formula.code)
                            .font(.caption).foregroundStyle(.secondary)
                        if let m = meta, !m.form.isEmpty {
                            Text(m.form)
                                .font(.caption2).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.blue.opacity(0.7), in: Capsule())
                        }
                        Text("\(bagKg) kg")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // Peşin Barem (ana fiyat)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmt(calc.pesin) + " ₺")
                        .font(.title3.bold()).foregroundStyle(.orange)
                    Text("Peşin Barem")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let m = meta, m.overrideKarPct >= 0 {
                        Text("KAR: %\(String(format: "%.0f", m.overrideKarPct))")
                            .font(.caption2).foregroundStyle(.purple)
                    } else {
                        Text("KAR: %\(String(format: "%.0f", karPct))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            // Maliyet detay şeridi
            HStack(spacing: 0) {
                costChip("Rasyon", fmt(calc.rasyon))
                costChip("Fire",   fmt(calc.fire))
                costChip("E/G",    fmt(calc.elektrik))
                costChip("Nak.",   fmt(calc.nakliye))
                costChip("İşç.",   fmt(calc.iscilik))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Genel: \(fmt(calc.toplam)) ₺/ton")
                        .font(.caption2.bold()).foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity((meta?.isVisible ?? true) ? 1 : 0.5)
    }

    private func costChip(_ label: String, _ val: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
            Text(val).font(.system(size: 9, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 4))
        .padding(.trailing, 4)
    }
}

// MARK: - Ürün Meta Düzenleme Sheet'i

struct ProductPricingMetaSheet: View {
    let formula:      BlendFormula
    var existingMeta: ProductPricingMeta?
    let ipCuval:   Double
    let firePct:   Double
    let elektrik:  Double
    let nakliye:   Double
    let iscilik:   Double
    let globalKarPct: Double

    @Environment(\.dismiss)       private var dismiss
    @Environment(\.modelContext)  private var context

    @State private var form:          String = "Pelet"
    @State private var categoryGroup: String = ""
    @State private var bagKg:         Int    = 50
    @State private var isVisible:     Bool   = true
    @State private var overrideKarStr: String = ""
    @State private var orderIndex:    Int    = 0
    @State private var logoName:      String = ""

    private let formOptions = ["Pelet-Granül", "Pelet", "Toz", "TANELİ", "Diğer"]
    // Asset catalog'daki logo isimleri — kullanıcı görselleri bu isimlerle ekler
    private let logoOptions = [
        ("", "Yok"),
        ("LogoClassFeed",  "ClassFeed / ClassPeak"),
        ("LogoSpeedCalf",  "Speed Calf"),
        ("LogoCalfmix",    "CALFMİX"),
        ("LogoRobotix",    "ROBOTİX"),
        ("LogoCustom1",    "Özel Logo 1"),
        ("LogoCustom2",    "Özel Logo 2"),
    ]

    private var rasyon: Double { formula.currentCostTL > 0 ? formula.currentCostTL : formula.recordedCostTL }
    private var effKar: Double {
        Double(overrideKarStr.replacingOccurrences(of: ",", with: ".")) ?? globalKarPct
    }

    private var calc: PricingCalc {
        PricingCalc.calculate(
            rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
            karPct: effKar, bagKg: bagKg
        )
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = Locale(identifier: "tr_TR")
        n.numberStyle = .decimal
        n.minimumFractionDigits = 2
        n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Ürün bilgisi (readonly)
                Section("Ürün") {
                    LabeledContent("Kod",  value: formula.code)
                    LabeledContent("Ad",   value: formula.name)
                    LabeledContent("Rasyon Mal.", value: fmt(rasyon) + " ₺/ton")
                }

                // Form ve kategori
                Section("Ürün Özellikleri") {
                    Picker("Form", selection: $form) {
                        ForEach(formOptions, id: \.self) { Text($0) }
                    }
                    HStack {
                        Text("Kategori Grubu")
                        Spacer()
                        TextField("örn: SIĞIR SÜT YEMLERİ (50 kg)", text: $categoryGroup)
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                    }
                    Picker("Çuval Ağırlığı", selection: $bagKg) {
                        Text("50 kg").tag(50)
                        Text("40 kg").tag(40)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Fiyat Listesinde Göster", isOn: $isVisible)
                    // Logo seçici
                    Picker("Logo", selection: $logoName) {
                        ForEach(logoOptions, id: \.0) { val, label in
                            HStack {
                                if !val.isEmpty, UIImage(named: val) != nil {
                                    Image(val).resizable().scaledToFit().frame(width: 24, height: 14)
                                }
                                Text(label)
                            }.tag(val)
                        }
                    }
                }

                // Fiyat hesap
                Section("Fiyat Hesabı") {
                    HStack {
                        Text("Özel KAR %")
                        Spacer()
                        TextField("Boş = global (%\(String(format: "%.0f", globalKarPct)))", text: $overrideKarStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    LabeledContent("Genel Mailyeti") {
                        Text(fmt(calc.toplam) + " ₺/ton")
                            .foregroundStyle(.primary)
                    }
                    LabeledContent("Peşin Barem (\(bagKg) kg)") {
                        Text(fmt(calc.pesin) + " ₺")
                            .font(.headline).foregroundStyle(.orange)
                    }
                }

                Section("Liste Sırası") {
                    Stepper("Sıra: \(orderIndex)", value: $orderIndex, in: 0...999)
                }
            }
            .navigationTitle(formula.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let m = existingMeta else { return }
        form          = m.form
        categoryGroup = m.categoryGroup
        bagKg         = m.bagKg
        isVisible     = m.isVisible
        orderIndex    = m.orderIndex
        logoName      = m.logoName
        if m.overrideKarPct >= 0 {
            overrideKarStr = String(format: "%.1f", m.overrideKarPct)
        }
    }

    private func save() {
        let meta = existingMeta ?? {
            let m = ProductPricingMeta(formulaCode: formula.code)
            context.insert(m)
            return m
        }()
        meta.form           = form
        meta.categoryGroup  = categoryGroup
        meta.bagKg          = bagKg
        meta.isVisible      = isVisible
        meta.orderIndex     = orderIndex
        meta.logoName       = logoName
        let karVal = Double(overrideKarStr.replacingOccurrences(of: ",", with: "."))
        meta.overrideKarPct = karVal ?? -1
        try? context.save()
    }
}
