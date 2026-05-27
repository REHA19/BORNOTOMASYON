import Foundation

// MARK: - ConsumptionGroupModel
// POST /api/ConsumptionGroup yanıt modeli

struct ConsumptionGroupModel: Identifiable, Decodable {
    let code:        String
    let name:        String
    let formulaName: String?
    let formulaID:   Int?
    let planAmount:  Double
    let realAmount:  Double
    let diff:        Double

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code        = "Code"
        case name        = "Name"
        case formulaName = "FormulaName"
        case formulaID   = "FormulaID"
        case planAmount  = "PlanAmount"
        case realAmount  = "RealAmount"
        case diff        = "Diff"
    }
}

// MARK: - ConsumptionGroupFilter
// POST /api/ConsumptionGroup istek gövdesi

struct ConsumptionGroupFilter: Encodable {
    var date1:        Date
    var date2:        Date
    var materialType: Int   // 1 = Hammadde, 2 = Yem

    enum CodingKeys: String, CodingKey {
        case date1        = "Date1"
        case date2        = "Date2"
        case materialType = "MaterialType"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        try c.encode(iso.string(from: date1), forKey: .date1)
        try c.encode(iso.string(from: date2), forKey: .date2)
        try c.encode(materialType,             forKey: .materialType)
    }
}

// MARK: - ConsumptionGroupResponse (sarmalı yanıt)

struct ConsumptionGroupResponse: Decodable {
    let data:    [ConsumptionGroupModel]
    let message: String?
    let success: Bool

    enum CodingKeys: String, CodingKey {
        case data    = "Data"
        case message = "Message"
        case success = "Success"
    }
}
