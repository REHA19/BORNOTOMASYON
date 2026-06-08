import SwiftData
import Foundation

@Model final class GiderKalemi {
    var name:       String  = ""
    var value:      Double  = 0.0
    var isPercent:  Bool    = false   // false = ₺/ton sabit | true = rasyon × %
    var brand:      String  = "Alapala"
    var orderIndex: Int     = 0

    init(name: String, value: Double, isPercent: Bool,
         brand: String = "Alapala", orderIndex: Int = 0) {
        self.name       = name
        self.value      = value
        self.isPercent  = isPercent
        self.brand      = brand
        self.orderIndex = orderIndex
    }

    // Rasyon maliyetine göre ₺/ton katkısı
    func contribution(rasyon: Double) -> Double {
        isPercent ? rasyon * value / 100 : value
    }

    var unitLabel: String { isPercent ? "%" : "₺/t" }
}
