import SwiftData
import Foundation

// MARK: - Fiyat listesi ürün fiyat snapshot'ı (karşılaştırma raporu için)

struct PriceSnap: Codable, Identifiable, Hashable {
    var id = UUID()
    var code: String
    var name: String
    var pesin: Double   // ₺/çuval peşin fiyat
    /// Listenin yayınlandığı andaki rasyon (hammadde) maliyeti ₺/ton.
    /// Eski kayıtlarda yok → 0. Sıfırsa "veri yok" olarak ele alınmalıdır.
    var rasyon: Double = 0

    private enum CodingKeys: String, CodingKey { case id, code, name, pesin, rasyon }

    init(id: UUID = UUID(), code: String, name: String, pesin: Double, rasyon: Double = 0) {
        self.id = id; self.code = code; self.name = name
        self.pesin = pesin; self.rasyon = rasyon
    }

    init(from decoder: any Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decodeIfPresent(UUID.self,   forKey: .id)     ?? UUID()
        code   = try c.decode(String.self,          forKey: .code)
        name   = try c.decode(String.self,          forKey: .name)
        pesin  = try c.decode(Double.self,          forKey: .pesin)
        // Bu alan sonradan eklendi — eski arşivlerde bulunmaz
        rasyon = try c.decodeIfPresent(Double.self, forKey: .rasyon) ?? 0
    }
}

// MARK: - Güncel fiyat snapshot'ı üretimi
//
// PDF'teki peşin fiyatla birebir aynı hesap. Hem "Yayınla" arşivi hem de
// yayın öncesi canlı karşılaştırma buradan beslenir — iki yerde ayrı hesap
// yapılmadığı için fark raporu ile PDF asla çelişmez.

enum PriceSnapBuilder {
    static func build(
        rows:         [(formula: BlendFormula, meta: ProductPricingMeta?)],
        ipCuval:      Double, firePct: Double,
        elektrik:     Double, nakliye: Double, iscilik: Double,
        globalKarPct: Double,
        extraItems:   [(value: Double, isPercent: Bool)] = []
    ) -> [PriceSnap] {
        rows.filter { $0.meta?.isVisible ?? true }.map { row in
            let rasyon = row.formula.currentCostTL > 0 ? row.formula.currentCostTL
                                                       : row.formula.recordedCostTL
            let effKar = (row.meta?.overrideKarPct ?? -1) >= 0 ? row.meta!.overrideKarPct
                                                               : globalKarPct
            let bagKg  = row.meta?.bagKg ?? 50
            let calc   = PricingCalc.calculate(
                rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                karPct: effKar, bagKg: bagKg, extraItems: extraItems
            )
            let manual = row.meta?.manualPesin ?? -1
            let pesin  = manual >= 0 ? manual : calc.pesin
            return PriceSnap(code: row.formula.code, name: row.formula.name,
                             pesin: pesin, rasyon: rasyon)
        }
    }
}

@Model final class PriceListArchive {
    var brand:    String = "Alapala"
    var period:   String = ""
    var savedAt:  Date   = Date()
    var fileName: String = ""
    var revision: String = ""        // Kullanıcının girdiği revizyon (örn: "2026-06")
    var isPublished: Bool = false     // Yayınla'ya basıldıysa piyasaya sunulmuş resmi liste
    var pricesJSON: String = "[]"     // PriceSnap dizisi — karşılaştırma raporu için
    // PDF içeriği kaydın kendisinde saklanır → CloudKit ile senkronize olur, cihaz
    // değişse veya uygulama silinip kurulsa bile kaybolmaz.
    @Attribute(.externalStorage) var pdfData: Data? = nil

    init(brand: String, period: String, fileName: String,
         revision: String = "", isPublished: Bool = false, prices: [PriceSnap] = [],
         pdfData: Data? = nil) {
        self.brand       = brand
        self.period      = period
        self.fileName    = fileName
        self.revision    = revision
        self.isPublished = isPublished
        self.savedAt     = Date()
        self.prices      = prices
        self.pdfData     = pdfData
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

    /// PDF açılabilir mi — diskte varsa ya da kayıtta gömülü veri varsa.
    var hasPDF: Bool { fileExists || (pdfData?.isEmpty == false) }

    /// Açmak/paylaşmak için kullanılabilir bir dosya URL'i döndürür.
    /// Disk kopyası yoksa gömülü `pdfData`'dan geçici dosya üretir; hiçbiri yoksa nil.
    func resolvedPDFURL() -> URL? {
        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard let data = pdfData, !data.isEmpty else { return nil }
        let name = fileName.isEmpty ? "FiyatListesi_\(brand).pdf" : fileName
        let tmp  = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: tmp, options: .atomic)
            return tmp
        } catch {
            return nil
        }
    }

    /// Gömülü PDF'i kalıcı Documents konumuna geri yazar (cihaz değişimi sonrası onarım).
    @discardableResult
    func restorePDFToDocuments() -> Bool {
        guard !fileExists, let data = pdfData, !data.isEmpty, let url = fileURL else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
