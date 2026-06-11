import SwiftUI
import SwiftData

// MARK: - Ana Maliyetlendirme Ekranı

struct MaliyetlendirmeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BlendFormula.code)            private var formulas:   [BlendFormula]
    @Query(sort: \ProductPricingMeta.orderIndex) private var metas:     [ProductPricingMeta]
    @Query(sort: \BrandDefinition.orderIndex)    private var brandDefs:  [BrandDefinition]
    @Query(sort: \KategoriTanim.orderIndex)      private var allKatDefs: [KategoriTanim]

    // Seçili marka
    @AppStorage("pricing_selected_brand") private var selectedBrand: String = "Alapala"

    @Query(sort: \GiderKalemi.orderIndex) private var tumGiderler: [GiderKalemi]

    @State private var showSettings      = false
    @State private var editTarget:       BlendFormula? = nil
    @State private var nutrientTarget:   BlendFormula? = nil
    @State private var showFiyatListesi  = false
    @State private var showArchive       = false
    @State private var showFiyatDegisim  = false
    @State private var showLabelEditor   = false
    @State private var showIskontoAnaliz = false
    @State private var showAddGider      = false
    @State private var showSiralama      = false
    @State private var showBrandYonetim  = false
    @State private var showKatYonetim    = false

    // Dinamik marka listesi — tekrar eden isimleri çıkar
    private var brands: [String] {
        if brandDefs.isEmpty { return ["Alapala", "Karadeniz"] }
        var seen = Set<String>()
        return brandDefs
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { seen.insert($0.name).inserted ? $0.name : nil }
    }

    // Aktif markanın kategorileri
    private var aktifKategoriler: [KategoriTanim] {
        allKatDefs.filter { $0.brand == selectedBrand }
    }

    // Aktif markanın BrandDefinition'ı
    private var aktifBrandDef: BrandDefinition? {
        brandDefs.first { $0.name == selectedBrand }
    }

    // Aktif markaya ait dinamik gider kalemleri
    private var aktifGiderler: [GiderKalemi] {
        tumGiderler.filter { $0.brand == selectedBrand }
    }

    // PricingCalc'a gönderilecek tuple listesi
    private var extraItems: [(value: Double, isPercent: Bool)] {
        aktifGiderler.map { (value: $0.value, isPercent: $0.isPercent) }
    }

    // Aktif marka değerleri (BrandDefinition'dan okunur)
    private var ipCuval:  Double { aktifBrandDef?.giderValue1 ?? 262 }
    private var firePct:  Double { aktifBrandDef?.giderValue2 ?? 2.0 }
    private var elektrik: Double { aktifBrandDef?.giderValue3 ?? 270 }
    private var nakliye:  Double { aktifBrandDef?.giderValue4 ?? 700 }
    private var iscilik:  Double { aktifBrandDef?.giderValue5 ?? 2000 }
    private var karPct:   Double { aktifBrandDef?.karPct      ?? 17  }

    private var label1: String { aktifBrandDef?.giderLabel1 ?? "İP ÇUVAL"     }
    private var label2: String { aktifBrandDef?.giderLabel2 ?? "% Fire"        }
    private var label3: String { aktifBrandDef?.giderLabel3 ?? "Elektrik/GAZ"  }
    private var label4: String { aktifBrandDef?.giderLabel4 ?? "Nakliye"       }
    private var label5: String { aktifBrandDef?.giderLabel5 ?? "İşçilik"       }

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
                                formula:    row.formula,
                                meta:       row.meta,
                                ipCuval:    ipCuval, firePct:  firePct,
                                elektrik:   elektrik, nakliye: nakliye,
                                iscilik:    iscilik, karPct:   karPct,
                                label1: label1, label2: label2,
                                label3: label3, label4: label4, label5: label5,
                                extraItems: extraItems
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { editTarget = row.formula }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    nutrientTarget = row.formula
                                } label: {
                                    Label("İçerik & Besinler", systemImage: "chart.bar.doc.horizontal")
                                }
                                .tint(.indigo)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                ForEach(brands.filter { $0 != selectedBrand }, id: \.self) { hedef in
                                    Button {
                                        aktarUrun(row, to: hedef)
                                    } label: {
                                        Label(hedef, systemImage: "arrow.right.square.fill")
                                    }
                                    .tint(.blue)
                                }
                            }
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
                    HStack(spacing: 12) {
                        Menu {
                            Button { showBrandYonetim = true } label: {
                                Label("Marka Yönetimi", systemImage: "building.2")
                            }
                            Button { showKatYonetim = true } label: {
                                Label("Kategori Ayarları", systemImage: "square.grid.2x2")
                            }
                            Button { showSiralama = true } label: {
                                Label("Ürün Sıralama", systemImage: "arrow.up.arrow.down")
                            }
                            Button { showArchive = true } label: {
                                Label("Arşiv", systemImage: "clock.arrow.circlepath")
                            }
                            Button { showFiyatDegisim = true } label: {
                                Label("Fiyat Değişim Raporu", systemImage: "chart.line.uptrend.xyaxis")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        Button { showIskontoAnaliz = true } label: {
                            Image(systemName: "percent").foregroundStyle(.green)
                        }
                        Button { showFiyatListesi = true } label: {
                            Image(systemName: "doc.richtext.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }
            .onAppear { seedDefaultsIfNeeded() }
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
                    label3: label3, label4: label4, label5: label5,
                    extraItems:  extraItems,
                    antetImage:  aktifBrandDef?.antetImage,
                    kategoriler: aktifKategoriler
                )
            }
            .sheet(isPresented: $showIskontoAnaliz) {
                IskontoAnalizView(
                    rows:        rows,
                    ipCuval:     ipCuval, firePct:  firePct,
                    elektrik:    elektrik, nakliye: nakliye,
                    iscilik:     iscilik, globalKarPct: karPct,
                    extraItems:  extraItems
                )
            }
            .sheet(isPresented: $showAddGider) {
                GiderKalemiEkleSheet(brand: selectedBrand,
                                     nextOrder: aktifGiderler.count)
            }
            .sheet(isPresented: $showSiralama) {
                UrunSiralamaView(brand: selectedBrand)
            }
            .sheet(isPresented: $showBrandYonetim) {
                BrandYonetimView()
            }
            .sheet(isPresented: $showKatYonetim) {
                KategoriYonetimView(brand: selectedBrand)
            }
            .sheet(item: $nutrientTarget) { formula in
                FormulaContentSheet(formula: formula)
            }
            .navigationDestination(isPresented: $showArchive) {
                PriceListArchiveView(brand: selectedBrand)
            }
            .navigationDestination(isPresented: $showFiyatDegisim) {
                FiyatDegisimRaporuView(brand: selectedBrand)
            }
        }
    }

    // MARK: - Global ayarlar içeriği

    @ViewBuilder
    private var globalSettingsContent: some View {
        if let brand = aktifBrandDef {
            BrandGiderAyarlari(
                brand:      brand,
                ekGiderler: aktifGiderler,
                onEkle:     { showAddGider = true },
                onSil:      { item in context.delete(item); try? context.save() }
            )
        } else {
            Text("Önce bir marka oluşturun.")
                .font(.caption).foregroundStyle(.secondary).padding()
        }
    }

    // MARK: - İlk açılışta varsayılan markalar

    private func seedDefaultsIfNeeded() {
        // Önce mevcut tekrarları temizle (CloudKit çift seed yarattıysa)
        deduplicateBrands()

        // Eksik varsayılanları ekle
        let existingNames = Set(brandDefs.map { $0.name })
        let defaults = [("Alapala", 0), ("Karadeniz", 1)]
        var inserted = false
        for (name, idx) in defaults {
            guard !existingNames.contains(name) else { continue }
            context.insert(BrandDefinition(name: name, orderIndex: idx))
            inserted = true
        }
        if inserted { try? context.save() }
    }

    /// Aynı isimde birden fazla BrandDefinition varsa ilki dışındakileri sil
    private func deduplicateBrands() {
        var seen  = Set<String>()
        var toDelete: [BrandDefinition] = []
        for b in brandDefs.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            if seen.contains(b.name) { toDelete.append(b) }
            else                     { seen.insert(b.name) }
        }
        guard !toDelete.isEmpty else { return }
        toDelete.forEach { context.delete($0) }
        try? context.save()
    }

    // MARK: - Ürün aktarımı

    private func aktarUrun(
        _ row: (formula: BlendFormula, meta: ProductPricingMeta?),
        to targetBrand: String
    ) {
        if let meta = row.meta {
            // Meta zaten var → sadece markasını değiştir
            meta.brand = targetBrand
        } else {
            // Meta yok (varsayılan Alapala'da görünüyordu) → hedef marka için oluştur
            let m = ProductPricingMeta(formulaCode: row.formula.code, brand: targetBrand)
            context.insert(m)
        }
        try? context.save()
    }

}

