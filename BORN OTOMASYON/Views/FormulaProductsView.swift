import SwiftUI

struct FormulaProductsView: View {
    let group: RasyonGroup

    var body: some View {
        List {
            // Özet bilgi
            Section {
                infoRow("Rasyon Adı", value: group.customName)
                infoRow("Tarih",      value: fmtDate(group.latestDate))
                infoRow("Ürün Sayısı", value: "\(group.productCount) ürün")
            } header: { Text("Rasyon Bilgisi") }

            // Ürün listesi
            Section {
                ForEach(group.formulas.sorted { $0.materialName < $1.materialName },
                        id: \.formulaID) { formula in
                    NavigationLink(destination: FormulaDetailView(
                        formulaID:    formula.formulaID,
                        productCode:  formula.materialCode,
                        fallbackCode: formula.customName ?? "",
                        displayName:  formula.materialName
                    )) {
                        ProductRowView(formula: formula)
                    }
                }
            } header: {
                Text("Ürünler (\(group.productCount) kalem)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.customName)
        .navigationBarTitleDisplayMode(.large)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    private func fmtDate(_ date: Date) -> String {
        date == .distantPast ? "—" : date.trLong
    }
}

// MARK: - Ürün satırı

private struct ProductRowView: View {
    let formula: FormulaActiveResponse

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formula.materialName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(formula.materialCode)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtKg(formula.totalAmount))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.caption2)
                    Text("\(formula.details.count) hammadde")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func fmtKg(_ v: Double) -> String { v.kgString }
}
