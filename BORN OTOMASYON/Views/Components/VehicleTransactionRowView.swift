import SwiftUI

struct VehicleTransactionRowView: View {
    let transaction: VehicleListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(transaction.vehicleCode)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(formatted(transaction.net) + " kg")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            HStack(spacing: 16) {
                label("Brüt", value: formatted(transaction.gross))
                label("Dara", value: formatted(transaction.tare))
            }
            .font(.caption).foregroundColor(.secondary)

            HStack {
                Text(formattedDate(transaction.entryDate))
                    .font(.caption2).foregroundColor(.secondary)
                if let no = transaction.waybillNo {
                    Spacer()
                    Text("İrsaliye: \(no)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatted(_ v: Double) -> String { v.decimalString }

    private func formattedDate(_ d: Date) -> String { d.trLong }

    private func label(_ title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title + ":"); Text(value).fontWeight(.medium)
        }
    }
}
