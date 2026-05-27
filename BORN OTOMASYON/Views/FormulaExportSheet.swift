import SwiftUI
import SwiftData

struct FormulaExportSheet: View {
    let formula: BlendFormula
    let library: [FeedIngredient]

    @Environment(\.dismiss) private var dismiss
    @State private var shareItems:    [Any] = []
    @State private var showShareSheet = false
    @State private var isGenerating   = false

    var body: some View {
        NavigationStack {
            List {
                Section("Formül") {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(formula.name, systemImage: "flask.fill").font(.headline)
                        Text("Kod: \(formula.code)").font(.caption).foregroundStyle(.secondary)
                        let n = formula.ingredients.filter(\.isActive).count
                        Text("\(n) aktif hammadde  •  \(Int(formula.totalKg)) kg parti")
                            .font(.caption).foregroundStyle(.secondary)
                        if formula.currentCostTL > 0 {
                            Text(String(format: "Maliyet: %.2f TL/ton", formula.currentCostTL))
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    exportRow("PDF olarak dışa aktar",    "A4 dikey, tablo düzeni",        "doc.richtext.fill",  .red)   { share(.pdf) }
                    exportRow("Excel (CSV) olarak dışa aktar", "Excel / Numbers uyumlu",    "tablecells.fill",    .green)  { share(.csv) }
                    exportRow("Metin (TXT) olarak dışa aktar", "Düz metin, her uygulama",   "doc.plaintext.fill", .blue)   { share(.txt) }
                } header: {
                    Text("Format Seçin")
                } footer: {
                    Text("WhatsApp, E-posta, AirDrop ve tüm paylaşım kanallarıyla gönderilebilir.")
                }
            }
            .navigationTitle("Rapor Dışa Aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .overlay { if isGenerating { generatingOverlay } }
            .background {
                // ActivitySheet must be presented, not embedded — use zero-size background host
                if showShareSheet {
                    ActivitySheet(items: shareItems, isPresented: $showShareSheet)
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
    }

    // MARK: - Share (data extracted on main thread, generated on background)

    private enum Format { case pdf, csv, txt }

    private func share(_ format: Format) {
        isGenerating = true
        // Snapshot all SwiftData model data on @MainActor (thread-safe)
        let snapshot = FormulaSnapshot.make(formula: formula, library: library)
        let svc      = FormulaExportService(snap: snapshot)

        Task.detached(priority: .userInitiated) {
            let url: URL
            switch format {
            case .pdf: url = svc.writePDF()
            case .csv: url = svc.writeCSV()
            case .txt: url = svc.writeTXT()
            }
            await MainActor.run {
                isGenerating   = false
                shareItems     = [url]
                showShareSheet = true
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

// MARK: - UIActivityViewController bridge
// UIActivityViewController must be *presented*, not embedded as a child view.
// We use a transparent host VC that calls present() on viewDidAppear —
// this is the only reliable pattern on both iOS and macOS (Catalyst).

final class ActivityHostVC: UIViewController {
    var items: [Any]
    var onDismiss: () -> Void
    private var didPresent = false

    init(items: [Any], onDismiss: @escaping () -> Void) {
        self.items = items; self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresent else { return }
        didPresent = true

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.onDismiss()
        }
        // iPad + macOS Catalyst: popover needs an anchor or it won't appear
        if let pop = vc.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(vc, animated: true)
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items:       [Any]
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> ActivityHostVC {
        ActivityHostVC(items: items) { isPresented = false }
    }
    func updateUIViewController(_ vc: ActivityHostVC, context: Context) {
        vc.items = items
    }
}
