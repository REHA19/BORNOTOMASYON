import Foundation

// MARK: - Uygulamada gösterilen birleşik model

struct FormulaDetailItem: Identifiable {
    let materialCode: String
    let materialName: String
    let amount:       Double
    let percentage:   Double?
    let isAdditive:   Bool
    let rowNo:        Int

    var id: String { "\(rowNo)-\(materialCode)" }
}

// MARK: - GET /api/GetActiveFormulaOfProduct/{productCode} yanıtı

struct FormulaActiveResponse: Codable {
    let formulaID:    Int
    let materialCode: String
    let materialName: String
    let totalAmount:  Double
    let customName:   String?
    let customVersion:String?
    let validDate:    String?
    let updateDate:   String?   // "2026-04-27T16:38:58.958..." → ay filtresi için kullanılır
    let createDate:   String?
    let details:      [FormulaDetailAPIItem]

    enum CodingKeys: String, CodingKey {
        case formulaID    = "FormulaID"
        case materialCode = "MaterialCode"
        case materialName = "MaterialName"
        case totalAmount  = "TotalAmount"
        case customName   = "CustomName"
        case customVersion = "CustomVersion"
        case validDate    = "ValidDate"
        case updateDate   = "UpdateDate"
        case createDate   = "CreateDate"
        case details      = "Details"
    }
}

struct FormulaDetailAPIItem: Codable {
    let formulaDetailID: Int
    let materialID:      Int
    let rowNo:           Int
    let amount:          Double
    let isAdditive:      Bool

    enum CodingKeys: String, CodingKey {
        case formulaDetailID = "FormulaDetailID"
        case materialID      = "MaterialID"
        case rowNo           = "RowNo"
        case amount          = "Amount"
        case isAdditive      = "IsAdditive"
    }
}

extension FormulaActiveResponse {
    /// Sırasıyla dener: validDate → customName'deki ddMMyyyy bloğu → updateDate → createDate
    var effectiveDate: Date? {
        // 1) ValidDate
        if let d = validDate?.isoDate { return d }
        // 2) CustomName içindeki tarih: "rasyon16042026" → 16.04.2026
        if let name = customName {
            let digits = name.filter(\.isNumber)
            if digits.count >= 8 {
                let fmt = DateFormatter()
                fmt.locale     = Locale(identifier: "en_US_POSIX")
                fmt.dateFormat = "ddMMyyyy"
                if let d = fmt.date(from: String(digits.prefix(8))) { return d }
            }
        }
        // 3) UpdateDate (API her zaman dolu gönderir: "2026-04-27T16:38:58.958...")
        if let d = updateDate?.isoDate { return d }
        // 4) CreateDate
        return createDate?.isoDate
    }
}

struct FormulaActiveWrapper: Decodable {
    let data:    FormulaActiveResponse?
    let success: Bool?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case data    = "Data"
        case success = "Success"
        case message = "Message"
    }
}
