import SwiftUI
import SwiftData

struct StokRaporDetayView: View {
    let rapor: StokAylikRapor

    @Query(sort: \BrandDefinition.orderIndex) private var brands: [BrandDefinition]

    @State private var isGenerating          = false
    @State private var showAntetPicker       = false
    @State private var pendingAntet: UIImage? = nil
    @State private var hasPendingExport       = false
    @State private var sortMode: SortMode    = .byAmountDesc

    enum SortMode: String, CaseIterable, Identifiable {
        case byAmountDesc = "Tutar ↓"
        case byAmountAsc  = "Tutar ↑"
        case alphabetical = "A–Z"
        var id: String { rawValue }
    }

    private var snap: StokRaporSnapshot? { rapor.snapshot }

    private var sortedHammadde: [HammaddeSnapshot] {
        guard let rows = snap?.hammaddeler else { return [] }
        switch sortMode {
        case .byAmountDesc:  return rows.sorted { $0.totalTL > $1.totalTL }
        case .byAmountAsc:   return rows.sorted { $0.totalTL < $1.totalTL }
        case .alphabetical:  return rows.sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        Group {
            if let snap {
                detailList(snap: snap)
            } else {
                ContentUnavailableView("Rapor verisi okunamadı", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(rapor.ayBaslik)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    Picker("Sıralama", selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Button {
                        exportPDF()
                    } label: {
                        if isGenerating {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isGenerating)
                }
            }
        }
        .sheet(isPresented: $showAntetPicker, onDismiss: {
            if hasPendingExport {
                hasPendingExport = false
                doExport(antet: pendingAntet)
            }
        }) {
            AntetSecimSheet(brands: brands.filter { $0.antetImage != nil }) { brand in
                pendingAntet = brand?.antetImage
                hasPendingExport = true
            }
        }
    }

    // MARK: - Detail list

    private func detailList(snap: StokRaporSnapshot) -> some View {
        List {
            // Özet kart
            Section {
                summaryCard(snap: snap)
            }

            // Kur bilgisi
            if snap.usdRate > 0 || snap.eurRate > 0 {
                Section {
                    var parts: [String] = []
                    let _ = { if snap.usdRate > 0 { parts.append(String(format: "1 $ = %.2f ₺", snap.usdRate)) }
                               if snap.eurRate > 0 { parts.append(String(format: "1 € = %.2f ₺", snap.eurRate)) } }()
                    Text(parts.joined(separator: "  •  "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            // Hammadde tablosu
            Section {
                ForEach(sortedHammadde) { row in
                    hammaddeCell(row)
                }
            } header: {
                Text("Hammadde Stoğu (\(sortedHammadde.count))")
            } footer: {
                Text("Toplam: \(snap.hammaddeToplam.tlString)")
                    .font(.caption2.bold())
            }

            // Manuel kalemler
            if !snap.manuelKalemler.isEmpty {
                Section {
                    ForEach(snap.manuelKalemler) { item in
                        manuelCell(item)
                    }
                } header: {
                    Text("Manuel Kalemler (\(snap.manuelKalemler.count))")
                } footer: {
                    Text("Toplam: \(snap.manuelToplam.tlString)")
                        .font(.caption2.bold())
                }
            }

            // Kayıt bilgisi
            Section {
                let dateFmt = DateFormatter()
                let _ = { dateFmt.locale = Locale(identifier: "tr_TR")
                           dateFmt.dateFormat = "d MMMM yyyy, HH:mm" }()
                LabeledContent("Son Kayıt", value: dateFmt.string(from: rapor.kayitTarihi))
                LabeledContent("Kayıt Sayısı", value: "\(rapor.kayitSayisi)")
                if rapor.isOtomatik {
                    Label("Otomatik kaydedildi", systemImage: "clock.badge.checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Bilgi") }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Cells

    private func summaryCard(snap: StokRaporSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label("Hammadde Stoğu", systemImage: "shippingbox.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(snap.hammaddeToplam.tlString).font(.subheadline.bold())
            }
            HStack {
                Label("Manuel Kalemler", systemImage: "list.clipboard.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(snap.manuelToplam.tlString).font(.subheadline.bold())
            }
            Divider()
            HStack {
                Text("TOPLAM STOK DEĞERİ")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(snap.grandTotal.tlString)
                    .font(.title3.bold()).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    private func hammaddeCell(_ row: HammaddeSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 10) {
                    Text(row.stockKg.kgString).font(.caption).foregroundStyle(.secondary)
                    if let p = row.priceTL {
                        Text("× \(p.tlString)/ton").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(row.priceTL == nil ? "—" : row.totalTL.tlString)
                .font(.subheadline.bold())
                .foregroundStyle(row.priceTL == nil ? .secondary : .primary)
        }
        .opacity(row.priceTL == nil ? 0.55 : 1)
    }

    private func manuelCell(_ item: ManuelKalemSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).font(.subheadline.bold())
                    if !item.category.isEmpty {
                        Text(item.category).font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
                }
                Text(String(format: "%.2f %@ × %.2f %@", item.quantity, item.unit, item.unitPrice, item.currency))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.totalTL.tlString).font(.subheadline.bold())
        }
    }

    // MARK: - PDF

    private func exportPDF() {
        let brandsWithAntet = brands.filter { $0.antetImage != nil }
        if brandsWithAntet.count > 1 {
            showAntetPicker = true
        } else {
            doExport(antet: brandsWithAntet.first?.antetImage)
        }
    }

    private func doExport(antet: UIImage?) {
        isGenerating = true
        let raporRef = rapor
        Task.detached(priority: .userInitiated) {
            let data = StokPDFService.generate(rapor: raporRef, antet: antet)
            let safe = raporRef.ayBaslik.replacingOccurrences(of: " ", with: "_")
            let url  = FileManager.default.temporaryDirectory
                .appendingPathComponent("StokRaporu_\(safe).pdf")
            try? data.write(to: url)
            await MainActor.run {
                isGenerating = false
                ShareService.share(items: [url])
            }
        }
    }
}
