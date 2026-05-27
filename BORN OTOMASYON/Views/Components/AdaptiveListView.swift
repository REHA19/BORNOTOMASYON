import SwiftUI

// iPhone'da düz liste, iPad/Mac'te 2 sütunlu grid gösterir.
struct AdaptiveListView: View {
    let materials: [Material]
    let searchText: String
    let snapshotDeltas: [Int: Double]
    var stockDays: [String: Double] = [:]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 12)
    ]

    var body: some View {
        if materials.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if horizontalSizeClass == .compact {
            // iPhone: düz liste
            List(materials) { material in
                NavigationLink(destination: MaterialDetailView(material: material)) {
                    MaterialRowView(material: material,
                                   delta: snapshotDeltas[material.id],
                                   days: stockDays[material.materialCode])
                }
            }
            .listStyle(.plain)
        } else {
            // iPad / Mac: grid kart
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(materials) { material in
                        NavigationLink(destination: MaterialDetailView(material: material)) {
                            MaterialCardView(material: material, delta: snapshotDeltas[material.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Kart (iPad/Mac)

struct MaterialCardView: View {
    let material: Material
    let delta: Double?

    private var stockColor: Color {
        switch material.netStock {
        case ..<0:           return .red
        case 0..<1_000:      return .orange
        case 1_000..<50_000: return .yellow
        default:             return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(material.materialCode)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                Circle()
                    .fill(stockColor)
                    .frame(width: 10, height: 10)
            }

            Text(material.materialName)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(2)

            Spacer()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(formattedStock)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(stockColor)
                        Text("kg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let d = delta, abs(d) > 0.05 {
                        DeltaBadge(delta: d)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private var formattedStock: String { material.netStock.decimalString }
}
