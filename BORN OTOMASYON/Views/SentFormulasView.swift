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
                if record.costPerTon > 0 {
                    Text(String(format: "%.0f ₺/ton", record.costPerTon))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                }
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

    @Query(sort: \SendRecord.sentAt, order: .reverse) private var allRecords: [SendRecord]

    // Aynı formülün bu gönderiyle hemen önceki gönderisi
    private var previousRecord: SendRecord? {
        allRecords.first { $0.formulaCode == record.formulaCode && $0.sentAt < record.sentAt }
    }

    struct IngChange: Identifiable {
        let id   = UUID()
        let code:        String
        let name:        String
        let currentPct:  Double
        let previousPct: Double
        var delta:  Double { currentPct - previousPct }
        var isNew:  Bool   { previousPct < 0.01 && currentPct  > 0.01 }
        var isGone: Bool   { currentPct  < 0.01 && previousPct > 0.01 }
    }

    private var ingredientChanges: [IngChange] {
        guard let prev = previousRecord, !prev.snapshotIngredients.isEmpty else { return [] }
        let prevMap = Dictionary(uniqueKeysWithValues:
            prev.snapshotIngredients.map { ($0.code, $0.mixPct) })
        let currMap = Dictionary(uniqueKeysWithValues:
            record.snapshotIngredients.map { ($0.code, $0.mixPct) })

        var changes: [IngChange] = []

        for snap in record.snapshotIngredients {
            let prevPct = prevMap[snap.code] ?? 0
            if abs(snap.mixPct - prevPct) > 0.09 || (prevPct < 0.01 && snap.mixPct > 0.01) {
                changes.append(IngChange(code: snap.code, name: snap.name,
                                         currentPct: snap.mixPct, previousPct: prevPct))
            }
        }
        for prevSnap in prev.snapshotIngredients where (currMap[prevSnap.code] ?? 0) < 0.01 && prevSnap.mixPct > 0.01 {
            changes.append(IngChange(code: prevSnap.code, name: prevSnap.name,
                                     currentPct: 0, previousPct: prevSnap.mixPct))
        }
        return changes.sorted { abs($0.delta) > abs($1.delta) }
    }

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

            // ── Maliyet ──────────────────────────────────────────────────────
            if record.costPerTon > 0 {
                Section("Maliyet") {
                    HStack {
                        Label("Ton Başı Maliyet", systemImage: "turkishlirasign.circle.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f ₺/ton", record.costPerTon))
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                    }
                    if record.totalKg > 0 {
                        HStack {
                            Text("Toplam Parti Maliyeti").foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0f ₺", record.costPerTon * record.totalKg / 1000))
                                .font(.subheadline.bold()).foregroundStyle(.orange)
                        }
                    }
                }
            }

            // ── Besin Değerleri ───────────────────────────────────────────────
            let nutrients = record.snapshotNutrients
            if !nutrients.isEmpty {
                Section {
                    ForEach(nutrients, id: \.id) { nut in
                        SentNutrientRow(nut: nut)
                    }
                } header: {
                    HStack {
                        Text("Besin Değerleri (\(nutrients.count))")
                        Spacer()
                        Text("Min–Max aralığı dışındakiler turuncu")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            // ── Hammadde Değişimi (önceki gönderimle kıyaslama) ──────────────
            let changes = ingredientChanges
            if !changes.isEmpty {
                Section {
                    ForEach(changes, id: \.id) { ch in
                        IngChangeRow(change: ch)
                    }
                } header: {
                    HStack {
                        Text("Değişim — Önceki Gönderime Göre")
                        Spacer()
                        Text(previousRecord.map {
                            let fmt = DateFormatter()
                            fmt.locale = Locale(identifier: "tr_TR")
                            fmt.dateFormat = "d MMM HH:mm"
                            return fmt.string(from: $0.sentAt)
                        } ?? "")
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            // ── Hammaddeler ───────────────────────────────────────────────────
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

private struct IngChangeRow: View {
    let change: SentRecordDetailView.IngChange

    var body: some View {
        HStack(spacing: 10) {
            // İkon
            Group {
                if change.isNew {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                } else if change.isGone {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                } else if change.delta > 0 {
                    Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.red)
                }
            }
            .font(.title3)

            // İsim + durum
            VStack(alignment: .leading, spacing: 2) {
                Text(change.name).font(.subheadline)
                if change.isNew {
                    Text("Yeni eklendi").font(.caption2).foregroundStyle(.green)
                } else if change.isGone {
                    Text("Rasyondan çıktı").font(.caption2).foregroundStyle(.red)
                }
            }

            Spacer()

            // Yüzde bilgisi
            VStack(alignment: .trailing, spacing: 2) {
                if change.isNew {
                    Text(String(format: "%.2f%%", change.currentPct))
                        .font(.subheadline.bold().monospacedDigit()).foregroundStyle(.green)
                } else if change.isGone {
                    Text(String(format: "%.2f%%", change.previousPct))
                        .font(.subheadline.bold().monospacedDigit()).foregroundStyle(.red)
                        .strikethrough()
                } else {
                    let color: Color = change.delta > 0 ? .green : .red
                    Text(String(format: "%+.2f%%", change.delta))
                        .font(.subheadline.bold().monospacedDigit()).foregroundStyle(color)
                    HStack(spacing: 3) {
                        Text(String(format: "%.2f", change.previousPct))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(String(format: "%.2f%%", change.currentPct))
                            .foregroundStyle(color)
                    }
                    .font(.caption2.monospacedDigit())
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SentNutrientRow: View {
    let nut: SentNutrientSnap
    var body: some View {
        let inRange = (nut.minValue.map { nut.value >= $0 - 0.001 } ?? true)
                   && (nut.maxValue.map { nut.value <= $0 + 0.001 } ?? true)
        HStack(spacing: 8) {
            Text(nut.displayName).font(.subheadline)
            Spacer()
            Text(String(format: "%.3f %@", nut.value, nut.unit))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(inRange ? Color.primary : Color.orange)
        }
        .padding(.vertical, 1)
    }
}
