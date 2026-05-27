import Foundation
import Combine
import SwiftUI

final class MaterialDetailViewModel: ObservableObject {

    let material: Material

    // MARK: - Computed

    var formattedStock: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: material.netStock)) ?? "\(material.netStock)"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: material.effective)
    }

    var stockStatus: StockStatus {
        switch material.netStock {
        case ..<0:        return .negative
        case 0..<1_000:   return .low
        case 1_000..<50_000: return .medium
        default:          return .high
        }
    }

    // MARK: - Stock Status

    enum StockStatus {
        case negative, low, medium, high

        var label: String {
            switch self {
            case .negative: return "Negatif Stok"
            case .low:      return "Düşük Stok"
            case .medium:   return "Normal"
            case .high:     return "Yüksek Stok"
            }
        }

        var color: Color {
            switch self {
            case .negative: return .red
            case .low:      return .orange
            case .medium:   return .yellow
            case .high:     return .green
            }
        }
    }

    // MARK: - Init

    init(material: Material) {
        self.material = material
    }
}
