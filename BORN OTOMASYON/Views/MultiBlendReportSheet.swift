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

    init(group: MultiBlendGroup, allFormulas: [BlendFormula], library: [FeedIngredient]) {
        self.group       = group
        self.allFormulas = allFormulas
        self.library     = library
        _selectedCodes   = State(initialValue: Set(group.formulaCodes))
    }

    private var groupFormulas: [BlendFormula] {
        group.formulaCodes.compactMap { code in allFormulas.first { $0.code == code } }
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

                ForEach(groupFormulas) { formula in
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

                // ── Export format ──
                Section {
                    exportRow("PDF olarak dışa aktar",        "A4 yatay, tam detay raporlama",   "doc.richtext.fill",  .red)   { share(.pdf) }
                    exportRow("Excel (CSV) olarak dışa aktar","Excel / Numbers uyumlu",           "tablecells.fill",    .green)  { share(.csv) }
                    exportRow("Metin (TXT) olarak dışa aktar","Düz metin, her uygulama açar",    "doc.plaintext.fill", .blue)   { share(.txt) }
                } header: {
                    Text("Format Seçin")
                } footer: {
                    Text("Seçili \(selectedCodes.count) formül raporda yer alır. WhatsApp, E-posta, AirDrop ile paylaşılabilir.")
                }
            }
            .navigationTitle("MultiBlend Raporu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
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
        }
    }

    // MARK: - Row

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

    // MARK: - Share (snapshot on main thread → background generation)

    private enum Format { case pdf, csv, txt }

    private func share(_ format: Format) {
        guard !selectedCodes.isEmpty else { return }
        isGenerating = true

        // Build snapshot on @MainActor (safe SwiftData access)
        let orderedCodes = group.formulaCodes.filter { selectedCodes.contains($0) }
        let snapshot = MultiBlendSnapshot.make(
            group: group,
            selectedCodes: orderedCodes,
            allFormulas: allFormulas,
            library: library
        )
        let svc = MultiBlendExportService(snap: snapshot)

        Task.detached(priority: .userInitiated) {
            let url: URL
            switch format {
            case .pdf: url = svc.writePDF()
            case .csv: url = svc.writeCSV()
            case .txt: url = svc.writeTXT()
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
