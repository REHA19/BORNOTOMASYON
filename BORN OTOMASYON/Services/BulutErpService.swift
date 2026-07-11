import Foundation

// MARK: - GET /Rasyonlar/Kaydet istek modeli

struct BulutErpRasyonPayload: Sendable {
    struct Item: Sendable {
        var code:      String
        var name:      String
        var costPerKg: Double
        var amountKg:  Double
    }
    var rasyonNo:         String   // Versiyon alanının değeri
    var rasyonTarih:      Date     // gönderim anı
    var productCode:      String
    var productName:      String
    var productCostPerKg: Double
    var items:            [Item]
}

struct BulutErpResponse: Sendable {
    let statusCode: Int
    let message:    String
}

// Sunucu HTTP 200 ile birlikte "success": false de dönebiliyor —
// bu durumda gövdeyi ayrıştırıp gerçek başarı durumunu tespit etmek gerekiyor.
private struct BulutErpApiResult: Decodable {
    let success: Bool?
    let message: String?
}

struct BulutErpService {
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    func send(payload: BulutErpRasyonPayload) async throws -> BulutErpResponse {
        var comps = URLComponents(string: AppConfig.BulutErp.baseURL + AppConfig.BulutErp.endpoint)!
        comps.queryItems = [
            URLQueryItem(name: "rasyonno",    value: payload.rasyonNo),
            URLQueryItem(name: "rasyontarih", value: Self.dateFmt.string(from: payload.rasyonTarih)),
            URLQueryItem(name: "productcode", value: payload.productCode),
            URLQueryItem(name: "product",     value: payload.productName),
            URLQueryItem(name: "productcost", value: String(format: "%.2f", payload.productCostPerKg)),
            URLQueryItem(name: "hmcodes",     value: payload.items.map(\.code).joined(separator: ",")),
            URLQueryItem(name: "hmnames",     value: payload.items.map(\.name).joined(separator: ",")),
            URLQueryItem(name: "hmcosts",     value: payload.items.map { String(format: "%.2f", $0.costPerKg) }.joined(separator: ",")),
            URLQueryItem(name: "hmamounts",   value: payload.items.map { String(format: "%.2f", $0.amountKg) }.joined(separator: ",")),
            URLQueryItem(name: "uuid",        value: AppConfig.BulutErp.uuid),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: AppConfig.Timeout.request)
        request.httpMethod = "GET"

        print("[BulutErp] GET \(url)")

        let (data, response) = try await URLSession.shared.data(for: request)
        let raw = String(data: data, encoding: .utf8) ?? ""

        print("[BulutErp] raw: \(raw.prefix(400))")

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "BulutErp", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Sunucudan yanıt alınamadı."])
        }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "BulutErp", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Bulut ERP hata (\(http.statusCode)): \(raw.prefix(400))"])
        }

        // Sunucu 200 ile birlikte gövdede "success": false döndürebiliyor —
        // bunu da hata olarak ele al, aksi halde arayüzde yanlışlıkla ✓ görünür.
        if let data2 = raw.data(using: .utf8),
           let apiResult = try? JSONDecoder().decode(BulutErpApiResult.self, from: data2),
           apiResult.success == false {
            let msg = apiResult.message ?? "Bulut ERP isteği reddetti."
            throw NSError(domain: "BulutErp", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return BulutErpResponse(statusCode: http.statusCode, message: raw)
    }
}
