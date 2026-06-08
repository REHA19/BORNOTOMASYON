import SwiftUI
import SwiftData

// MARK: - Fiyat Listesi Arşivi

struct PriceListArchiveView: View {
    let brand: String

    @Query(sort: \PriceListArchive.savedAt, order: .reverse) private var allArchives: [PriceListArchive]
    @Environment(\.modelContext) private var context

    @State private var shareURL: URL?  = nil
    @State private var showShare       = false

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
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .font(.title2)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(archive.displayDate)
                                .font(.subheadline.bold())
                            if !archive.period.isEmpty {
                                Text(archive.period)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(archive.fileName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if archive.fileExists {
                            Button {
                                shareURL = archive.fileURL
                                showShare = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .help("Dosya bulunamadı")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteArchives)
            }
        }
        .navigationTitle("\(brand) Arşivi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !archives.isEmpty {
                EditButton()
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(url: url) }
        }
    }

    private func deleteArchives(at offsets: IndexSet) {
        for idx in offsets {
            let arc = archives[idx]
            if let url = arc.fileURL {
                try? FileManager.default.removeItem(at: url)
            }
            context.delete(arc)
        }
        try? context.save()
    }
}
