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
