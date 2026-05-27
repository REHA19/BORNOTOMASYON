import Foundation

// MARK: - StockRequest
// POST /api/FactoryNetStockOut için istek gövdesi.
// Tüm alanlar opsiyoneldir; nil gönderilenleri encode etme.

struct StockRequest: Encodable {
    /// Sarfiyat hesabı için kısayol: sadece bitiş tarihi gönder
    init(endDate: Date) {
        self.endDate = endDate
    }

    init() {}
    /// Belirli malzeme kodlarına göre filtrele. nil = tümü
    var materialCodes: [String]?
    /// Stok geçerlilik başlangıç tarihi (ISO8601)
    var startDate: Date?
    /// Stok geçerlilik bitiş tarihi (ISO8601)
    var endDate: Date?
    /// Depo kodu. nil = tüm depolar
    var warehouseCode: String?

    enum CodingKeys: String, CodingKey {
        case materialCodes  = "MaterialCodes"
        case startDate      = "StartDate"
        case endDate        = "EndDate"
        case warehouseCode  = "WarehouseCode"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(materialCodes,  forKey: .materialCodes)
        try container.encodeIfPresent(warehouseCode,  forKey: .warehouseCode)

        let iso = ISO8601DateFormatter()
        if let start = startDate {
            try container.encode(iso.string(from: start), forKey: .startDate)
        }
        if let end = endDate {
            try container.encode(iso.string(from: end), forKey: .endDate)
        }
    }
}
