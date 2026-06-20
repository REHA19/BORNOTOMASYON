import SwiftUI
import SwiftData

struct MultiBlendReportSheet: View {
    let group:       MultiBlendGroup
    let allFormulas: [BlendFormula]
    let library:     [FeedIngredient]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCodes: Set<String>
    @State private var shareItems:    [Any] = []
    @State private var showShare      = false
    @State private var isGenerating   = false
    @State private var showSettings   = false
    @State private var searchText     = ""

    @ObservedObject private var settings = ReportSettings.shared

    init(group: MultiBlendGroup, allFormulas: [BlendFormula], library: [FeedIngredient],
         preselectedCodes: [String]? = nil) {
        self.group       = group
        self.allFormulas = allFormulas
        self.library     = library
        _selectedCodes   = State(initialValue: Set(preselectedCodes ?? group.formulaCodes))
    }

    private var groupFormulas: [BlendFormula] {
        group.formulaCodes.compactMap { code in allFormulas.first { $0.code == code } }
    }

    private var filteredGroupFormulas: [BlendFormula] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return groupFormulas }
        return groupFormulas.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    // All unique constraint names from selected formulas (for nutrient toggle)
    private var availableNutrients: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for code in selectedCodes {
            guard let f = allFormulas.first(where: { $0.code == code }) else { continue }
            for c in f.constraints {
                let n = c.resolvedDisplayName
                if seen.insert(n).inserted { result.append(n) }
            }
        }
        return result.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Formula selection ──
                Section {
                    HStack {
                        Button("Tümünü Seç") { selectedCodes = Set(group.formulaCodes) }
                            .disabled(selectedCodes.count == group.formulaCodes.count)
                        Spacer()
                        Button("Seçimi Temizle") { selectedCodes = [] }
                            .disabled(selectedCodes.isEmpty)
                    }
                    .font(.caption)
                } header: {
                    Text("Formüller (\(selectedCodes.count)/\(groupFormulas.count) seçili)")
                }

                ForEach(filteredGroupFormulas) { formula in
                    let selected = selectedCodes.contains(formula.code)
                    Button {
                        if selected { selectedCodes.remove(formula.code) }
                        else        { selectedCodes.insert(formula.code) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? .blue : .secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formula.name).font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    Text(formula.code).font(.caption).foregroundStyle(.secondary)
                                    if let tons = group.productionTons[formula.code], tons > 0 {
                                        Text(String(format: "%.1f ton/ay", tons))
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                // ── Report settings summary ──
                Section {
                    Button { showSettings = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3).foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Rapor Düzeni ve Ayarları")
                                    .font(.body).foregroundStyle(.primary)
                                Text(settingsSummaryText)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Rapor Ayarları")
                }

                // ── Export format ──
                Section {
                    exportRow("PDF olarak dışa aktar",         "A4 yatay, tam detay raporlama",  "doc.richtext.fill",  .red)   { share(.pdf) }
                    exportRow("Excel (CSV) olarak dışa aktar", "Excel / Numbers uyumlu",          "tablecells.fill",    .green)  { share(.csv) }
                    exportRow("Metin (TXT) olarak dışa aktar", "Düz metin, her uygulama açar",   "doc.plaintext.fill", .blue)   { share(.txt) }
                } header: {
                    Text("Format Seçin")
                } footer: {
                    Text("Seçili \(selectedCodes.count) formül raporda yer alır. WhatsApp, E-posta, AirDrop ile paylaşılabilir.")
                }

                // ── Cihazlar arası formül aktarımı ──
                Section {
                    exportRow("Formülleri Aktar (Cihazlar Arası)",
                              "Kod, ad, hammadde oranları ve besin kriterleriyle birlikte — diğer cihazda Rasyon İçe Aktar ile yüklenir",
                              "arrow.triangle.2.circlepath", .indigo) { share(.transferTxt) }
                } header: {
                    Text("Formül Aktarımı")
                } footer: {
                    Text("Bu TXT dosyası diğer cihazda \"Rasyon İçe Aktar\" ekranından seçilince, içindeki tüm formüller kod kod ve isim isim ayrı ayrı yüklenebilir.")
                }
            }
            .searchable(text: $searchText, prompt: "Formül adı veya kodu ara")
            .navigationTitle("MultiBlend Raporu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .overlay { if isGenerating { generatingOverlay } }
            .background {
                if showShare {
                    ActivitySheet(items: shareItems, isPresented: $showShare)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                }
            }
            .sheet(isPresented: $showSettings) {
                ReportSettingsView(availableNutrients: availableNutrients)
            }
        }
    }

    // MARK: - Settings summary text

    private var settingsSummaryText: String {
        var parts: [String] = []
        switch settings.sortSharedBy {
        case .usageDesc:    parts.append("Sıra: Kullanım ↓")
        case .usageAsc:     parts.append("Sıra: Kullanım ↑")
        case .alphabetical: parts.append("Sıra: A-Z")
        }
        var hiddenCols: [String] = []
        if !settings.show1000kg  { hiddenCols.append("1000kg") }
        if !settings.showKgDay   { hiddenCols.append("Kg/ay") }
        if !settings.showMinMax  { hiddenCols.append("Min/Max") }
        if !settings.showPrice   { hiddenCols.append("Fiyat") }
        if !settings.showCost    { hiddenCols.append("Tutar") }
        if !settings.showCostPct { hiddenCols.append("%Mal.") }
        if !hiddenCols.isEmpty   { parts.append("Gizli: \(hiddenCols.joined(separator: ", "))") }
        if !settings.hiddenNutrients.isEmpty {
            parts.append("\(settings.hiddenNutrients.count) besin değeri gizli")
        }
        return parts.isEmpty ? "Tüm sütunlar görünür" : parts.joined(separator: "  •  ")
    }

    // MARK: - Export row

    private func exportRow(_ title: String, _ detail: String, _ icon: String, _ color: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(selectedCodes.isEmpty)
    }

    // MARK: - Share

    private enum Format { case pdf, csv, txt, transferTxt }

    private func share(_ format: Format) {
        guard !selectedCodes.isEmpty else { return }
        isGenerating = true
        let orderedCodes = group.formulaCodes.filter { selectedCodes.contains($0) }
        let snapshot = MultiBlendSnapshot.make(
            group: group,
            selectedCodes: orderedCodes,
            allFormulas: allFormulas,
            library: library
        )
        let config = ReportConfig.current()
        let svc = MultiBlendExportService(snap: snapshot, config: config)

        Task.detached(priority: .userInitiated) {
            let url: URL
            switch format {
            case .pdf:         url = svc.writePDF()
            case .csv:         url = svc.writeCSV()
            case .txt:         url = svc.writeTXT()
            case .transferTxt: url = svc.writeTransferTXT()
            }
            await MainActor.run {
                isGenerating = false
                shareItems   = [url]
                showShare    = true
            }
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text("Rapor hazırlanıyor…").font(.subheadline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Report Settings View

struct ReportSettingsView: View {
    let availableNutrients: [String]
    @ObservedObject private var settings = ReportSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // ── Sorting ──
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ortak Hammadde Tablosu").font(.subheadline.bold())
                        Picker("", selection: Binding(
                            get: { settings.sortSharedBy },
                            set: { settings.sortSharedBy = $0 }
                        )) {
                            ForEach(ReportSettings.IngSort.allCases) { s in
                                Text(sortLabel(s)).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Formül Hammadde Tablosu").font(.subheadline.bold())
                        Picker("", selection: Binding(
                            get: { settings.sortFormulaBy },
                            set: { settings.sortFormulaBy = $0 }
                        )) {
                            ForEach(ReportSettings.IngSort.allCases) { s in
                                Text(sortLabel(s)).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Sıralama", systemImage: "arrow.up.arrow.down")
                } footer: {
                    Text("↓ Büyükten küçüğe  •  ↑ Küçükten büyüğe  •  A-Z Alfabetik")
                }

                // ── Columns ──
                Section {
                    Toggle(isOn: Binding(get: { settings.show1000kg },  set: { settings.show1000kg  = $0 })) {
                        Label("1000 kg Miktarı", systemImage: "scalemass")
                    }
                    Toggle(isOn: Binding(get: { settings.showKgDay },   set: { settings.showKgDay   = $0 })) {
                        Label("Kg/ay (Aylık Kullanım)", systemImage: "calendar")
                    }
                    Toggle(isOn: Binding(get: { settings.showMinMax },  set: { settings.showMinMax  = $0 })) {
                        Label("Min% / Max% Kısıtları", systemImage: "slider.horizontal.below.rectangle")
                    }
                    Toggle(isOn: Binding(get: { settings.showPrice },   set: { settings.showPrice   = $0 })) {
                        Label("TL/ton (Fiyat)", systemImage: "turkishlirasign.circle")
                    }
                    Toggle(isOn: Binding(get: { settings.showCost },    set: { settings.showCost    = $0 })) {
                        Label("Tutar TL/ay", systemImage: "sum")
                    }
                    Toggle(isOn: Binding(get: { settings.showCostPct }, set: { settings.showCostPct = $0 })) {
                        Label("%Maliyet", systemImage: "percent")
                    }
                } header: {
                    Label("Gösterilecek Sütunlar", systemImage: "tablecells")
                } footer: {
                    Text("Mix% sütunu her zaman gösterilir.")
                }

                // ── Nutrients ──
                if !availableNutrients.isEmpty {
                    Section {
                        ForEach(availableNutrients, id: \.self) { name in
                            Toggle(isOn: Binding(
                                get: { settings.isNutrientVisible(name) },
                                set: { _ in settings.toggleNutrient(name) }
                            )) {
                                Text(name)
                            }
                        }
                    } header: {
                        Label("Besin Değerleri Kriterleri", systemImage: "chart.bar.doc.horizontal")
                    } footer: {
                        Text("Kapatılan besin değerleri raporda gözükmez.")
                    }
                }
            }
            .navigationTitle("Rapor Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sıfırla") { settings.resetToDefaults() }
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func sortLabel(_ s: ReportSettings.IngSort) -> String {
        switch s {
        case .usageDesc:    return "↓ Büyük→Küçük"
        case .usageAsc:     return "↑ Küçük→Büyük"
        case .alphabetical: return "A–Z"
        }
    }
}
