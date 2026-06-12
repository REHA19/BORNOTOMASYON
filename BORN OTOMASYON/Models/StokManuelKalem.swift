import SwiftData
import Foundation

@Model final class StokManuelKalem {
    var name:       String  = ""
    var category:   String  = ""
    var quantity:   Double  = 0
    var unit:       String  = "adet"
    var unitPrice:  Double  = 0
    var currency:   String  = "TL"     // "TL", "USD", "EUR"
    var note:       String  = ""
    var orderIndex: Int     = 0
    var isArchived: Bool    = false

    init(name: String, category: String = "", quantity: Double = 0,
         unit: String = "adet", unitPrice: Double = 0, currency: String = "TL",
         note: String = "", orderIndex: Int = 0) {
        self.name       = name
        self.category   = category
        self.quantity   = quantity
        self.unit       = unit
        self.unitPrice  = unitPrice
        self.currency   = currency
        self.note       = note
        self.orderIndex = orderIndex
    }

    // Kur bağımsız hesaplama (sadece TL kalemler için kullanılabilir)
    var totalTLDirect: Double { quantity * unitPrice }

    // Kur dönüşümlü toplam
    func totalTL(usdRate: Double, eurRate: Double) -> Double {
        switch currency {
        case "USD": return quantity * unitPrice * usdRate
        case "EUR": return quantity * unitPrice * eurRate
        default:    return quantity * unitPrice
        }
    }
}
