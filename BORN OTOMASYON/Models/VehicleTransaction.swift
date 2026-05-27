import Foundation

// MARK: - VehicleListFilter

struct VehicleListFilter: Encodable {
    var date1: Date
    var date2: Date
    var inside: Bool
    var exited: Bool
    var sale: Bool
    var purchase: Bool
    var withoutOrder: Bool
    var withOrder: Bool

    enum CodingKeys: String, CodingKey {
        case date1        = "Date1"
        case date2        = "Date2"
        case inside       = "Inside"
        case exited       = "Exited"
        case sale         = "Sale"
        case purchase     = "Purchase"
        case withoutOrder = "WithoutOrder"
        case withOrder    = "WithOrder"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        try c.encode(iso.string(from: date1), forKey: .date1)
        try c.encode(iso.string(from: date2), forKey: .date2)
        try c.encode(inside,       forKey: .inside)
        try c.encode(exited,       forKey: .exited)
        try c.encode(sale,         forKey: .sale)
        try c.encode(purchase,     forKey: .purchase)
        try c.encode(withoutOrder, forKey: .withoutOrder)
        try c.encode(withOrder,    forKey: .withOrder)
    }
}

// MARK: - VehicleListModel

struct VehicleListModel: Identifiable, Decodable {
    let id: Int
    let vehicleCode: String
    let recordType: Int
    let gross: Double
    let tare: Double
    let net: Double
    let entryDate: Date
    let exitDate: Date?
    let waybillAmount: Double?
    let waybillNo: String?
    let waybillDate: Date?
    let orderCount: Int
    let orderAmount: Double
    let materialName: String?

    enum CodingKeys: String, CodingKey {
        case id            = "ID"
        case vehicleCode   = "VehicleCode"
        case recordType    = "RecordType"
        case gross         = "Gross"
        case tare          = "Tare"
        case net           = "Net"
        case entryDate     = "EntryDate"
        case exitDate      = "ExitDate"
        case waybillAmount = "WaybillAmount"
        case waybillNo     = "WaybillNo"
        case waybillDate   = "WaybillDate"
        case orderCount    = "OrderCount"
        case orderAmount   = "OrderAmount"
        case materialName  = "MaterialName"
    }
}

// MARK: - VehicleTransactionResponse

struct VehicleTransactionResponse: Decodable {
    let data: [VehicleListModel]
    let message: String?
    let success: Bool

    enum CodingKeys: String, CodingKey {
        case data    = "Data"
        case message = "Message"
        case success = "Success"
    }
}
