import Foundation

struct ConsumptionItem: Identifiable {
    let id: Int
    let materialCode: String
    let materialName: String
    let openingStock: Double   // Başlangıç stoku
    let closingStock: Double   // Bitiş stoku
    var consumption: Double { openingStock - closingStock }

    var status: ConsumptionStatus {
        if consumption > 0 { return .consumed }
        if consumption < 0 { return .replenished }
        return .unchanged
    }

    enum ConsumptionStatus {
        case consumed, replenished, unchanged

        var label: String {
            switch self {
            case .consumed:    return "Sarfiyat"
            case .replenished: return "Takviye"
            case .unchanged:   return "Değişmedi"
            }
        }
    }
}
