import SwiftUI

struct StokMaliyetiForecastView: View {
    let materials:  [Material]
    let dailyRates: [String: Double]
    let priceMap:   [String: Double]   // materialCode → ₺/ton

    @Environment(\.dismiss) private var dismiss

    private struct ForecastRow: Identifiable {
        let id       = UUID()
        let code:    String
        let name:    String
        let stockKg: Double
        let dailyKg: Double
        let need30:  Double
        let defKg:   Double
        let costTL:  Double
    }

    private var rows: [ForecastRow] {
        materials.compactMap { mat in
            let daily = dailyRates[mat.materialCode] ?? 0
            guard daily > 0 else { return nil }
            let need  = daily * 30
            let def   = max(0, need - mat.netStock)
            // priceMap ₺/ton → eksik kg × (₺/ton ÷ 1000) = ₺
            let price = priceMap[mat.materialCode] ?? 0
            return ForecastRow(
                code:    mat.materialCode,
                name:    mat.materialName,
                stockKg: mat.netStock,
                dailyKg: daily,
                need30:  need,
                defKg:   def,
                costTL:  def * price / 1000
            )
        }
        .sorted { $0.costTL > $1.costTL }
    }

    private var totalBudget: Double { rows.reduce(0) { $0 + $1.costTL } }

    var body: some View {
        NavigationStack {
            List {
                // Özet bant
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("30 Günlük Tahmini Tedarik Bütçesi")
                                .font(.subheadline.bold())
                            Text("Eksik hammaddelerin tahmini alım maliyeti")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(totalBudget.tlString)
                            .font(.title3.bold())
                            .foregroundStyle(totalBudget > 0 ? .orange : .green)
                    }
                    .padding(.vertical, 6)
                }

                // Satın alma gereken hammaddeler
                let deficit = rows.filter { $0.defKg > 0 }
                if !deficit.isEmpty {
                    Section("Eksik — Alım Gerekiyor (\(deficit.count))") {
                        ForEach(deficit) { row in
                            forecastCell(row)
                        }
                    }
                }

                // Yeterli stok
                let sufficient = rows.filter { $0.defKg == 0 }
                if !sufficient.isEmpty {
                    Section("Yeterli Stok (\(sufficient.count))") {
                        ForEach(sufficient) { row in
                            forecastCell(row)
                        }
                    }
                }

                // Tüketim verisi olmayan hammaddeler
                let noData = materials.filter { mat in
                    (dailyRates[mat.materialCode] ?? 0) == 0
                }
                if !noData.isEmpty {
                    Section("Tüketim Verisi Yok (\(noData.count))") {
                        ForEach(noData) { mat in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mat.materialName)
                                        .font(.subheadline)
                                    Text("Stok: \(mat.netStock.kgString)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Veri yok")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("30 Günlük Rapor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func forecastCell(_ row: ForecastRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                if row.defKg > 0 {
                    Text(row.costTL.tlString)
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            HStack(spacing: 12) {
                label("Stok", value: row.stockKg.kgString)
                label("Günlük", value: String(format: "%.0f kg", row.dailyKg))
                label("30g İhtiyaç", value: String(format: "%.0f kg", row.need30))
                if row.defKg > 0 {
                    label("Eksik", value: String(format: "%.0f kg", row.defKg))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func label(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }
}
