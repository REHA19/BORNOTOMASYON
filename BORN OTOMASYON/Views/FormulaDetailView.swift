import SwiftUI

struct FormulaDetailView: View {
    var formulaID:    Int?    = nil  // Backend FormulaID (en güvenilir)
    let productCode:  String          // Fallback: ürün kodu
    var fallbackCode: String = ""     // Fallback: formulaName
    let displayName:  String          // Başlık

    @State private var items:         [FormulaDetailItem] = []
    @State private var formula:       FormulaActiveResponse?
    @State private var isLoading      = false
    @State private var loadingMessage = "Yükleniyor..."
    @State private var errorMessage:  String?
    @State private var showCreateSheet = false

    private let service = FormulaDetailService()

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if errorMessage != nil {
                backendFixView

            } else if items.isEmpty {
                Text("Formül içeriği bulunamadı.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                List {
                    // Formül özet bilgisi
                    if let f = formula {
                        Section {
                            infoRow("Ürün Kodu",   value: f.materialCode)
                            infoRow("Ürün Adı",    value: f.materialName)
                            if let cn = f.customName,   !cn.isEmpty  { infoRow("Özel Ad",  value: cn) }
                            if let cv = f.customVersion,!cv.isEmpty  { infoRow("Versiyon", value: cv) }
                            infoRow("Toplam Miktar", value: fmtKg(f.totalAmount))
                        } header: { Text("Formül Bilgisi") }
                    }

                    // İçerik listesi
                    Section {
                        summaryRow("Hammadde Sayısı", value: "\(items.filter { !$0.isAdditive }.count) kalem")
                        summaryRow("Katkı Sayısı",    value: "\(items.filter { $0.isAdditive }.count) kalem")
                        summaryRow("Toplam",           value: fmtKg(items.reduce(0) { $0 + $1.amount }))
                    } header: { Text("Özet") }

                    Section {
                        ForEach(items) { item in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.materialName)
                                            .font(.subheadline).fontWeight(.medium)
                                        if item.isAdditive {
                                            Text("Katkı")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text(item.materialCode)
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(fmtKg(item.amount))
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(.accentColor)
                                    if let pct = item.percentage {
                                        Text(String(format: "%.1f%%", pct))
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("İçerik (\(items.count) kalem)")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !items.isEmpty {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Yeni Formül", systemImage: "plus.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateFormulaView(prefillName: displayName, prefillItems: items)
        }
    }

    // MARK: - Backend Fix Ekranı

    private var backendFixView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Backend Güncellemesi Gerekiyor", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
                    .foregroundColor(.orange)

                Text("ConsumptionGroup API yanıtına **FormulaID** alanı eklenince bu ekran otomatik çalışacak.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("C# — ConsumptionGroup yanıtına ekle:")
                        .font(.caption).foregroundColor(.secondary)
                    Text(backendCode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = backendCode
                    } label: {
                        Label("Kodu Kopyala", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                Button("Tekrar Dene (ID Taraması)") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    private let backendCode = """
    // ConsumptionGroup sorgu sonucuna ekle:
    FormulaID = formula != null ? formula.FormulaID : (int?)null

    // Record tanımına ekle:
    int? FormulaID
    """

    private func load() async {
        isLoading     = true
        loadingMessage = "Formül aranıyor..."
        errorMessage  = nil

        // Normal yolları dene
        if let result = try? await service.fetch(
            formulaID:    formulaID,
            productCode:  productCode,
            fallbackCode: fallbackCode
        ), !result.items.isEmpty {
            items         = result.items
            formula       = result.formula
            isLoading     = false
            return
        }

        // Paralel ID taraması
        loadingMessage = "Formül veritabanında aranıyor\n(GetFormulaApp ile 3000 ID taranıyor…)"
        let scanName = fallbackCode.isEmpty ? productCode : fallbackCode
        if let found = await service.scanRecentIDs(customName: scanName) {
            do {
                let result = try await service.joinPublic(found)
                items   = result.items
                formula = result.formula
                isLoading = false
                return
            } catch { }
        }

        errorMessage = nil   // backendFixView göster
        isLoading    = false
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    private func fmtKg(_ v: Double) -> String { v.kgString }
}
