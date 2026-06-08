import SwiftUI
import SwiftData

// MARK: - Ürün Sıralama (sürükle-bırak, kategori bazlı)

struct UrunSiralamaView: View {
    let brand: String

    @Query(sort: \ProductPricingMeta.orderIndex) private var allMetas:    [ProductPricingMeta]
    @Query(sort: \BlendFormula.code)             private var allFormulas:  [BlendFormula]
    @Environment(\.modelContext)                  private var context
    @Environment(\.dismiss)                       private var dismiss

    // PDF'deki kategori sırası
    private let kategoriler = [
        "SIĞIR SÜT YEMLERİ( 50 kg)",
        "SIĞIR BESİ YEMLERİ( 50 kg)",
        "SIĞIR BESİ TOZ YEMLERİ( 50 kg)",
        "KUZU TOKLU YEMLERİ( 50 kg)",
        "BUZAĞI YEMLERİ( 40-50 kg)",
        "ÖZEL YEMLER( 50 kg)",
        "KANATLI YEMLERİ ( 50 KG)",
    ]

    // Formül isim haritası
    private var formulaByCode: [String: BlendFormula] {
        Dictionary(allFormulas.map { ($0.code, $0) }, uniquingKeysWith: { f, _ in f })
    }

    // Markaya ait metalar
    private var brandMetas: [ProductPricingMeta] {
        allMetas.filter { $0.brand == brand }
    }

    // Kategori içindeki ürünler (sıralı)
    private func uruns(in cat: String) -> [ProductPricingMeta] {
        brandMetas.filter { $0.categoryGroup == cat }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    // Kategorisiz ürünler
    private var kategorisiz: [ProductPricingMeta] {
        brandMetas.filter { m in
            !kategoriler.contains(m.categoryGroup) || m.categoryGroup.isEmpty
        }
        .sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Kategorilere göre sıralı bölümler ─────────────────
                ForEach(kategoriler, id: \.self) { kat in
                    let items = uruns(in: kat)
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.formulaCode) { meta in
                                urunSatiri(meta)
                            }
                            .onMove { from, to in
                                tasiKategori(kat, from: from, to: to)
                            }
                        } header: {
                            Text(kat)
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // ── Kategorisiz ürünler ────────────────────────────────
                if !kategorisiz.isEmpty {
                    Section {
                        ForEach(kategorisiz, id: \.formulaCode) { meta in
                            urunSatiri(meta)
                        }
                        .onMove { from, to in
                            tasiListeden(kategorisiz, from: from, to: to)
                        }
                    } header: {
                        Text("KATEGORİSİZ")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(brand) Sıralama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
        }
    }

    // MARK: - Satır görünümü

    private func urunSatiri(_ meta: ProductPricingMeta) -> some View {
        HStack(spacing: 10) {
            // Sıra numarası
            Text("\(meta.orderIndex + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.orange, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(formulaByCode[meta.formulaCode]?.name ?? meta.formulaCode)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(meta.formulaCode)
                        .font(.caption2).foregroundStyle(.secondary)
                    if !meta.form.isEmpty {
                        Text(meta.form)
                            .font(.caption2).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.blue.opacity(0.7), in: Capsule())
                    }
                    Text("\(meta.bagKg) kg")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !meta.isVisible {
                Image(systemName: "eye.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Sıralama güncelleme

    private func tasiKategori(_ kat: String, from: IndexSet, to: Int) {
        var items = uruns(in: kat)
        items.move(fromOffsets: from, toOffset: to)
        for (idx, item) in items.enumerated() {
            item.orderIndex = idx
        }
        try? context.save()
    }

    private func tasiListeden(_ liste: [ProductPricingMeta], from: IndexSet, to: Int) {
        var items = liste
        items.move(fromOffsets: from, toOffset: to)
        for (idx, item) in items.enumerated() {
            item.orderIndex = idx
        }
        try? context.save()
    }
}
