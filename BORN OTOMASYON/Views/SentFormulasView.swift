import SwiftUI
import SwiftData

struct SentFormulasView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SendRecord.sentAt, order: .reverse) private var records: [SendRecord]

    @State private var deleteTarget: SendRecord?
    @State private var showClearConfirm = false
    @State private var clearMonth: String?

    // MARK: - Gruplama: Ay → kayıtlar

    private var grouped: [(month: String, date: Date, records: [SendRecord])] {
        let cal = Calendar.current
        var dict: [String: (date: Date, records: [SendRecord])] = [:]

        for rec in records {
            let comps = cal.dateComponents([.year, .month], from: rec.sentAt)
            let key   = monthKey(rec.sentAt)
            let anchor = cal.date(from: comps) ?? rec.sentAt
            if dict[key] == nil {
                dict[key] = (date: anchor, records: [])
            }
            dict[key]!.records.append(rec)
        }

        return dict
            .map { (month: $0.key, date: $0.value.date, records: $0.value.records) }
            .sorted { $0.date > $1.date }
    }

    private func monthKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date).capitalized
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .navigationTitle("Gönderilen Rasyonlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !records.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        summaryBadge
                    }
                }
            }
        }
    }

    // MARK: - List

    private var recordList: some View {
        List {
            ForEach(grouped, id: \.month) { group in
                Section {
                    ForEach(group.records) { rec in
                        NavigationLink(destination: SentRecordDetailView(record: rec)) {
                            RecordRow(record: rec)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(rec)
                                try? modelContext.save()
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    monthHeader(group)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Month header

    @ViewBuilder
    private func monthHeader(_ group: (month: String, date: Date, records: [SendRecord])) -> some View {
        let successCount = group.records.filter(\.isSuccess).count
        let failCount    = group.records.count - successCount

        HStack(spacing: 8) {
            Text(group.month)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .textCase(nil)

            Spacer()

            if successCount > 0 {
                Label("\(successCount)", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
            if failCount > 0 {
                Label("\(failCount)", systemImage: "xmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }

            // Ay temizle butonu
            Button {
                clearMonth = group.month
                showClearConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .alert("Ayı Temizle", isPresented: $showClearConfirm) {
            Button("Tümünü Sil", role: .destructive) {
                if let m = clearMonth {
                    deleteMonth(m)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\(clearMonth ?? "") ayına ait tüm gönderim kayıtları silinecek.")
        }
    }

    // MARK: - Özet badge (toolbar)

    private var summaryBadge: some View {
        let total   = records.count
        let success = records.filter(\.isSuccess).count
        return HStack(spacing: 6) {
            Label("\(success)/\(total)", systemImage: "paperplane.fill")
                .font(.caption.bold())
                .foregroundStyle(success == total ? .green : .orange)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "Gönderim Yok",
            systemImage: "paperplane",
            description: Text("SingleBlend veya MultiBlend'den rasyon gönderdikçe burada listelenir.")
        )
    }

    // MARK: - Delete month

    private func deleteMonth(_ month: String) {
        for rec in records where monthKey(rec.sentAt) == month {
            modelContext.delete(rec)
        }
        try? modelContext.save()
    }
}

// MARK: - Tek satır

private struct RecordRow: View {
    let record: SendRecord

    private var timeStr: String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMM HH:mm"
        return fmt.string(from: record.sentAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Başarı / hata ikonu
            Image(systemName: record.isSuccess
                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(record.isSuccess ? .green : .red)

            VStack(alignment: .leading, spacing: 3) {
                // Rasyon adı (customName)
                Text(record.customName.isEmpty ? record.formulaName : record.customName)
                    .font(.subheadline.bold())

                // Formül kodu + kaynak
                HStack(spacing: 6) {
                    Text("[\(record.formulaCode)]")
                        .font(.caption).foregroundStyle(.secondary)
                    sourceBadge
                }

                // Sunucu mesajı
                if !record.serverMessage.isEmpty {
                    Text(record.serverMessage)
                        .font(.caption2)
                        .foregroundStyle(record.isSuccess ? .green : .red)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(timeStr)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(record.ingredientCount) hmd")
                    .font(.caption2).foregroundStyle(.tertiary)
                if record.totalKg > 0 {
                    Text(String(format: "%.0f kg", record.totalKg))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceBadge: some View {
        let isSingle = record.source == "SingleBlend"
        return Text(isSingle ? "Single" : "Multi")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(isSingle ? Color.mint : Color.indigo, in: Capsule())
    }
}

// MARK: - Detay Sayfası

struct SentRecordDetailView: View {
    let record: SendRecord

    private var ingredients: [SentIngredientSnap] {
        record.snapshotIngredients.sorted { $0.amountKg > $1.amountKg }
    }

    private var sentDateStr: String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMMM yyyy, HH:mm"
        return fmt.string(from: record.sentAt)
    }

    var body: some View {
        List {
            // ── Özet ──────────────────────────────────────────────────────────
            Section("Gönderim Bilgisi") {
                infoRow("Rasyon Adı",
                        record.customName.isEmpty ? record.formulaName : record.customName)
                if !record.customVersion.isEmpty {
                    infoRow("Dosya Adı / Versiyon", record.customVersion)
                }
                infoRow("Ürün Kodu",   record.formulaCode)
                infoRow("Ürün Adı",    record.formulaName)
                infoRow("Kaynak",      record.source)
                infoRow("Gönderim",    sentDateStr)
                infoRow("Parti",       String(format: "%.0f kg", record.totalKg))

                HStack {
                    Text("Durum")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(record.isSuccess ? "Başarılı" : "Hatalı",
                          systemImage: record.isSuccess
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(record.isSuccess ? .green : .red)
                }

                if !record.serverMessage.isEmpty {
                    Text(record.serverMessage)
                        .font(.caption)
                        .foregroundStyle(record.isSuccess ? .green : .secondary)
                }
            }

            // ── Hammaddeler ────────────────────────────────────────────────────
            Section {
                if ingredients.isEmpty {
                    Text("İçerik kaydedilmemiş (eski kayıt).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { i, snap in
                        HStack(spacing: 12) {
                            Text("\(i + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.name)
                                    .font(.subheadline)
                                Text("[\(snap.code)]")
                                    .font(.caption).foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.2f kg", snap.amountKg))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.orange)
                                Text(String(format: "%%%.2f", snap.mixPct))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("Hammaddeler (\(ingredients.count) kalem)")
                    Spacer()
                    if !ingredients.isEmpty {
                        Text(String(format: "Toplam: %.0f kg", ingredients.reduce(0) { $0 + $1.amountKg }))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(record.customName.isEmpty ? record.formulaName : record.customName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}
