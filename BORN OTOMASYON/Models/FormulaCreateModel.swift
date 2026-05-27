import Foundation

// MARK: - POST /api/CreateNewFormulaFromApp istek modeli

struct FormulaCreateAppModel: Encodable {
    var productCode:    String
    var productName:    String
    var customName:     String
    var customVersion:  String
    var validDate:      Date?
    var totalAmount:    Double
    var comment:        String
    var details:        [FormulaCreateDetailAppModel]
    var activate:       Bool

    enum CodingKeys: String, CodingKey {
        case productCode   = "ProductCode"
        case productName   = "ProductName"
        case customName    = "CustomName"
        case customVersion = "CustomVersion"
        case validDate     = "ValidDate"
        case totalAmount   = "TotalAmount"
        case comment       = "Comment"
        case details       = "Details"
        case activate      = "Activate"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(productCode,   forKey: .productCode)
        try c.encode(productName,   forKey: .productName)
        try c.encode(customName,    forKey: .customName)
        try c.encode(customVersion, forKey: .customVersion)
        if let date = validDate {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            try c.encode(iso.string(from: date), forKey: .validDate)
        } else {
            try c.encodeNil(forKey: .validDate)
        }
        try c.encode(totalAmount,   forKey: .totalAmount)
        try c.encode(comment,       forKey: .comment)
        try c.encode(details,       forKey: .details)
        try c.encode(activate,      forKey: .activate)
    }
}

struct FormulaCreateDetailAppModel: Encodable, Identifiable {
    var id            = UUID()
    var materialCode:  String
    var materialName:  String
    var rowNo:         Int
    var amount:        Double
    var isAdditive:    Bool

    enum CodingKeys: String, CodingKey {
        case materialCode = "MaterialCode"
        case materialName = "MaterialName"
        case rowNo        = "RowNo"
        case amount       = "Amount"
        case isAdditive   = "IsAdditive"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(materialCode, forKey: .materialCode)
        try c.encode(materialName, forKey: .materialName)
        try c.encode(rowNo,        forKey: .rowNo)
        try c.encode(amount,       forKey: .amount)
        try c.encode(isAdditive,   forKey: .isAdditive)
    }
}

// MARK: - Yanıt

struct FormulaCreateResponse: Decodable {
    let success: Bool
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case message = "Message"
    }
}
