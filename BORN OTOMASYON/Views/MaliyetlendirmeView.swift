import SwiftUI
import SwiftData

// MARK: - Ana Maliyetlendirme Ekranı

struct MaliyetlendirmeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BlendFormula.code)            private var formulas: [BlendFormula]
    @Query(sort: \ProductPricingMeta.orderIndex) private var metas:   [ProductPricingMeta]

    // Seçili marka
    @AppStorage("pricing_selected_brand") private var selectedBrand: String = "Alapala"

    // Global maliyet değerleri — marka başına ayrı AppStorage
    @AppStorage("pricing_ip_cuval_Alapala")     private var ipCuvalA:  Double = 262
    @AppStorage("pricing_fire_pct_Alapala")     private var firePctA:  Double = 2.0
    @AppStorage("pricing_elektrik_Alapala")     private var elektrikA: Double = 270
    @AppStorage("pricing_nakliye_Alapala")      private var nakliyeA:  Double = 700
    @AppStorage("pricing_iscilik_Alapala")      private var iscilikA:  Double = 2000
    @AppStorage("pricing_kar_pct_Alapala")      private var karPctA:   Double = 17

    @AppStorage("pricing_ip_cuval_Karadeniz")   private var ipCuvalK:  Double = 262
    @AppStorage("pricing_fire_pct_Karadeniz")   private var firePctK:  Double = 2.0
    @AppStorage("pricing_elektrik_Karadeniz")   private var elektrikK: Double = 270
    @AppStorage("pricing_nakliye_Karadeniz")    private var nakliyeK:  Double = 700
    @AppStorage("pricing_iscilik_Karadeniz")    private var iscilikK:  Double = 2000
    @AppStorage("pricing_kar_pct_Karadeniz")    private var karPctK:   Double = 17

    // Değiştirilebilir kalem adları (global — tüm markalar için)
    @AppStorage("pricing_label_1") private var label1: String = "İP ÇUVAL"
    @AppStorage("pricing_label_2") private var label2: String = "% Fire"
    @AppStorage("pricing_label_3") private var label3: String = "Elektrik/GAZ"
    @AppStorage("pricing_label_4") private var label4: String = "Nakliye"
    @AppStorage("pricing_label_5") private var label5: String = "İşçilik"

    @State private var showSettings    = false
    @State private var editTarget:     BlendFormula? = nil
    @State private var showFiyatListesi = false
    @State private var showArchive      = false
    @State private var showLabelEditor  = false

    private let brands = ["Alapala", "Karadeniz"]

    // Aktif marka değerleri
    private var ipCuval:  Double { selectedBrand == "Alapala" ? ipCuvalA  : ipCuvalK  }
    private var firePct:  Double { selectedBrand == "Alapala" ? firePctA  : firePctK  }
    private var elektrik: Double { selectedBrand == "Alapala" ? elektrikA : elektrikK }
    private var nakliye:  Double { selectedBrand == "Alapala" ? nakliyeA  : nakliyeK  }
    private var iscilik:  Double { selectedBrand == "Alapala" ? iscilikA  : iscilikK  }
    private var karPct:   Double { selectedBrand == "Alapala" ? karPctA   : karPctK   }

    // Aktif marka binding'leri
    private var ipCuvalB:  Binding<Double>  { selectedBrand == "Alapala" ? $ipCuvalA  : $ipCuvalK  }
    private var firePctB:  Binding<Double>  { selectedBrand == "Alapala" ? $firePctA  : $firePctK  }
    private var elektrikB: Binding<Double>  { selectedBrand == "Alapala" ? $elektrikA : $elektrikK }
    private var nakliyeB:  Binding<Double>  { selectedBrand == "Alapala" ? $nakliyeA  : $nakliyeK  }
    private var iscilikB:  Binding<Double>  { selectedBrand == "Alapala" ? $iscilikA  : $iscilikK  }
    private var karPctB:   Binding<Double>  { selectedBrand == "Alapala" ? $karPctA   : $karPctK   }

    private var rows: [(formula: BlendFormula, meta: ProductPricingMeta?)] {
        let metaByCode = Dictionary(metas.map { ($0.formulaCode, $0) },
                                    uniquingKeysWith: { first, _ in first })
        return formulas
            .filter { f in
                guard f.currentCostTL > 0 || f.recordedCostTL > 0 else { return false }
                let brand = metaByCode[f.code]?.brand ?? "Alapala"
                return brand == selectedBrand
            }
            .sorted { (metaByCode[$0.code]?.orderIndex ?? 999) < (metaByCode[$1.code]?.orderIndex ?? 999) }
            .map { ($0, metaByCode[$0.code]) }
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Marka seçici ───────────────────────────────────────
                Section {
                    Picker("Marka", selection: $selectedBrand) {
                        ForEach(brands, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                // ── Global gider ayarları ──────────────────────────────
                Section {
                    DisclosureGroup(isExpanded: $showSettings) {
                        globalSettingsContent
                    } label: {
                        HStack {
                            Label("Global Gider Ayarları", systemImage: "slider.horizontal.3")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(selectedBrand)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Ürün listesi ───────────────────────────────────────
                Section {
                    if rows.isEmpty {
                        ContentUnavailableView(
                            "\(selectedBrand) Ürünü Yok",
                            systemImage: "chart.bar.doc.horizontal",
                            description: Text("Ürünleri \(selectedBrand) markasına atamak için üzerine dokunun.")
                        )
                    } else {
                        ForEach(rows, id: \.formula.code) { row in
                            PricingProductRow(
                                formula:  row.formula,
                                meta:     row.meta,
                                ipCuval:  ipCuval, firePct:  firePct,
                                elektrik: elektrik, nakliye: nakliye,
                                iscilik:  iscilik, karPct:   karPct,
                                label1: label1, label2: label2,
                                label3: label3, label4: label4, label5: label5
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { editTarget = row.formula }
                        }
                    }
                } header: {
                    HStack {
                        Text("\(selectedBrand) — \(rows.count) ürün")
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
                    HStack(spacing: 14) {
                        Button { showArchive = true } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        Button { showFiyatListesi = true } label: {
                            Image(systemName: "doc.richtext.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .sheet(item: $editTarget) { formula in
                ProductPricingMetaSheet(
                    formula:      formula,
                    existingMeta: metas.first { $0.formulaCode == formula.code },
                    ipCuval: ipCuval, firePct:  firePct,
                    elektrik: elektrik, nakliye: nakliye,
                    iscilik:  iscilik, globalKarPct: karPct,
                    defaultBrand: selectedBrand
                )
            }
            .sheet(isPresented: $showFiyatListesi) {
                FiyatListesiView(
                    rows:        rows,
                    brand:       selectedBrand,
                    ipCuval:     ipCuval, firePct:  firePct,
                    elektrik:    elektrik, nakliye: nakliye,
                    iscilik:     iscilik, globalKarPct: karPct,
                    label1: label1, label2: label2,
                    label3: label3, label4: label4, label5: label5
                )
            }
            .sheet(isPresented: $showLabelEditor) {
                CostLabelEditorSheet(
                    label1: $label1, label2: $label2,
                    label3: $label3, label4: $label4, label5: $label5
                )
            }
            .navigationDestination(isPresented: $showArchive) {
                PriceListArchiveView(brand: selectedBrand)
            }
        }
    }

    // MARK: - Global ayarlar içeriği

    private var globalSettingsContent: some View {
        VStack(spacing: 0) {
            PricingInputRow(label: label1, unit: "₺/ton", value: ipCuvalB)
            PricingInputRow(label: label2, unit: "%",      value: firePctB)
            PricingInputRow(label: label3, unit: "₺/ton", value: elektrikB)
            PricingInputRow(label: label4, unit: "₺/ton", value: nakliyeB)
            PricingInputRow(label: label5, unit: "₺/ton", value: iscilikB)
            Divider().padding(.vertical, 4)
            PricingInputRow(label: "Kar Marjı", unit: "%", value: karPctB, accent: .orange)
            Divider().padding(.vertical, 4)
            Button {
                showLabelEditor = true
            } label: {
                HStack {
                    Image(systemName: "pencil.circle").foregroundStyle(.blue)
                    Text("Kalem Adlarını Düzenle")
                        .font(.subheadline).foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Kalem adı düzenleme sheet'i

struct CostLabelEditorSheet: View {
    @Binding var label1: String
    @Binding var label2: String
    @Binding var label3: String
    @Binding var label4: String
    @Binding var label5: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kalem 1", text: $label1)
                    TextField("Kalem 2", text: $label2)
                    TextField("Kalem 3", text: $label3)
                    TextField("Kalem 4", text: $label4)
                    TextField("Kalem 5", text: $label5)
                } header: {
                    Text("Maliyet Kalem Adları")
                } footer: {
                    Text("Bu isimler tüm markalarda gösterilir. Kar Marjı adı değiştirilemez.")
                        .font(.caption2)
                }

                Section {
                    Button("Varsayılana Sıfırla") {
                        label1 = "İP ÇUVAL"
                        label2 = "% Fire"
                        label3 = "Elektrik/GAZ"
                        label4 = "Nakliye"
                        label5 = "İşçilik"
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Kalem Adları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }.fontWeight(.semibold)
                }
            }
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
    let label1:   String
    let label2:   String
    let label3:   String
    let label4:   String
    let label5:   String

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
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formula.name).font(.subheadline.bold())
                    HStack(spacing: 6) {
                        Text(formula.code).font(.caption).foregroundStyle(.secondary)
                        if let m = meta, !m.form.isEmpty {
                            Text(m.form).font(.caption2).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.blue.opacity(0.7), in: Capsule())
                        }
                        if let m = meta, !m.categoryGroup.isEmpty {
                            Text(m.categoryGroup.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? "")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                        Text("\(bagKg) kg").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmt(calc.pesin) + " ₺")
                        .font(.title3.bold()).foregroundStyle(.orange)
                    Text("Peşin Barem").font(.caption2).foregroundStyle(.secondary)
                    if let m = meta, m.overrideKarPct >= 0 {
                        Text("KAR: %\(String(format: "%.0f", m.overrideKarPct))")
                            .font(.caption2).foregroundStyle(.purple)
                    } else {
                        Text("KAR: %\(String(format: "%.0f", karPct))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 0) {
                costChip("Rasyon",  fmt(calc.rasyon))
                costChip(label2.replacingOccurrences(of: "% ", with: ""), fmt(calc.fire))
                costChip(label3.components(separatedBy: "/").first ?? label3, fmt(calc.elektrik))
                costChip(label4, fmt(calc.nakliye))
                costChip(label5, fmt(calc.iscilik))
                Spacer()
                Text("Genel: \(fmt(calc.toplam)) ₺/ton")
                    .font(.caption2.bold()).foregroundStyle(.primary)
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
    let ipCuval:      Double
    let firePct:      Double
    let elektrik:     Double
    let nakliye:      Double
    let iscilik:      Double
    let globalKarPct: Double
    var defaultBrand: String = "Alapala"

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @State private var form:          String = "Pelet"
    @State private var categoryGroup: String = ""
    @State private var bagKg:         Int    = 50
    @State private var isVisible:     Bool   = true
    @State private var overrideKarStr: String = ""
    @State private var orderIndex:    Int    = 0
    @State private var logoName:      String = ""
    @State private var brand:         String = "Alapala"

    private let formOptions = ["Pelet-Granül", "Pelet", "Toz", "TANELİ", "Diğer"]

    // PDF'deki kategoriler — iki marka için
    private let alapalaCategories = [
        "SIĞIR SÜT YEMLERİ( 50 kg)",
        "SIĞIR BESİ YEMLERİ( 50 kg)",
        "SIĞIR BESİ TOZ YEMLERİ( 50 kg)",
        "KUZU TOKLU YEMLERİ( 50 kg)",
        "BUZAĞI YEMLERİ( 40-50 kg)",
        "ÖZEL YEMLER( 50 kg)",
        "KANATLI YEMLERİ ( 50 KG)",
    ]
    private let karadenizCategories = [
        "SIĞIR SÜT YEMLERİ( 50 kg)",
        "SIĞIR BESİ YEMLERİ( 50 kg)",
        "KUZU TOKLU YEMLERİ( 50 kg)",
        "BUZAĞI YEMLERİ( 40-50 kg)",
        "ÖZEL YEMLER( 50 kg)",
    ]

    private var categories: [String] { brand == "Karadeniz" ? karadenizCategories : alapalaCategories }

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
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ürün") {
                    LabeledContent("Kod",  value: formula.code)
                    LabeledContent("Ad",   value: formula.name)
                    LabeledContent("Rasyon Mal.", value: fmt(rasyon) + " ₺/ton")
                }

                Section("Marka") {
                    Picker("Marka", selection: $brand) {
                        Text("Alapala").tag("Alapala")
                        Text("Karadeniz").tag("Karadeniz")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Kategori") {
                    Picker("Kategori Grubu", selection: $categoryGroup) {
                        Text("Seçilmemiş").tag("")
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                }

                Section("Ürün Özellikleri") {
                    Picker("Form", selection: $form) {
                        ForEach(formOptions, id: \.self) { Text($0) }
                    }
                    Picker("Çuval Ağırlığı", selection: $bagKg) {
                        Text("50 kg").tag(50)
                        Text("40 kg").tag(40)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Fiyat Listesinde Göster", isOn: $isVisible)
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

                Section("Fiyat Hesabı") {
                    HStack {
                        Text("Özel KAR %")
                        Spacer()
                        TextField("Boş = global (%\(String(format: "%.0f", globalKarPct)))", text: $overrideKarStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    LabeledContent("Genel Maliyet") {
                        Text(fmt(calc.toplam) + " ₺/ton").foregroundStyle(.primary)
                    }
                    LabeledContent("Peşin Barem (\(bagKg) kg)") {
                        Text(fmt(calc.pesin) + " ₺").font(.headline).foregroundStyle(.orange)
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
                    Button("Kaydet") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        brand = existingMeta?.brand ?? defaultBrand
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
        meta.brand          = brand
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
