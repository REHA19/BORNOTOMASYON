import SwiftUI
import SwiftData

struct StokRaporlarView: View {
    @Query(sort: \StokAylikRapor.yil, order: .reverse) private var raporlar: [StokAylikRapor]
    @Environment(\.modelContext) private var context

    @State private var deleteTarget:  StokAylikRapor? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        Group {
            if raporlar.isEmpty {
                ContentUnavailableView(
                    "Kayıtlı Rapor Yok",
                    systemImage: "archivebox",
                    description: Text("Stok Maliyeti ekranındaki \"Kaydet\" butonu ile aylık rapor oluşturabilirsiniz.")
                )
            } else {
                raporList
            }
        }
        .navigationTitle("Aylık Stok Raporları")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Raporu Sil", isPresented: $showDeleteAlert, presenting: deleteTarget) { rapor in
            Button("Sil", role: .destructive) {
                context.delete(rapor)
                try? context.save()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { rapor in
            Text("\"\(rapor.ayBaslik)\" raporu kalıcı olarak silinecek.")
        }
    }

    // MARK: - List

    private var raporList: some View {
        List {
            // Yıllara göre grupla
            let grouped = Dictionary(grouping: raporlar) { $0.yil }
            ForEach(grouped.keys.sorted(by: >), id: \.self) { yil in
                Section("\(yil)") {
                    ForEach(grouped[yil]!.sorted { $0.ay > $1.ay }) { rapor in
                        NavigationLink(destination: StokRaporDetayView(rapor: rapor)) {
                            raporCell(rapor)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget    = rapor
                                showDeleteAlert = true
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func raporCell(_ rapor: StokAylikRapor) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(rapor.ayBaslik)
                    .font(.headline)
                if rapor.isOtomatik {
                    Text("Oto")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.blue.opacity(0.8), in: Capsule())
                }
                Spacer()
                Text(rapor.grandTotal.tlString)
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Label(rapor.hammaddeToplam.tlString, systemImage: "shippingbox.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Label(rapor.manuelToplam.tlString, systemImage: "list.clipboard.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                let fmt = DateFormatter()
                let _ = { fmt.locale = Locale(identifier: "tr_TR"); fmt.dateFormat = "d MMMM HH:mm" }()
                Text(fmt.string(from: rapor.kayitTarihi))
                    .font(.caption2).foregroundStyle(.tertiary)
                if rapor.kayitSayisi > 1 {
                    Text("• \(rapor.kayitSayisi) kayıt")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