// MARK: - Marka başına Global Gider Ayarları (@Bindable ile BrandDefinition'a bağlanır)

private struct BrandGiderAyarlari: View {
    @Bindable var brand:       BrandDefinition
    let ekGiderler:  [GiderKalemi]
    let onEkle:      () -> Void
    let onSil:       (GiderKalemi) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PricingInputRow(label: brand.giderLabel1, unit: "₺/ton", value: $brand.giderValue1)
            PricingInputRow(label: brand.giderLabel2, unit: "%",      value: $brand.giderValue2)
            PricingInputRow(label: brand.giderLabel3, unit: "₺/ton", value: $brand.giderValue3)
            PricingInputRow(label: brand.giderLabel4, unit: "₺/ton", value: $brand.giderValue4)
            PricingInputRow(label: brand.giderLabel5, unit: "₺/ton", value: $brand.giderValue5)

            if !ekGiderler.isEmpty {
                Divider().padding(.vertical, 3)
                ForEach(ekGiderler) { item in
                    HStack {
                        Text(item.name).font(.subheadline).foregroundStyle(.purple)
                            .frame(minWidth: 110, alignment: .leading)
                        Spacer()
                        Text(fmtV(item.value)).font(.subheadline.monospacedDigit())
                        Text(item.unitLabel).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                        Button { onSil(item) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 2)
                }
            }

            Button { onEkle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.purple)
                    Text("Gider Kalemi Ekle").font(.subheadline).foregroundStyle(.purple)
                }
            }.padding(.vertical, 6)

            Divider().padding(.vertical, 4)
            PricingInputRow(label: "Kar Marjı", unit: "%", value: $brand.karPct, accent: .orange)
            Divider().padding(.vertical, 4)

            // Kalem adlarını bu marka için düzenle
            NavigationLink {
                Form {
                    Section("Kalem Adları — \(brand.name)") {
                        TextField("Kalem 1", text: $brand.giderLabel1)
                        TextField("Kalem 2", text: $brand.giderLabel2)
                        TextField("Kalem 3", text: $brand.giderLabel3)
                        TextField("Kalem 4", text: $brand.giderLabel4)
                        TextField("Kalem 5", text: $brand.giderLabel5)
                    }
                    Section {
                        Button("Varsayılana Sıfırla") {
                            brand.giderLabel1 = "İP ÇUVAL"
                            brand.giderLabel2 = "% Fire"
                            brand.giderLabel3 = "Elektrik/GAZ"
                            brand.giderLabel4 = "Nakliye"
                            brand.giderLabel5 = "İşçilik"
                        }.foregroundStyle(.red)
                    }
                }
                .navigationTitle("Kalem Adları")
            } label: {
                HStack {
                    Image(systemName: "pencil.circle").foregroundStyle(.blue)
                    Text("Kalem Adlarını Düzenle").font(.subheadline).foregroundStyle(.blue)
                }
            }.padding(.vertical, 6)
        }
    }

    private func fmtV(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }
}

