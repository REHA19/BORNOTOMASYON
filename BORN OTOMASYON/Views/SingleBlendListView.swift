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
                    Button { showNewFormula = true } label: {
                        Image(systemName: "plus")
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
            ForEach(formulas) { formula in
                NavigationLink(destination: FormulaEditorView(formula: formula)) {
                    FormulaRow(formula: formula)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget    = formula
                        showDeleteAlert = true
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                    Button {
                        duplicate(formula)
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

    private func duplicate(_ source: BlendFormula) {
        let copy = BlendFormula(
            code:    source.code + "_KOPYA",
            name:    source.name + " (Kopya)",
            totalKg: source.totalKg
        )
        copy.ingredientsJSON = source.ingredientsJSON
        copy.constraintsJSON = source.constraintsJSON
        copy.recordedCostTL  = source.recordedCostTL
        modelContext.insert(copy)
        try? modelContext.save()
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
