import SwiftUI
import SwiftData

// MARK: - Fiyat Değişim Raporu
// İki yayınlanmış liste arasında peşin fiyat değişimini (zam oranı + miktar) karşılaştırır.

struct FiyatDegisimRaporuView: View {
    let brand: String
    /// Güncel maliyetlerden hesaplanan, henüz yayınlanmamış taslak fiyatlar.
    /// Doluysa varsayılan karşılaştırma "taslak vs en son yayınlanan liste" olur.
    var draftPrices: [PriceSnap] = []
    /// Maliyetlendirme ekranındaki ürün sırası (formül kodları).
    /// Rapor bu sırayı birebir kullanır — ekranlar arasında sıra farkı olmaz.
    var displayOrder: [String] = []

    @Query(sort: \PriceListArchive.savedAt, order: .reverse) private var allArchives: [PriceListArchive]

    @State private var oldSelection: PersistentIdentifier? = nil
    @State private var useDraft:     Bool = true

    private var published: [PriceListArchive] {
        allArchives.filter { $0.brand == brand && $0.isPublished }
    }

    private var hasDraft: Bool { !draftPrices.isEmpty }
    /// Taslak modunda karşılaştırma yapılabilmesi için tek bir yayınlanmış liste yeterli.
    private var comparingDraft: Bool { hasDraft && useDraft && !published.isEmpty }

    /// "Yeni" taraf: taslak modunda güncel hesap, aksi hâlde en son yayınlanan liste.
    private var newPrices: [PriceSnap] {
        comparingDraft ? draftPrices : (newList?.prices ?? [])
    }
    private var newLabel: String {
        comparingDraft ? "Güncel Taslak" : (newList.map(listLabel) ?? "—")
    }

    private var newList: PriceListArchive? { published.first }
    private var oldList: PriceListArchive? {
        // Taslak modunda baz DAİMA en son yayınlanan listedir.
        if comparingDraft {
            if let oldSelection, let found = published.first(where: { $0.persistentModelID == oldSelection }) {
                return found
            }
            return published.first
        }
        if let oldSelection, let found = published.first(where: { $0.persistentModelID == oldSelection }) {
            return found
        }
        return published.dropFirst().first   // varsayılan: bir önceki yayınlanan
    }

    /// Eski liste menüsünde seçilebilecek adaylar.
    private var oldCandidates: [PriceListArchive] {
        comparingDraft ? published : Array(published.dropFirst())
    }

    /// Rapor gösterilebilir mi — taslak varsa 1, yoksa 2 yayınlanmış liste gerekir.
    private var canCompare: Bool {
        hasDraft ? !published.isEmpty : published.count >= 2
    }

    // MARK: - Karşılaştırma satırı

    struct ChangeRow: Identifiable {
        let id = UUID()
        let code: String
        let name: String
        let oldPesin: Double?   // nil → yeni ürün
        let newPesin: Double?   // nil → listeden çıkarıldı
        var delta: Double? { guard let o = oldPesin, let n = newPesin else { return nil }; return n - o }
        var pct:   Double? { guard let o = oldPesin, o > 0, let n = newPesin else { return nil }; return (n - o) / o * 100 }
    }