// MARK: - Kalem adı düzenleme sheet'i (artık BrandGiderAyarlari içinde, geriye uyumluluk için bırakıldı)

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
    let formula:    BlendFormula
    let meta:       ProductPricingMeta?
    let ipCuval:    Double
    let firePct:    Double
    let elektrik:   Double
    let nakliye:    Double
    let iscilik:    Double
    let karPct:     Double
    let label1:     String
    let label2:     String
    let label3:     String
    let label4:     String
    let label5:     String
    var extraItems: [(value: Double, isPercent: Bool)] = []

    private var rasyon: Double { formula.currentCostTL > 0 ? formula.currentCostTL : formula.recordedCostTL }
    private var bagKg:  Int    { meta?.bagKg ?? 50 }
    private var effKar: Double { (meta?.overrideKarPct ?? -1) >= 0 ? (meta!.overrideKarPct) : karPct }

    // Ürünün logosu — galeriden yüklenen öncelikli, yoksa asset catalog
    private var logoImage: UIImage? { meta?.logoImage }

    private var calc: PricingCalc {
        PricingCalc.calculate(
            rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
            karPct: effKar, bagKg: bagKg, extraItems: extraItems
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

                // Logo küçük önizleme
                if let img = logoImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 28)
                        .padding(3)
                        .background(Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                }

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

    @State private var form:              String           = "Pelet"
    @State private var categoryGroup:     String           = ""
    @State private var bagKg:             Int              = 50
    @State private var isVisible:         Bool             = true
    @State private var overrideKarStr:    String           = ""
    @State private var orderIndex:        Int              = 0
    @State private var logoName:          String           = ""
    @State private var brand:             String           = "Alapala"
    @State private var proteinStr:        String           = ""   // boş = formül değeri
    @State private var manualPesinStr:    String           = ""   // boş = hesaplanan
    @State private var logoImagePath: String  = ""
    @State private var logoImageData: Data?   = nil

    @Query(sort: \KategoriTanim.orderIndex) private var allKategoriTanimlar: [KategoriTanim]

    private let formOptions = ["Pelet-Granül", "Pelet", "Granül", "Toz", "TANELİ", "Diğer"]

    // Seçili markaya ait kategoriler — KategoriYonetimView'de eklenenler dahil
    private var categories: [String] {
        let brandKats = allKategoriTanimlar
            .filter { $0.brand == brand }
            .map    { $0.name }
        if brandKats.isEmpty {
            // Hiç tanım yoksa sabit listeye düş
            return [
                "SIĞIR SÜT YEMLERİ( 50 kg)",
                "SIĞIR BESİ YEMLERİ( 50 kg)",
                "SIĞIR BESİ TOZ YEMLERİ( 50 kg)",
                "KUZU TOKLU YEMLERİ( 50 kg)",
                "BUZAĞI YEMLERİ( 40-50 kg)",
                "ÖZEL YEMLER( 50 kg)",
                "KANATLI YEMLERİ ( 50 KG)",
            ]
        }
        return brandKats
    }

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

                // ── Protein ───────────────────────────────────────────
                Section {
                    HStack {
                        Text("Formül Proteini")
                        Spacer()
                        if let p = formula.lastSolve?.nutrientValues["crudeProtein"] {
                            Text(String(format: "%.1f%%", p)).foregroundStyle(.secondary)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Manuel Protein %")
                        Spacer()
                        TextField("Boş = formül değeri", text: $proteinStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                } header: { Text("Protein") } footer: {
                    if !proteinStr.isEmpty {
                        Text("PDF'de \(proteinStr)% gösterilir.")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }

                // ── Fiyat hesabı ───────────────────────────────────────
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
                    LabeledContent("Hesaplanan Peşin (\(bagKg) kg)") {
                        Text(fmt(calc.pesin) + " ₺").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Manuel Peşin Fiyat")
                        Spacer()
                        TextField("Boş = hesaplanan", text: $manualPesinStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("₺").font(.caption).foregroundStyle(.secondary)
                    }
                    if let mp = Double(manualPesinStr.replacingOccurrences(of: ",", with: ".")), mp > 0 {
                        Label("Tüm vadeler bu fiyat üzerinden hesaplanır", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }

                // ── Logo (galeri + asset) ──────────────────────────────
                Section {
                    // Önizleme
                    if let img = loadCurrentLogo() {
                        HStack {
                            Image(uiImage: img)
                                .resizable().scaledToFit()
                                .frame(height: 36)
                                .padding(4)
                                .background(Color.secondary.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 6))
                            Spacer()
                            Button { logoImagePath = ""; logoName = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    ResimYukleButon(
                        baslik: logoImagePath.isEmpty && logoName.isEmpty
                                ? "Logo Seç (Galeri veya Dosya)"
                                : "Logoyu Değiştir"
                    ) { img in
                        // PNG saydamlığı korur (logo arka planı); JPEG'e sadece PNG yoksa düş
                        logoImageData = img.pngData() ?? img.jpegData(compressionQuality: 0.90)
                        logoImagePath = ""
                        logoName      = ""
                    }

                    Picker("Asset Catalog Logo", selection: $logoName) {
                        ForEach(logoOptions, id: \.0) { val, label in
                            HStack {
                                if !val.isEmpty, UIImage(named: val) != nil {
                                    Image(val).resizable().scaledToFit().frame(width: 24, height: 14)
                                }
                                Text(label)
                            }.tag(val)
                        }
                    }
                } header: {
                    Text("Logo")
                } footer: {
                    Text("Galeriden yüklenen logo önceliklidir.")
                        .font(.caption2)
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
        form           = m.form
        categoryGroup  = m.categoryGroup
        bagKg          = m.bagKg
        isVisible      = m.isVisible
        orderIndex     = m.orderIndex
        logoName       = m.logoName
        logoImagePath  = m.logoImagePath
        logoImageData  = m.logoImageData
        if m.overrideKarPct >= 0 {
            overrideKarStr = String(format: "%.1f", m.overrideKarPct)
        }
        if m.proteinOverride >= 0 {
            proteinStr = String(format: "%.1f", m.proteinOverride)
        }
        if m.manualPesin >= 0 {
            manualPesinStr = String(format: "%.2f", m.manualPesin)
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
        meta.logoImagePath  = logoImagePath
        meta.logoImageData  = logoImageData
        meta.overrideKarPct = Double(overrideKarStr.replacingOccurrences(of: ",", with: ".")) ?? -1
        meta.proteinOverride = Double(proteinStr.replacingOccurrences(of: ",", with: ".")) ?? -1
        meta.manualPesin    = Double(manualPesinStr.replacingOccurrences(of: ",", with: ".")) ?? -1
        try? context.save()
    }

    private func loadCurrentLogo() -> UIImage? {
        if let data = logoImageData, let img = UIImage(data: data) { return img }
        if !logoImagePath.isEmpty,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent(logoImagePath)
            if let img = UIImage(contentsOfFile: url.path) { return img }
        }
        if !logoName.isEmpty { return UIImage(named: logoName) }
        return nil
    }

}

// MARK: - Formül İçerik & Besin Değerleri Sheet'i (çift tıklamayla açılır)

struct FormulaContentSheet: View {
    let formula: BlendFormula
    @Environment(\.dismiss) private var dismiss

    private var activeIngredients: [BFIngredient] {
        formula.ingredients
            .filter { $0.isActive && $0.mixPct > 0.001 }
            .sorted { $0.mixPct > $1.mixPct }
    }

    private var nutrientRows: [(name: String, unit: String, value: Double)] {
        guard let solve = formula.lastSolve else { return [] }
        return allNutrientDefs.compactMap { def in
            guard let v = solve.nutrientValues[def.key], v > 0.0001 else { return nil }
            return (name: def.displayName, unit: def.unit, value: v)
        }
    }

    private func pctFmt(_ v: Double) -> String { String(format: "%.2f%%", v) }
    private func numFmt(_ v: Double, unit: String) -> String {
        unit.lowercased().contains("kcal") ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Çözüm özeti ───────────────────────────────────────────
                if let solve = formula.lastSolve {
                    Section {
                        let dateFmt = DateFormatter()
                        let _ = { dateFmt.locale = Locale(identifier: "tr_TR"); dateFmt.dateFormat = "d MMM yyyy HH:mm" }()
                        LabeledContent("Son Çözüm", value: dateFmt.string(from: solve.solvedAt))
                        LabeledContent("Rasyon Maliyeti") {
                            Text(String(format: "%.2f ₺/ton", solve.costPerTon))
                                .foregroundStyle(.orange).fontWeight(.semibold)
                        }
                        LabeledContent("Durum") {
                            Label(solve.isFeasible ? "Uygun Çözüm" : "Uygun Değil",
                                  systemImage: solve.isFeasible ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(solve.isFeasible ? .green : .red)
                        }
                    } header: { Text("Çözüm Bilgisi") }
                }

                // ── İçerik (hammaddeler) ──────────────────────────────────
                Section {
                    if activeIngredients.isEmpty {
                        Text("Henüz çözüm yapılmamış veya hammadde bulunamadı.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(activeIngredients) { ing in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ing.name).font(.subheadline)
                                    Text(ing.code).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(pctFmt(ing.mixPct))
                                        .font(.subheadline.bold().monospacedDigit())
                                        .foregroundStyle(.indigo)
                                    let kg = ing.mixPct / 100.0 * formula.totalKg
                                    Text(String(format: "%.0f kg/ton", kg))
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                if ing.minPct > 0 && abs(ing.mixPct - ing.minPct) < 0.05 {
                                    Image(systemName: "arrow.down.to.line")
                                        .font(.caption2).foregroundStyle(.orange)
                                } else if ing.maxPct < 100 && abs(ing.mixPct - ing.maxPct) < 0.05 {
                                    Image(systemName: "arrow.up.to.line")
                                        .font(.caption2).foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                } header: {
                    HStack {
                        Text("İçerik — \(activeIngredients.count) Hammadde")
                        Spacer()
                        Text(String(format: "Toplam: %.2f%%", activeIngredients.reduce(0) { $0 + $1.mixPct }))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // ── Besin Değerleri ───────────────────────────────────────
                if !nutrientRows.isEmpty {
                    Section {
                        ForEach(nutrientRows, id: \.name) { row in
                            HStack {
                                Text(row.name).font(.subheadline)
                                Spacer()
                                Text(numFmt(row.value, unit: row.unit))
                                    .font(.subheadline.monospacedDigit())
                                if !row.unit.isEmpty {
                                    Text(row.unit)
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .frame(minWidth: 50, alignment: .leading)
                                }
                            }
                        }
                    } header: { Text("Besin Değerleri") }
                } else if formula.lastSolve != nil {
                    Section {
                        Text("Bu formül için besin değeri kaydı bulunamadı.")
                            .font(.caption).foregroundStyle(.secondary)
                    } header: { Text("Besin Değerleri") }
                }

                // ── Kısıtlar ─────────────────────────────────────────────
                let shownConstraints = formula.constraints.filter { $0.isActive && $0.showInResult }
                if !shownConstraints.isEmpty {
                    Section {
                        ForEach(shownConstraints) { con in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(con.resolvedDisplayName).font(.subheadline)
                                    HStack(spacing: 6) {
                                        if let mn = con.minValue {
                                            Text("min: \(String(format: "%.2f", mn))")
                                                .font(.caption2).foregroundStyle(.blue)
                                        }
                                        if let mx = con.maxValue {
                                            Text("max: \(String(format: "%.2f", mx))")
                                                .font(.caption2).foregroundStyle(.orange)
                                        }
                                    }
                                }
                                Spacer()
                                if let curr = con.currentValue {
                                    Text(String(format: "%.2f", curr))
                                        .font(.subheadline.bold().monospacedDigit())
                                        .foregroundStyle(constraintColor(con))
                                    Text(con.unit).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    } header: { Text("Besin Kısıtları") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(formula.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func constraintColor(_ con: BFConstraint) -> Color {
        guard let curr = con.currentValue else { return .primary }
        if let mn = con.minValue, curr < mn - 0.01 { return .red }
        if let mx = con.maxValue, curr > mx + 0.01 { return .red }
        return .green
    }
}
