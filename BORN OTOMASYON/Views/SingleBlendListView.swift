import SwiftUI
import SwiftData

struct SingleBlendListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlendFormula.updatedAt, order: .reverse) private var formulas:  [BlendFormula]
    @Query                                                 private var library:    [FeedIngredient]

    @State private var showNewFormula   = false
    @State private var deleteTarget:    BlendFormula?
    @State private var showDeleteAlert  = false
    @State private var exportTarget:    BlendFormula?
    @State private var sendTarget:      BlendFormula?

    // Kopyala / Yapıştır
    @State private var clipboard:       BlendFormula?    = nil
    @State private var showPasteSheet   = false

    var body: some View {
        NavigationStack {
            Group {
                if formulas.isEmpty {
                    emptyState
                } else {
                    formulaList
                }
            }
            .navigationTitle("SingleBlend Formüller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 14) {
                        // Panoda formül varsa yapıştır butonu toolbar'da da görünsün
                        if clipboard != nil {
                            Button {
                                showPasteSheet = true
                            } label: {
                                Label("Yapıştır", systemImage: "doc.on.clipboard.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        Button { showNewFormula = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewFormula) {
                FormulaEditorView(formula: nil)
            }
            .sheet(item: $exportTarget) { f in
                FormulaExportSheet(formula: f, library: library)
            }
            .sheet(item: $sendTarget) { f in
                SendFormulaSheet(formula: f)
            }
            .sheet(isPresented: $showPasteSheet) {
                if let source = clipboard {
                    PasteFormulaSheet(source: source) { newCode, newName in
                        pasteFormula(source: source, code: newCode, name: newName)
                    }
                }
            }
            .alert("Formülü Sil", isPresented: $showDeleteAlert, presenting: deleteTarget) { f in
                Button("Sil", role: .destructive) { delete(f) }
                Button("Vazgeç", role: .cancel) {}
            } message: { f in
                Text("\"\(f.name)\" formülü kalıcı olarak silinecek.")
            }
        }
    }

    // MARK: - List

    private var formulaList: some View {
        List {
            // Panoda formül varsa üstte bilgi bandı göster
            if let src = clipboard {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Kopyalandı: \(src.name)")
                                .font(.subheadline.bold())
                            Text("Yapıştırmak için bir formüle basılı tutun veya + yanındaki butona dokunun.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            clipboard = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(formulas) { formula in
                NavigationLink(destination: FormulaEditorView(formula: formula)) {
                    FormulaRow(formula: formula)
                }
                .contextMenu {
                    // Kopyala
                    Button {
                        clipboard = formula
                    } label: {
                        Label("Kopyala", systemImage: "doc.on.doc")
                    }
                    // Yapıştır — sadece panoda bir şey varsa göster
                    if clipboard != nil {
                        Button {
                            showPasteSheet = true
                        } label: {
                            Label("Yapıştır (Yeni Ürün)", systemImage: "doc.on.clipboard")
                        }
                    }
                    Divider()
                    Button {
                        exportTarget = formula
                    } label: {
                        Label("Rapor", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        sendTarget = formula
                    } label: {
                        Label("Gönder", systemImage: "paperplane.fill")
                    }
                    Divider()
                    Button(role: .destructive) {
                        deleteTarget    = formula
                        showDeleteAlert = true
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget    = formula
                        showDeleteAlert = true
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                    Button {
                        clipboard = formula
                    } label: {
                        Label("Kopyala", systemImage: "doc.on.doc")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        exportTarget = formula
                    } label: {
                        Label("Rapor", systemImage: "square.and.arrow.up")
                    }
                    .tint(.indigo)
                    Button {
                        sendTarget = formula
                    } label: {
                        Label("Gönder", systemImage: "paperplane.fill")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView(
            "Formül Yok",
            systemImage: "flask",
            description: Text("Sağ üstteki + butonuna basarak yeni formül oluşturun.")
        )
    }

    // MARK: - Actions

    private func delete(_ formula: BlendFormula) {
        modelContext.delete(formula)
        try? modelContext.save()
    }

    private func pasteFormula(source: BlendFormula, code: String, name: String) {
        let copy = BlendFormula(code: code, name: name, totalKg: source.totalKg)
        copy.ingredientsJSON  = source.ingredientsJSON
        copy.constraintsJSON  = source.constraintsJSON
        copy.combinationsJSON = source.combinationsJSON
        copy.recordedCostTL   = 0
        modelContext.insert(copy)
        try? modelContext.save()
    }
}

// MARK: - Yapıştır Sheet (yeni isim ve kod girişi)

private struct PasteFormulaSheet: View {
    let source:    BlendFormula
    let onConfirm: (String, String) -> Void   // (code, name)

    @Environment(\.dismiss) private var dismiss

    @State private var newCode: String = ""
    @State private var newName: String = ""
    @FocusState private var focusedField: Field?

    enum Field { case code, name }

    private var canSave: Bool {
        !newCode.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Kaynak Formül", value: source.name)
                    LabeledContent("Kaynak Kod",    value: source.code)
                    LabeledContent("Hammadde Sayısı",
                                   value: "\(source.ingredients.filter(\.isActive).count) aktif")
                } header: { Text("Kopyalanacak Formül") }

                Section {
                    HStack {
                        Text("Yeni Kod")
                        Spacer()
                        TextField("örn. 152.999", text: $newCode)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .focused($focusedField, equals: .code)
                    }
                    HStack {
                        Text("Yeni Ad")
                        Spacer()
                        TextField("örn. ALAPALA YEM PRO", text: $newName)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .name)
                    }
                } header: { Text("Yeni Ürün Bilgileri") }
                 footer: { Text("Hammaddeler, kısıtlar ve kombinasyonlar kopyalanır. Maliyet sıfırdan başlar.") }
            }
            .navigationTitle("Yeni Ürün Oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur") {
                        let code = newCode.trimmingCharacters(in: .whitespaces)
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        onConfirm(code, name)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                newCode = source.code + "_2"
                newName = source.name + " (Kopya)"
                focusedField = .code
            }
        }
    }
}

// MARK: - Row

private struct FormulaRow: View {
    let formula: BlendFormula

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formula.name)
                        .font(.headline)
                    Text(formula.code)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if formula.currentCostTL > 0 {
                        Text(formula.currentCostTL.tlString + "/ton")
                            .font(.subheadline).bold().foregroundStyle(.orange)
                        Text("Güncel Maliyet")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if formula.recordedCostTL > 0 {
                        Text(formula.recordedCostTL.tlString + "/ton")
                            .font(.subheadline).bold().foregroundStyle(.secondary)
                        Text("Kaydedilen")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Label(String(format: "%.0f kg parti", formula.totalKg),
                      systemImage: "scalemass")
                    .font(.caption).foregroundStyle(.secondary)
                Label("\(formula.ingredients.filter(\.isActive).count) aktif hammadde",
                      systemImage: "list.bullet")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let solve = formula.lastSolve {
                HStack(spacing: 4) {
                    Image(systemName: solve.isFeasible ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(solve.isFeasible ? .green : .red)
                        .font(.caption)
                    Text(solve.isFeasible ? "Son çözüm: \(solve.solvedAt.trClock)" : "Çözüm bulunamadı")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
