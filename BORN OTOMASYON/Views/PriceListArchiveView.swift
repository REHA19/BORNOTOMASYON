import SwiftUI
import SwiftData
import QuickLook

// MARK: - Fiyat Listesi Arşivi

struct PriceListArchiveView: View {
    let brand: String

    @Query(sort: \PriceListArchive.savedAt, order: .reverse) private var allArchives: [PriceListArchive]
    @Environment(\.modelContext) private var context

    @State private var shareURL:   URL? = nil
    @State private var showShare       = false
    @State private var previewURL: URL? = nil
    @State private var snapshotArchive: PriceListArchive? = nil
    @State private var pendingDelete:   PriceListArchive? = nil

    private var archives: [PriceListArchive] {
        allArchives.filter { $0.brand == brand }
    }

    var body: some View {
        List {
            if archives.isEmpty {
                ContentUnavailableView(
                    "Kayıt Yok",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("\(brand) için henüz fiyat listesi oluşturulmadı.")
                )
            } else {
                ForEach(archives) { archive in
                    Button {
                        // PDF varsa (diskte ya da kayda gömülü) önizle;
                        // yoksa arşivdeki fiyat tablosunu uygulama içinde göster.
                        if let url = archive.resolvedPDFURL() {
                            previewURL = url
                        } else {
                            snapshotArchive = archive
                        }
                    } label: {
                        rowContent(archive)
                    }
                    .buttonStyle(.plain)
                    // Not: özel trailing swipe action'lar varsayılan silmeyi devre dışı
                    // bırakır — silme burada açıkça tanımlanır.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = archive
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                        Button {
                            snapshotArchive = archive
                        } label: {
                            Label("Fiyatlar", systemImage: "list.bullet.rectangle")
                        }
                        .tint(.indigo)
                    }
                }
                .onDelete(perform: deleteArchives)
            }
        }
        .navigationTitle("\(brand) Fiyat Arşivi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !archives.isEmpty {
                EditButton()
            }
        }
        .confirmationDialog(
            "Fiyat Listesini Sil",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let target = pendingDelete { delete(target) }
                pendingDelete = nil
            }
            Button("Vazgeç", role: .cancel) { pendingDelete = nil }
        } message: {
            if let a = pendingDelete {
                Text(a.isPublished
                     ? "“\(a.displayDate)” tarihli YAYINLANMIŞ liste kalıcı olarak silinecek. Bu liste fiyat karşılaştırmalarında baz olarak kullanılıyorsa, karşılaştırma bir önceki yayınlanan listeye kayar. Bu işlem geri alınamaz."
                     : "“\(a.displayDate)” tarihli kayıt kalıcı olarak silinecek. Bu işlem geri alınamaz.")
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(url: url) }
        }
        .sheet(item: $snapshotArchive) { archive in
            PriceSnapshotDetailView(archive: archive)
        }
        .quickLookPreview($previewURL)
        .onAppear {
            // Kayda gömülü PDF'i olan ama disk kopyası kaybolmuş kayıtları onar
            var repaired = false
            for archive in archives where archive.restorePDFToDocuments() { repaired = true }
            if repaired { try? context.save() }
        }
    }

    @ViewBuilder
    private func rowContent(_ archive: PriceListArchive) -> some View {
        let hasPDF = archive.hasPDF
        HStack(spacing: 12) {
            Image(systemName: hasPDF ? "doc.richtext.fill" : "list.bullet.rectangle")
                .font(.title2)
                .foregroundStyle(hasPDF ? .orange : .indigo)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(archive.displayDate)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    if archive.isPublished {
                        Text("YAYINDA")
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    if !archive.revision.isEmpty {
                        Text("Rev: \(archive.revision)")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if !archive.period.isEmpty {
                        Text(archive.period)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if hasPDF {
                    Text(archive.fileName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text("PDF yok — \(archive.prices.count) ürünlük fiyat listesi kayıtlı")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if hasPDF {
                Button {
                    shareURL  = archive.resolvedPDFURL()
                    showShare = shareURL != nil
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func deleteArchives(at offsets: IndexSet) {
        let targets = offsets.map { archives[$0] }
        for arc in targets { removeFiles(of: arc); context.delete(arc) }
        try? context.save()
    }

    private func delete(_ archive: PriceListArchive) {
        removeFiles(of: archive)
        context.delete(archive)
        try? context.save()
    }

    /// Kayda ait disk kopyalarını temizler (Documents + geçici önizleme dosyası).
    private func removeFiles(of archive: PriceListArchive) {
        if let url = archive.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        if !archive.fileName.isEmpty {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(archive.fileName)
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

// MARK: - Arşiv fiyat tablosu (PDF kayıpken de erişilebilir)

private struct PriceSnapshotDetailView: View {
    let archive: PriceListArchive

    @Environment(\.dismiss) private var dismiss

    private var sorted: [PriceSnap] {
        archive.prices.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Liste Bilgisi") {
                    LabeledContent("Marka", value: archive.brand)
                    if !archive.revision.isEmpty {
                        LabeledContent("Revizyon", value: archive.revision)
                    }
                    if !archive.period.isEmpty {
                        LabeledContent("Dönem", value: archive.period)
                    }
                    LabeledContent("Tarih", value: archive.displayDate)
                    LabeledContent("Ürün Sayısı", value: "\(archive.prices.count)")
                    if archive.isPublished {
                        LabeledContent("Durum") {
                            Text("YAYINDA").font(.caption.bold()).foregroundStyle(.green)
                        }
                    }
                }

                Section {
                    if sorted.isEmpty {
                        Text("Bu kayıtta fiyat verisi yok.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(sorted) { snap in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snap.name).font(.subheadline).lineLimit(1)
                                    Text(snap.code).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(fmt(snap.pesin))
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Peşin Fiyatlar (₺/çuval)")
                } footer: {
                    if !archive.hasPDF {
                        Text("Bu kaydın PDF dosyası cihazda bulunamadı (uygulama yeniden kurulmuş veya liste başka bir cihazda oluşturulmuş olabilir). Fiyat verisi kayıtlıdır ve karşılaştırmalarda kullanılır.")
                            .font(.caption2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Fiyat Arşivi Detayı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = Locale(identifier: "tr_TR")
        n.numberStyle = .decimal
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return (n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)) + " ₺"
    }
}