    private var rows: [ChangeRow] {
        guard let oldList, !newPrices.isEmpty else { return [] }
        let newByCode = Dictionary(newPrices.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let oldByCode = Dictionary(oldList.prices.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let allCodes  = Set(newByCode.keys).union(oldByCode.keys)
        return allCodes.map { code in
            let n = newByCode[code]
            let o = oldByCode[code]
            return ChangeRow(
                code: code,
                name: n?.name ?? o?.name ?? code,
                oldPesin: o?.pesin,
                newPesin: n?.pesin
            )
        }
        .sorted(by: orderComparator)
    }

    /// Maliyetlendirme ekranındaki sıra baz alınır. O listede olmayan ürünler
    /// (ör. artık üretilmeyip yalnızca eski arşivde kalanlar) sona eklenir.
    private var orderIndexByCode: [String: Int] {
        Dictionary(displayOrder.enumerated().map { ($0.element, $0.offset) },
                   uniquingKeysWith: { first, _ in first })
    }

    private func orderComparator(_ lhs: ChangeRow, _ rhs: ChangeRow) -> Bool {
        let l = orderIndexByCode[lhs.code], r = orderIndexByCode[rhs.code]
        if let l, let r { return l < r }
        if l != nil { return true }     // maliyetlendirmede olan önce
        if r != nil { return false }
        return lhs.name < rhs.name      // ikisi de listede yoksa ada göre
    }

    private var matched: [ChangeRow] { rows.filter { $0.delta != nil } }
    private var avgPct: Double {
        let pcts = matched.compactMap { $0.pct }
        guard !pcts.isEmpty else { return 0 }
        return pcts.reduce(0, +) / Double(pcts.count)
    }

    var body: some View {
        Group {
            if !canCompare {
                ContentUnavailableView(
                    "Yeterli Liste Yok",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text(hasDraft
                        ? "Karşılaştırma için en az 1 yayınlanmış \(brand) listesi gerekir."
                        : "Karşılaştırma için en az 2 yayınlanmış \(brand) listesi gerekir.")
                )
            } else {
                reportList
            }
        }
        .navigationTitle("Fiyat Değişimi")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var reportList: some View {
        List {
            // ── Karşılaştırılan listeler ─────────────────────────────
            Section {
                if hasDraft && published.count >= 2 {
                    Picker("Karşılaştırma", selection: $useDraft) {
                        Text("Güncel Taslak").tag(true)
                        Text("Yayın Geçmişi").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: useDraft) { _, _ in oldSelection = nil }
                }

                LabeledContent("Yeni (güncel)") {
                    Text(newLabel).bold().foregroundStyle(.green)
                }
                // Eski liste seçici
                Menu {
                    ForEach(oldCandidates) { arc in
                        Button {
                            oldSelection = arc.persistentModelID
                        } label: {
                            HStack {
                                Text(listLabel(arc))
                                if arc.persistentModelID == (oldList?.persistentModelID) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Eski (baz)")
                        Spacer()
                        Text(oldList.map(listLabel) ?? "—")
                            .foregroundStyle(.orange)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
            } header: {
                Text("Karşılaştırma")
            } footer: {
                if comparingDraft {
                    Text("Güncel maliyetlerden hesaplanan fiyatlar, en son yayınlanan liste ile karşılaştırılıyor.")
                        .font(.caption2)
                }
            }

            // ── Özet ─────────────────────────────────────────────────
            Section("Özet") {
                summaryRow("Ortalama Zam", value: String(format: "%+.2f%%", avgPct),
                           color: avgPct > 0 ? .red : avgPct < 0 ? .green : .secondary)
                summaryRow("Zamlanan", value: "\(matched.filter { ($0.delta ?? 0) > 0.001 }.count) ürün", color: .red)
                summaryRow("İndirimli", value: "\(matched.filter { ($0.delta ?? 0) < -0.001 }.count) ürün", color: .green)
                summaryRow("Değişmeyen", value: "\(matched.filter { abs($0.delta ?? 0) <= 0.001 }.count) ürün", color: .secondary)
                if rows.contains(where: { $0.oldPesin == nil }) {
                    summaryRow("Yeni Ürün", value: "\(rows.filter { $0.oldPesin == nil }.count)", color: .blue)
                }
                if rows.contains(where: { $0.newPesin == nil }) {
                    summaryRow("Çıkarılan", value: "\(rows.filter { $0.newPesin == nil }.count)", color: .gray)
                }
            }

            // ── Detaylı liste ────────────────────────────────────────
            Section("Ürün Bazında Değişim") {
                ForEach(rows) { row in
                    changeRowView(row)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Satır görünümü

    @ViewBuilder
    private func changeRowView(_ row: ChangeRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.subheadline.bold()).lineLimit(1)
                Text(row.code).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let o = row.oldPesin, let n = row.newPesin {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(fmt(o)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        Text(fmt(n)).font(.subheadline.bold().monospacedDigit())
                    }
                    if let d = row.delta, let p = row.pct {
                        let clr: Color = d > 0.001 ? .red : d < -0.001 ? .green : .secondary
                        Text(String(format: "%+.2f ₺  (%+.2f%%)", d, p))
                            .font(.caption2.monospacedDigit()).foregroundStyle(clr)
                    }
                }
            } else if let n = row.newPesin {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmt(n)).font(.subheadline.bold().monospacedDigit())
                    Text("YENİ").font(.caption2.bold()).foregroundStyle(.blue)
                }
            } else if let o = row.oldPesin {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmt(o)).font(.caption.monospacedDigit()).strikethrough().foregroundStyle(.secondary)
                    Text("ÇIKARILDI").font(.caption2.bold()).foregroundStyle(.gray)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func summaryRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private func listLabel(_ a: PriceListArchive) -> String {
        if !a.revision.isEmpty { return a.revision }
        if !a.period.isEmpty   { return a.period }
        return a.displayDate
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = Locale(identifier: "tr_TR")
        n.numberStyle = .decimal
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return (n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)) + " ₺"
    }
}
