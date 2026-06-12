import Foundation

// MARK: - Hammadde anlık görüntüsü (JSON'a serileştirilir)

struct HammaddeSnapshot: Codable, Identifiable {
    var id:       String { code }
    var code:     String
    var name:     String
    var stockKg:  Double
    var priceTL:  Double?   // ₺/ton
    var totalTL:  Double    // stockKg × priceTL / 1000
}

// MARK: - Manuel kalem anlık görüntüsü

struct ManuelKalemSnapshot: Codable, Identifiable {
    var id:        UUID    = UUID()
    var name:      String
    var category:  String
    var quantity:  Double
    var unit:      String
    var unitPrice: Double
    var currency:  String  // "TL", "USD", "EUR"
    var totalTL:   Double  // kur dönüşümlü
}

// MARK: - Tam rapor anlık görüntüsü

struct StokRaporSnapshot: Codable {
    var hammaddeler:    [HammaddeSnapshot]
    var manuelKalemler: [ManuelKalemSnapshot]
    var hammaddeToplam: Double
    var manuelToplam:   Double
    var grandTotal:     Double
    var usdRate:        Double
    var eurRate:        Double
    var olusturmaTarihi: Date

    // JSON yardımcıları
    func toJSON() -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return (try? String(data: enc.encode(self), encoding: .utf8)) ?? "{}"
    }

    static func from(json: String) -> StokRaporSnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(StokRaporSnapshot.self, from: data)
    }
}
