import SwiftUI

struct MaterialRowView: View {
    let material: Material
    let delta: Double?
    var days: Double? = nil

    private var stockColor: Color {
        switch material.netStock {
        case ..<0:           return .red
        case 0..<1_000:      return .orange
        case 1_000..<50_000: return .yellow
        default:             return .green
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(stockColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(material.materialName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(material.materialCode)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedStock + " kg")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if let d = delta, abs(d) > 0.05 {
                    DeltaBadge(delta: d)
                }
                if let d = days {
                    DaysBadge(days: d)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedStock: String { material.netStock.decimalString }
}

// MARK: - Days Badge

struct DaysBadge: View {
    let days: Double

    private var color: Color {
        switch days {
        case ..<7:   return .red
        case 7..<15: return .orange
        case 15..<30: return .yellow
        default:     return .green
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8, weight: .bold))
            Text("\(Int(days.rounded())) gün")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Delta Badge

struct DeltaBadge: View {
    let delta: Double

    private var isConsumed: Bool { delta > 0 }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isConsumed ? "arrow.down" : "arrow.up")
                .font(.system(size: 9, weight: .bold))
            Text(formatted)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(isConsumed ? .red : .green)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isConsumed ? Color.red : Color.green).opacity(0.12))
        .clipShape(Capsule())
    }

    private var formatted: String { Swift.abs(delta).kgWholeString }
}
