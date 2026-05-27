import SwiftData
import Foundation

@Model
final class PriceHistoryEntry {
    var ingredientName: String = ""
    var priceTL: Double        = 0
    var recordedAt: Date       = Date()

    init(ingredientName: String, priceTL: Double) {
        self.ingredientName = ingredientName
        self.priceTL        = priceTL
        self.recordedAt     = Date()
    }
}
