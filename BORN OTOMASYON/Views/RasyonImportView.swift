import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Main View

struct RasyonImportView: View {

    @Environment(\.modelContext) private var context
    // Kalıcı liste — SwiftData'dan, her açılışta orada
    @Query(sort: \BlendFormula.createdAt, order: .reverse) private var savedFormulas: [BlendFormula]

    @State private var parsedList:  [ParsedRasyon] = []
    @State private var showPicker   = false
    @State private var isImporting  = false
    @State private var alertMsg:    String?
    @State private var showAlert    = false
    @State private var selectedFile = ""
    @State private var overwriteSet: Set<String> = []
    @State private var searchText   = ""

    // SingleBlend navigasyonu
    @State private var openInBlend:  BlendFormula?
    @State private var navigateBlend = false

    // Silme
    @State private var deleteTarget: BlendFormula?
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            List {

                // ── 1. Dosya yükle ─────────────────────────────
                Section("Dosya Yükle") {
                    Button {
                        showPicker = true
                    } label: {
                        Label(selectedFile.isEmpty ? "TXT Dosyası Seç" : selectedFile,
                              systemImage: "doc.text")
                    }

                    if !parsedList.isEmpty {
                        Button(role: .destructive) {
                            parsedList   = []
                            selectedFile = ""
                            overwriteSet = []
                        } label: {
                            Label("Dosyayı Temizle", systemImage: "xmark.circle")
                        }
                    }
                }

                // ── 2. Yüklenen dosya (oturum) ─────────────────
                if !parsedList.isEmpty {
                    Section {
                        ForEach(parsedList) { rasyon in
                            ParsedRasyonRow(
                                rasyon:           rasyon,
                                isSaved:          isSaved(rasyon),
                                willOverwrite:    overwriteSet.contains(rasyon.code),
                                onToggle:         { toggleOverwrite(rasyon.code) },
                                onSaveOne:        { saveOne(rasyon) },
                                onOpenBlend:      { openBlend(rasyon) }
                            )
                        }
                    } header: {
                        HStack {
                            Text("\(parsedList.count) rasyon bulundu")
                            Spacer()
                            Text("← kaydır: seçenek")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("🟠 = bu kod zaten kayıtlı. Satıra dokun → üzerine yaz moduna geç.")
                            .font(.caption)
                    }

                    Section {
                        Button {
                            importAll()
                        } label: {
                            if isImporting {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("Tümünü Kaydet (\(importableCount) rasyon)",
                                      systemImage: "square.and.arrow.down.on.square")
                                    .frame(maxWidth: .infinity)
                                    .bold()
                            }
                        }
                        .disabled(isImporting || importableCount == 0)
                    }
                }

                // ── 3. Kalıcı liste (SwiftData) ────────────────
                if !filteredSaved.isEmpty {
                    Section {
                        ForEach(filteredSaved) { formula in
                            NavigationLink(destination: RasyonDetailView(
                                formula:     formula,
                                onOpenBlend: {
                                    openInBlend   = formula
                                    navigateBlend = true
                                }
                            )) {
                                SavedFormulaRow(formula: formula)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget     = formula
                                    showDeleteAlert  = true
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                                Button {
                                    openInBlend   = formula
                                    navigateBlend = true
                                } label: {
                                    Label("SingleBlend", systemImage: "flask.fill")
                                }
                                .tint(.mint)
                            }
                        }
                    } header: {
                        Text("Kaydedilen Rasyonlar (\(filteredSaved.count))")
                    }
                } else if parsedList.isEmpty {
                    ContentUnavailableView(
                        "Henüz Rasyon Yok",
                        systemImage: "square.and.arrow.down",
                        description: Text("TXT dosyası seçerek rasyonları içe aktarın.")
                    )
                }
            }
            .searchable(text: $searchText, prompt: "Rasyon kodu veya adı ara")
            .navigationTitle("Rasyon İçe Aktar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateBlend) {
                if let f = openInBlend {
                    FormulaEditorView(formula: f)
                }
            }
            .sheet(isPresented: $showPicker) {
                TXTDocumentPicker { url in loadFile(url: url) }
            }
            .alert(alertMsg ?? "", isPresented: $showAlert) {
                Button("Tamam", role: .cancel) {}
            }
            .alert("Rasyonu Sil", isPresented: $showDeleteAlert, presenting: deleteTarget) { f in
                Button("Sil", role: .destructive) {
                    context.delete(f)
                    try? context.save()
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { f in
                Text("\"\(f.name)\" kalıcı olarak silinecek.")
            }
        }
    }

    // MARK: Computed

    private var existingCodes: Set<String> { Set(savedFormulas.map(\.code)) }

    private func isSaved(_ r: ParsedRasyon) -> Bool { existingCodes.contains(r.code) }

    private var importableCount: Int {
        parsedList.filter { !isSaved($0) || overwriteSet.contains($0.code) }.count
    }

    private var filteredSaved: [BlendFormula] {
        guard !searchText.isEmpty else { return savedFormulas }
        let q = searchText.lowercased()
        return savedFormulas.filter {
            $0.code.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }

    // MARK: Actions

    private func toggleOverwrite(_ code: String) {
        if overwriteSet.contains(code) { overwriteSet.remove(code) }
        else { overwriteSet.insert(code) }
    }

    private func loadFile(url: URL) {
        selectedFile = url.lastPathComponent
        do {
            if MultiBlendTransferParser.canParse(url: url) {
                // MultiBlend cihazlar arası aktarım formatı — besin kriterleriyle birlikte
                parsedList = MultiBlendTransferParser.parse(url: url)
            } else {
                parsedList = try RasyonTXTParser.parse(url: url)
            }
            if parsedList.isEmpty {
                alertMsg  = "Dosyada geçerli rasyon bulunamadı."
                showAlert = true
            }
        } catch {
            alertMsg  = "Dosya okunamadı: \(error.localizedDescription)"
            showAlert = true
        }
    }

    @discardableResult
    private func saveOne(_ rasyon: ParsedRasyon) -> BlendFormula {
        if let old = savedFormulas.first(where: { $0.code == rasyon.code }) {
            context.delete(old)
        }
        let f = makeFormula(rasyon)
        context.insert(f)
        try? context.save()
        return f
    }

    private func openBlend(_ rasyon: ParsedRasyon) {
        let formula: BlendFormula
        if let existing = savedFormulas.first(where: { $0.code == rasyon.code }) {
            formula = existing
        } else {
            formula = saveOne(rasyon)
        }
        openInBlend   = formula
        navigateBlend = true
    }

    private func importAll() {
        isImporting = true
        var saved = 0, skipped = 0

        for rasyon in parsedList {
            if isSaved(rasyon) && !overwriteSet.contains(rasyon.code) { skipped += 1; continue }
            if let old = savedFormulas.first(where: { $0.code == rasyon.code }) { context.delete(old) }
            context.insert(makeFormula(rasyon))
            saved += 1
        }

        do {
            try context.save()
            alertMsg = "✅ \(saved) rasyon kaydedildi" + (skipped > 0 ? ", \(skipped) atlandı" : "")
        } catch {
            alertMsg = "❌ Hata: \(error.localizedDescription)"
        }

        isImporting = false
        showAlert   = true
        // Dosya listesini temizle ama kaydedilenler altta görünmeye devam eder
        parsedList   = []
        selectedFile = ""
        overwriteSet = []
    }

    private func makeFormula(_ r: ParsedRasyon) -> BlendFormula {
        let f = BlendFormula(code: r.code, name: r.name, totalKg: r.totalKg)
        f.createdAt = r.date ?? Date()
        f.updatedAt = Date()

        let bfIngs = r.fullIngredients ?? RasyonTXTParser.toBFIngredients(from: r)
        f.ingredients = bfIngs
        if !r.constraints.isEmpty {
            f.constraints = r.constraints
        }

        // Çözüm sonuçlarını doldur → SingleBlend doğrudan gösterebilsin
        // Dosyada aynı koddan birden fazla satır gelebilir (kötü biçimli TXT) — son değeri kullan, çökme.
        let pctByCode = Dictionary(bfIngs.map { ($0.code, $0.mixPct) }, uniquingKeysWith: { _, new in new })
        let nutrientValues = Dictionary(
            r.constraints.compactMap { c in c.currentValue.map { (c.nutrientKey, $0) } },
            uniquingKeysWith: { _, new in new }
        )
        f.lastSolve = BFSolveResult(
            percentagesByCode: pctByCode,
            costPerTon:        0,
            nutrientValues:    nutrientValues,
            isFeasible:        true,
            message:           "TXT içe aktarım — \(r.code)",
            solvedAt:          r.date ?? Date()
        )
        return f
    }
}

// MARK: - Yüklenen dosya satırı (geçici)

private struct ParsedRasyonRow: View {
    let rasyon:        ParsedRasyon
    let isSaved:       Bool
    let willOverwrite: Bool
    let onToggle:      () -> Void
    let onSaveOne:     () -> Void
    let onOpenBlend:   () -> Void

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd.MM.yyyy"; return f
    }()

    var body: some View {
        Button(action: isSaved ? onToggle : {}) {
            HStack(spacing: 10) {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateColor)
                    .font(.system(size: 17))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rasyon.name).font(.subheadline.bold()).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(rasyon.code).font(.caption).foregroundStyle(.secondary)
                        if let d = rasyon.date {
                            Text("· \(Self.df.string(from: d))").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("· \(rasyon.ingredients.count) HM").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { onSaveOne() } label: {
                Label("Kaydet", systemImage: "square.and.arrow.down")
            }.tint(.blue)

            Button { onOpenBlend() } label: {
                Label("SingleBlend", systemImage: "flask.fill")
            }.tint(.mint)
        }
    }

    private var stateIcon: String {
        if isSaved && willOverwrite { return "arrow.triangle.2.circlepath.circle.fill" }
        if isSaved                  { return "exclamationmark.circle.fill" }
        return "circle"
    }
    private var stateColor: Color {
        if isSaved && willOverwrite { return .blue }
        if isSaved                  { return .orange }
        return Color(.systemGray4)
    }
}

// MARK: - Kaydedilmiş formül satırı (kalıcı)

private struct SavedFormulaRow: View {
    let formula: BlendFormula

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd.MM.yyyy"; return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 17))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(formula.name).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 4) {
                    Text(formula.code).font(.caption).foregroundStyle(.secondary)
                    Text("· \(Self.df.string(from: formula.createdAt))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("· \(formula.ingredients.filter(\.isActive).count) HM")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("· \(String(format: "%.0f", formula.totalKg)) kg")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Rasyon Detay (hammadde miktarları)

struct RasyonDetailView: View {
    let formula:     BlendFormula
    let onOpenBlend: () -> Void

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd.MM.yyyy"; return f
    }()

    private var sortedIngredients: [BFIngredient] {
        formula.ingredients.sorted { $0.mixPct > $1.mixPct }
    }

    var body: some View {
        List {
            // Başlık bilgisi
            Section {
                LabeledContent("Kod",    value: formula.code)
                LabeledContent("Ad",     value: formula.name)
                LabeledContent("Tarih",  value: Self.df.string(from: formula.createdAt))
                LabeledContent("Parti",  value: String(format: "%.0f kg", formula.totalKg))
                LabeledContent("Hammadde", value: "\(sortedIngredients.count) adet")
            }

            // Hammadde miktarları
            Section {
                // Başlık satırı
                HStack {
                    Text("Hammadde").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Miktar (kg)").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text("%").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .listRowBackground(Color(.systemGroupedBackground))

                ForEach(sortedIngredients) { ing in
                    let amountKg = ing.mixPct * formula.totalKg / 100.0
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ing.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(ing.code)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: "%.2f", amountKg))
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 80, alignment: .trailing)

                        Text(String(format: "%.2f", ing.mixPct))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                // Toplam
                HStack {
                    Text("TOPLAM").font(.caption.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.2f", formula.totalKg))
                        .font(.subheadline.monospacedDigit().bold())
                        .frame(width: 80, alignment: .trailing)
                    Text("100.00")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .listRowBackground(Color.accentColor.opacity(0.07))
            } header: {
                Text("Hammadde Kullanım Miktarları")
            }

            // SingleBlend'de aç
            Section {
                Button {
                    onOpenBlend()
                } label: {
                    Label("SingleBlend'de Aç", systemImage: "flask.fill")
                        .frame(maxWidth: .infinity)
                        .bold()
                }
                .tint(.mint)
            } footer: {
                Text("Çözüm sonuçları ve besin değerleri SingleBlend editöründe görünür.")
                    .font(.caption)
            }
        }
        .navigationTitle(formula.code)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Document Picker

private struct TXTDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.plainText]
        if let t = UTType("public.text") { types.append(t) }
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.allowsMultipleSelection = false
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
