import Foundation

struct Material: Identifiable, Codable {
    let id: Int
    let materialCode: String
    let materialName: String
    let netStock: Double
    let effective: Date

    enum CodingKeys: String, CodingKey {
        case id = "MaterialID"
        case materialCode = "MaterialCode"
        case materialName = "MaterialName"
        case netStock = "NetStock"
        case effective = "Effective"
    }
}

struct StockResponse: Codable {
    let data: [Material]
    let message: String?
    let success: Bool

    enum CodingKeys: String, CodingKey {
        case data = "Data"
        case message = "Message"
        case success = "Success"
    }
}
