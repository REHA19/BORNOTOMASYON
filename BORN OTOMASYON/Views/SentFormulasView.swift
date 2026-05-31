import SwiftUI
import SwiftData

struct SentFormulasView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SendRecord.sentAt, order: .reverse) private var records: [SendRecord]

    @State private var showClearConfirm = false
    @State private var clearKey: String?
    @State private var clearIsMonth = false

    // MARK: - Gruplama: Ay → Gün → Kayıtlar

    struct DayGroup: Identifiable {
        let id:      String   // "22 Mayıs 2026"
        let date:    Date
        var records: [SendRecord]
    }

    struct MonthGroup: Identifiable {
        let id:      String   // "Mayıs 2026"
        let date:    Date
        var days:    [DayGroup]
        var allRecords: [SendRecord] { days.flatMap(\.records) }
    }

    private var grouped: [MonthGroup] {
        let cal = Calendar.current
        var monthDict: [String: (date: Date, dayDict: [String: (date: Date, recs: [SendRecord])])] = [:]

        for rec in records {
            let mKey    = monthKey(rec.sentAt)
            let dKey    = dayKey(rec.sentAt)
            let mAnchor = cal.date(from: cal.dateComponents([.year, .month], from: rec.sentAt)) ?? rec.sentAt
            let dAnchor = cal.date(from: cal.dateComponents([.year, .month, .day], from: rec.sentAt)) ?? rec.sentAt

            if monthDict[mKey] == nil {
                monthDict[mKey] = (date: mAnchor, dayDict: [:])
            }
            if monthDict[mKey]!.dayDict[dKey] == nil {
                monthDict[mKey]!.dayDict[dKey] = (date: dAnchor, recs: [])
            }
            monthDict[mKey]!.dayDict[dKey]!.recs.append(rec)
        }

        return monthDict
            .map { mKey, mVal -> MonthGroup in
                let days = mVal.dayDict
                    .map { dKey, dVal in DayGroup(id: dKey, date: dVal.date, records: dVal.recs) }
                    .sorted { $0.date > $1.date }
                return MonthGroup(id: mKey, date: mVal.date, days: days)
            }
            .sorted { $0.date > $1.date }
    }

    private func monthKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date).capitalized
    }

    private func dayKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMMM yyyy"
        return fmt.string(from: date)
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
            .alert("Sil", isPresented: $showClearConfirm) {
                Button("Tümünü Sil", role: .destructive) {
                    if let key = clearKey { deleteByKey(key, isMonth: clearIsMonth) }
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("\(clearKey ?? "") tarihine ait tüm gönderim kayıtları silinecek.")
            }
        }
    }

    // MARK: - List

    private var recordList: some View {
        List {
            ForEach(grouped) { month in
                Section {
                    ForEach(month.days) { day in
                        DisclosureGroup {
                            ForEach(day.records) { rec in
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
                        } label: {
                            dayLabel(day)
                        }
                    }
                } header: {
                    monthHeader(month)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Gün etiketi

    @ViewBuilder
    private func dayLabel(_ day: DayGroup) -> some View {
        let success = day.records.filter(\.isSuccess).count
        let fail    = day.records.count - success
        HStack(spacing: 8) {
            Text(day.id)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Spacer()
            if success > 0 {
                Label("\(success)", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.green).labelStyle(.titleAndIcon)
            }
            if fail > 0 {
                Label("\(fail)", systemImage: "xmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.red).labelStyle(.titleAndIcon)
            }
            Button {
                clearKey = day.id; clearIsMonth = false; showClearConfirm = true
            } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Ay başlığı

    @ViewBuilder
    private func monthHeader(_ month: MonthGroup) -> some View {
        let all     = month.allRecords
        let success = all.filter(\.isSuccess).count
        let fail    = all.count - success
        HStack(spacing: 8) {
            Text(month.id)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .textCase(nil)
            Spacer()
            if success > 0 {
                Label("\(success)", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.green).labelStyle(.titleAndIcon)
            }
            if fail > 0 {
                Label("\(fail)", systemImage: "xmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.red).labelStyle(.titleAndIcon)
            }
            Button {
                clearKey = month.id; clearIsMonth = true; showClearConfirm = true
            } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Özet badge

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

    // MARK: - Silme

    private func deleteByKey(_ key: String, isMonth: Bool) {
        let toDelete = isMonth
            ? records.filter { monthKey($0.sentAt) == key }
            : records.filter { dayKey($0.sentAt) == key }
        toDelete.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
}

// MARK: - Tek satır

private struct RecordRow: View {
    let record: SendRecord

    private var timeStr: String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: record.sentAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(record.isSuccess ? .green : .red)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.customName.isEmpty ? record.formulaName : record.customName)
                    .font(.subheadline.bold())
                HStack(spacing: 6) {
                    Text("[\(record.formulaCode)]")
                        .font(.caption).foregroundStyle(.secondary)
                    sourceBadge
                }
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
            .padding(.horizontal, 5).padding(.vertical, 2)
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
            Section("Gönderim Bilgisi") {
                infoRow("Rasyon Adı", record.customName.isEmpty ? record.formulaName : record.customName)
                if !record.customVersion.isEmpty {
                    infoRow("Dosya Adı / Versiyon", record.customVersion)
                }
                infoRow("Ürün Kodu",   record.formulaCode)
                infoRow("Ürün Adı",    record.formulaName)
                infoRow("Kaynak",      record.source)
                infoRow("Gönderim",    sentDateStr)
                infoRow("Parti",       String(format: "%.0f kg", record.totalKg))

                HStack {
                    Text("Durum").foregroundStyle(.secondary)
                    Spacer()
                    Label(record.isSuccess ? "Başarılı" : "Hatalı",
                          systemImage: record.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(record.isSuccess ? .green : .red)
                }
                if !record.serverMessage.isEmpty {
                    Text(record.serverMessage)
                        .font(.caption)
                        .foregroundStyle(record.isSuccess ? .green : .secondary)
                }
            }

            Section {
                if ingredients.isEmpty {
                    Text("İçerik kaydedilmemiş (eski kayıt).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { i, snap in
                        HStack(spacing: 12) {
                            Text("\(i + 1)")
                                .font(.caption2.bold()).foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.name).font(.subheadline)
                                Text("[\(snap.code)]").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.2f kg", snap.amountKg))
                                    .font(.subheadline.bold()).foregroundStyle(.orange)
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
