import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - MultiBlend formül içe aktarım
//
// MultiBlend grubunun kendi ekranından TXT formül dosyası yükler. İki format da
// tanınır:
//   • MultiBlend aktarım TXT'si (@@@FORMUL@@@ — hammadde min/max/mix ve besin
//     kriterleriyle birlikte kayıpsız)
//   • Klasik rasyon TXT'si (RasyonTXTParser)
// İçe aktarılan formüller BlendFormula olarak kaydedilir ve istenirse aynı anda
// bu gruba eklenir — böylece "Rasyon İçe Aktar" ekranına gidip formülü tekrar
// gruba ekleme adımı ortadan kalkar.

struct MultiBlendImportSheet: View {
    let group: MultiBlendGroup

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query private var savedFormulas: [BlendFormula]

    @State private var parsedList:    [ParsedRasyon] = []
    @State private var selectedCodes: Set<String>    = []
    @State private var overwriteSet:  Set<String>    = []
    @State private var addToGroup     = true
    @State private var showPicker     = false
    @State private var selectedFile   = ""
    @State private var isImporting    = false
    @State private var alertMsg:      String? = nil
    @State private var showAlert      = false

    private var existingCodes: Set<String> { Set(savedFormulas.map(\.code)) }

    /// Kaydedilecek formüller: seçili olan ve (yeni ya da üzerine-yaz işaretli) olanlar
    private var importable: [ParsedRasyon] {
        parsedList.filter {
            selectedCodes.contains($0.code) &&
            (!existingCodes.contains($0.code) || overwriteSet.contains($0.code))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showPicker = true
                    } label: {
                        Label(selectedFile.isEmpty ? "TXT Dosyası Seç" : selectedFile,
                              systemImage: "doc.text")
                    }
                    if !parsedList.isEmpty {
                        Button(role: .destructive) { clear() } label: {
                            Label("Dosyayı Temizle", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text("Dosya")
                } footer: {
                    Text("MultiBlend aktarım TXT'si (hammadde oranları + besin kriterleri) ve klasik rasyon TXT'si otomatik tanınır.")
                        .font(.caption2)
                }

                if !parsedList.isEmpty {
                    Section {
                        Toggle(isOn: $addToGroup) {
                            Label("\u{201C}\(group.name)\u{201D} grubuna da ekle", systemImage: "rectangle.3.group.fill")
                        }
                    }

                    Section {
                        HStack {
                            Button(selectedCodes.count == parsedList.count ? "Hiçbirini Seçme" : "Tümünü Seç") {
                                selectedCodes = selectedCodes.count == parsedList.count
                                    ? [] : Set(parsedList.map(\.code))
                            }
                            .font(.caption.bold())
                            Spacer()
                            Text("\(selectedCodes.count)/\(parsedList.count) seçili")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(parsedList) { r in
                            importRow(r)
                        }
                    } header: {
                        Text("\(parsedList.count) formül bulundu")
                    } footer: {
                        Text("🟠 bu kod zaten kayıtlı — satıra dokunarak \u{201C}üzerine yaz\u{201D} moduna alın, yoksa atlanır.")
                            .font(.caption2)
                    }

                    Section {
                        Button {
                            performImport()
                        } label: {
                            if isImporting {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("İçe Aktar (\(importable.count) formül)",
                                      systemImage: "square.and.arrow.down.on.square")
                                    .frame(maxWidth: .infinity).bold()
                            }
                        }
                        .disabled(isImporting || importable.isEmpty)
                    }
                } else {
                    ContentUnavailableView(
                        "Dosya Seçilmedi",
                        systemImage: "square.and.arrow.down",
                        description: Text("İçe aktarmak istediğiniz formül TXT dosyasını seçin.")
                    )
                }
            }
            .navigationTitle("Formül İçe Aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                MultiBlendTXTPicker { url in loadFile(url: url) }
            }
            .alert(alertMsg ?? "", isPresented: $showAlert) {
                Button("Tamam", role: .cancel) {
                    if (alertMsg ?? "").hasPrefix("✅") { dismiss() }
                }
            }
        }
    }

    // MARK: - Satır

    @ViewBuilder
    private func importRow(_ r: ParsedRasyon) -> some View {
        let exists   = existingCodes.contains(r.code)
        let selected = selectedCodes.contains(r.code)
        let willOver = overwriteSet.contains(r.code)
        Button {
            if selected && exists {
                // Seçiliyken dokunmak üzerine-yaz durumunu değiştirir
                if willOver { overwriteSet.remove(r.code) } else { overwriteSet.insert(r.code) }
            } else if selected {
                selectedCodes.remove(r.code)
            } else {
                selectedCodes.insert(r.code)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(.subheadline.bold()).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(r.code).font(.caption).foregroundStyle(.secondary)
                        Text("· \(r.ingredients.count) hammadde")
                            .font(.caption).foregroundStyle(.secondary)
                        if !r.constraints.isEmpty {
                            Text("· \(r.constraints.count) besin kriteri")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if exists {
                    Text(willOver ? "ÜZERİNE YAZ" : "KAYITLI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(willOver ? Color.blue : Color.orange, in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Aksiyonlar

    private func clear() {
        parsedList = []; selectedCodes = []; overwriteSet = []; selectedFile = ""
    }

    private func loadFile(url: URL) {
        selectedFile = url.lastPathComponent
        do {
            let list: [ParsedRasyon]
            if MultiBlendTransferParser.canParse(url: url) {
                list = MultiBlendTransferParser.parse(url: url)
            } else {
                list = try RasyonTXTParser.parse(url: url)
            }
            parsedList    = list
            selectedCodes = Set(list.map(\.code))
            overwriteSet  = []
            if list.isEmpty {
                alertMsg = "Dosyada geçerli formül bulunamadı."; showAlert = true
            }
        } catch {
            alertMsg  = "Dosya okunamadı: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func performImport() {
        isImporting = true
        var saved = 0
        var addedToGroup = 0

        for r in importable {
            if let old = savedFormulas.first(where: { $0.code == r.code }) { context.delete(old) }
            context.insert(makeFormula(r))
            saved += 1
            if addToGroup, !group.formulaCodes.contains(r.code) {
                group.addFormula(code: r.code)
                addedToGroup += 1
            }
        }

        do {
            try context.save()
            var msg = "✅ \(saved) formül içe aktarıldı"
            if addToGroup { msg += ", \(addedToGroup) tanesi gruba eklendi" }
            let skipped = selectedCodes.count - saved
            if skipped > 0 { msg += " (\(skipped) kayıtlı formül atlandı)" }
            alertMsg = msg
        } catch {
            alertMsg = "❌ Kaydedilemedi: \(error.localizedDescription)"
        }
        isImporting = false
        showAlert   = true
        parsedList  = []
        selectedCodes = []
        overwriteSet  = []
        selectedFile  = ""
    }

    /// RasyonImportView.makeFormula ile aynı davranış — tek yerde değişirse ikisi de güncellenmeli.
    private func makeFormula(_ r: ParsedRasyon) -> BlendFormula {
        let f = BlendFormula(code: r.code, name: r.name, totalKg: r.totalKg)
        f.createdAt = r.date ?? Date()
        f.updatedAt = Date()

        let bfIngs = r.fullIngredients ?? RasyonTXTParser.toBFIngredients(from: r)
        f.ingredients = bfIngs
        if !r.constraints.isEmpty { f.constraints = r.constraints }

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

// MARK: - Document Picker

private struct MultiBlendTXTPicker: UIViewControllerRepresentable {
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
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
