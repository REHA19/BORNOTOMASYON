import SwiftUI
import SwiftData
import Charts

struct PriceHistoryView: View {
    let ingredientName: String

    @Query private var entries: [PriceHistoryEntry]

    init(ingredientName: String) {
        self.ingredientName = ingredientName
        _entries = Query(
            filter: #Predicate<PriceHistoryEntry> { $0.ingredientName == ingredientName },
            sort:   \PriceHistoryEntry.recordedAt,
            order:  .forward
        )
    }

    private var locale: Locale { Locale(identifier: "tr_TR") }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Fiyat Geçmişi Yok",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Hammadde fiyatı henüz kaydedilmemiş.")
                )
            } else {
                Section("Fiyat Grafiği") {
                    Chart(entries) { e in
                        LineMark(
                            x: .value("Tarih", e.recordedAt),
                            y: .value("₺/ton", e.priceTL)
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Tarih", e.recordedAt),
                            y: .value("₺/ton", e.priceTL)
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(50)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { val in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .frame(height: 220)
                    .padding(.vertical, 8)
                }

                Section("Kayıtlar") {
                    ForEach(entries.reversed()) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(e.priceTL.formatted(.number.locale(locale)) + " ₺/ton")
                                .font(.callout.monospacedDigit().bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fiyat Geçmişi")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Renkli Fiyat Geçmişi Sheet (MultiBlend hammadde swipe için)

struct PriceHistoryColoredSheet: View {
    let ingredient: FeedIngredient

    @Query private var entries: [PriceHistoryEntry]

    init(ingredient: FeedIngredient) {
        self.ingredient = ingredient
        let name = ingredient.name
        _entries = Query(
            filter: #Predicate<PriceHistoryEntry> { $0.ingredientName == name },
            sort:   \PriceHistoryEntry.recordedAt,
            order:  .forward
        )
    }

    // Her ardışık iki nokta arası bir segment
    private struct Segment: Identifiable {
        let id = UUID()
        let fromDate:  Date
        let fromPrice: Double
        let toDate:    Date
        let toPrice:   Double
        var isRising:  Bool { toPrice >= fromPrice }
    }

    private var segments: [Segment] {
        guard entries.count >= 2 else { return [] }
        return zip(entries, entries.dropFirst()).map { a, b in
            Segment(fromDate: a.recordedAt, fromPrice: a.priceTL,
                    toDate:   b.recordedAt, toPrice:   b.priceTL)
        }
    }

    private var locale: Locale { Locale(identifier: "tr_TR") }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Fiyat Geçmişi Yok",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Fiyat alanını güncelledikçe geçmiş buraya eklenir.")
                    )
                } else {
                    // ── Grafik ────────────────────────────────────────────────
                    Section("Fiyat Grafiği") {
                        Chart {
                            // Tek nokta varsa düz çizgi
                            if entries.count == 1, let e = entries.first {
                                PointMark(x: .value("Tarih", e.recordedAt),
                                          y: .value("₺/ton", e.priceTL))
                                    .foregroundStyle(Color.orange)
                            }
                            // Segment başlangıç noktası
                            if let first = entries.first {
                                PointMark(x: .value("Tarih", first.recordedAt),
                                          y: .value("₺/ton", first.priceTL))
                                    .foregroundStyle(Color.gray)
                                    .symbolSize(30)
                            }
                            // Her segment: yükseliş yeşil, düşüş kırmızı
                            ForEach(segments) { seg in
                                LineMark(
                                    x: .value("Tarih", seg.fromDate),
                                    y: .value("₺/ton", seg.fromPrice),
                                    series: .value("seg", seg.id.uuidString)
                                )
                                LineMark(
                                    x: .value("Tarih", seg.toDate),
                                    y: .value("₺/ton", seg.toPrice),
                                    series: .value("seg", seg.id.uuidString)
                                )
                                .foregroundStyle(seg.isRising ? Color.green : Color.red)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))

                                PointMark(x: .value("Tarih", seg.toDate),
                                          y: .value("₺/ton", seg.toPrice))
                                    .foregroundStyle(seg.isRising ? Color.green : Color.red)
                                    .symbolSize(40)
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { val in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .frame(height: 220)
                        .padding(.vertical, 8)
                    }

                    // ── Kayıt Listesi ─────────────────────────────────────────
                    Section("Kayıtlar") {
                        ForEach(entries.reversed()) { e in
                            HStack {
                                Text(e.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                // Renk: önceki kayıttan düşük/yüksek mi?
                                let idx = entries.firstIndex(where: { $0.id == e.id }) ?? 0
                                let prev = idx > 0 ? entries[idx - 1].priceTL : e.priceTL
                                let color: Color = e.priceTL > prev ? .green : e.priceTL < prev ? .red : .orange
                                Text(e.priceTL.formatted(.number.locale(locale)) + " ₺/ton")
                                    .font(.callout.monospacedDigit().bold())
                                    .foregroundStyle(color)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(ingredient.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("Fiyat Geçmişi").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
