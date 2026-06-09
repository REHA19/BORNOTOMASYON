import SwiftData
import Foundation

// MARK: - Fiyat listesi ürün fiyat snapshot'ı (karşılaştırma raporu için)

struct PriceSnap: Codable, Identifiable, Hashable {
    var id = UUID()
    var code: String
    var name: String
    var pesin: Double   // ₺/çuval peşin fiyat
}

@Model final class PriceListArchive {
    var brand:    String = "Alapala"
    var period:   String = ""
    var savedAt:  Date   = Date()
    var fileName: String = ""
    var revision: String = ""        // Kullanıcının girdiği revizyon (örn: "2026-06")
    var isPublished: Bool = false     // Yayınla'ya basıldıysa piyasaya sunulmuş resmi liste
    var pricesJSON: String = "[]"     // PriceSnap dizisi — karşılaştırma raporu için

    init(brand: String, period: String, fileName: String,
         revision: String = "", isPublished: Bool = false, prices: [PriceSnap] = []) {
        self.brand       = brand
        self.period      = period
        self.fileName    = fileName
        self.revision    = revision
        self.isPublished = isPublished
        self.savedAt     = Date()
        self.prices      = prices
    }

    var prices: [PriceSnap] {
        get {
            guard let data = pricesJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([PriceSnap].self, from: data)) ?? []
        }
        set {
            pricesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }

    var fileURL: URL? {
        guard !fileName.isEmpty else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(fileName)
    }

    var displayDate: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "tr_TR")
        df.dateFormat = "dd MMMM yyyy, HH:mm"
        return df.string(from: savedAt)
    }

    var fileExists: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
