import SwiftUI

struct StockReportDetailView: View {
    let summary: MaterialSummary

    var body: some View {
        List {
            Section {
                infoRow("Araç Sayısı",  value: "\(summary.count) sefer")
                infoRow("Toplam Net",   value: weight(summary.totalNet))
                infoRow("Toplam Brüt",  value: weight(summary.totalGross))
                infoRow("Toplam Dara",  value: weight(summary.totalTare))
            } header: { Text("Özet") }

            Section {
                ForEach(summary.transactions) { t in
                    VehicleTransactionRowView(transaction: t)
                }
            } header: {
                Text("Seferler (\(summary.count))")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(summary.materialName)
        .navigationBarTitleDisplayMode(.large)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    private func weight(_ v: Double) -> String { v.kgWholeString }
}
