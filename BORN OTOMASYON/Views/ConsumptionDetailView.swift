import SwiftUI

struct ConsumptionDetailView: View {
    let item: ConsumptionGroupModel
    let date1: Date
    let date2: Date

    var body: some View {
        List {
            // Özet
            Section {
                if let formula = item.formulaName, !formula.isEmpty {
                    NavigationLink(destination: FormulaDetailView(
                        formulaID:    item.formulaID,
                        productCode:  item.code,
                        fallbackCode: formula,
                        displayName:  formula
                    )) {
                        HStack {
                            Text("Formül").foregroundColor(.secondary)
                            Spacer()
                            Text(formula).fontWeight(.medium)
                        }
                    }
                } else {
                    infoRow("Formül", value: "—")
                }
                infoRow("Plan",         value: fmt(item.planAmount))
                infoRow("Gerçek",       value: fmt(item.realAmount))
                infoRow("Fark",         value: (item.diff > 0 ? "+" : "") + fmt(item.diff),
                         color: item.diff > 0 ? .red : item.diff < 0 ? .orange : .green)
            } header: { Text("Tüketim Özeti") }

            // Tarih aralığı
            Section {
                infoRow("Başlangıç", value: fmtDate(date1))
                infoRow("Bitiş",     value: fmtDate(date2))
            } header: { Text("Tarih Aralığı") }

            // Durum
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: statusIcon)
                            .font(.largeTitle)
                            .foregroundColor(statusColor)
                        Text(statusText)
                            .font(.headline)
                            .foregroundColor(statusColor)
                        Text(statusDetail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } header: { Text("Durum") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Status

    private var statusIcon: String {
        if item.diff > 0 { return "arrow.up.circle.fill" }
        if item.diff < 0 { return "arrow.down.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if item.diff > 0 { return .red }
        if item.diff < 0 { return .orange }
        return .green
    }

    private var statusText: String {
        if item.diff > 0 { return "Fazla Tüketim" }
        if item.diff < 0 { return "Eksik Tüketim" }
        return "Plana Uygun"
    }

    private var statusDetail: String {
        if item.diff > 0 {
            return "Plandan \(fmt(item.diff)) fazla tüketildi"
        }
        if item.diff < 0 {
            return "Plandan \(fmt(abs(item.diff))) eksik tüketildi"
        }
        return "Tüketim plana tam uyuyor"
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).foregroundColor(color)
        }
    }

    private func fmt(_ value: Double) -> String { value.kgString }

    private func fmtDate(_ date: Date) -> String { date.trLong }
}
