import UIKit
import Foundation

// MARK: - Toplu Fiyat Güncelleme Raporu + Maliyet Tablosu PDF üretimi
// BornPDFCanvas (FormulaExportService.swift) kullanır — markalı/logolu Fiyat Listesi
// PDF'inden (PricingPDFService) farklı olarak, burada sade bir tablo raporu üretilir.

struct MaliyetTabloPDFService {

    // MARK: - Toplu Fiyat Güncelleme Raporu

    struct BulkRow {
        let code:               String
        let name:               String
        let oldPesin:           Double
        let newPesin:           Double
        let lastPublishedPesin: Double?   // nil = son yayınlanan listede bu ürün yok
    }

    static func generateTopluGuncellemeRaporu(rows: [BulkRow], brand: String, deltaTL: Double) -> Data {
        let canvas = BornPDFCanvas()
        return canvas.render { c in
            c.banner(title: "Toplu Fiyat Güncelleme Raporu", subtitle: brand)
            c.metaBox([
                ("Tarih",            dateStr()),
                ("Uygulanan Tutar",  String(format: "%+.2f ₺", deltaTL)),
                ("Ürün Sayısı",      "\(rows.count)")
            ])
            let cols: [(String, CGFloat)] = [
                ("Kod", 45), ("Ürün", 145), ("Eski ₺", 58), ("Yeni ₺", 58),
                ("Fark ₺", 58), ("Fark %", 48), ("Son Liste ₺", 62), ("Liste Farkı ₺", 47)
            ]
            c.tableHeader(cols)
            for (i, r) in rows.enumerated() {
                let fark = r.newPesin - r.oldPesin
                let pct  = r.oldPesin > 0 ? fark / r.oldPesin * 100 : 0
                let listFarkStr: String = r.lastPublishedPesin.map {
                    String(format: "%+.2f", r.newPesin - $0)
                } ?? "—"
                c.tableRow([
                    r.code, r.name,
                    String(format: "%.2f", r.oldPesin),
                    String(format: "%.2f", r.newPesin),
                    String(format: "%+.2f", fark),
                    String(format: "%+.1f%%", pct),
                    r.lastPublishedPesin.map { String(format: "%.2f", $0) } ?? "—",
                    listFarkStr
                ], cols, idx: i)
            }
        }
    }

    // MARK: - Maliyet Tablosu (tüm formüller)

    struct CostRow {
        let code:               String
        let name:               String
        let rasyon:              Double   // ₺/ton
        var ipCuval:             Double = 0
        var fire:                Double = 0
        var elektrik:            Double = 0
        var nakliye:             Double = 0
        var iscilik:             Double = 0
        var giderValues:         [String: Double] = [:]   // gider kalemi adı → ₺/ton katkı
        let toplamMaliyet:       Double   // ₺/ton (rasyon + gider kalemleri)
        let karPct:              Double
        var brutKarPct:          Double = 0   // (satış fiyatı ₺/ton − rasyon) / rasyon × 100
        let pesin:               Double   // ₺/çuval
        let lastPublishedPesin:  Double?  // ₺/çuval — son yayınlanan listeden
        var yeniFiyat:           Double? = nil   // TL toplu ayarı uygulanmışsa önizlenen yeni fiyat
        var yeniKarPct:          Double? = nil   // yeniFiyat'a karşılık gelen gerçek kar oranı
        var oncekiKarlilikPct:   Double? = nil   // son yayınlanan fiyatın GÜNCEL maliyete göre kâr oranı
    }

    /// Ekrandaki sütun key sistemiyle birebir aynı: hangi sütunların PDF'de görüneceği
    /// `columns` ile seçilir/sıralanır. Seçilen sütunlar sayfaya sığmazsa rapor otomatik
    /// yatay düzene geçer; o da yetmezse tüm sütun genişlikleri orantılı küçültülerek
    /// (tam sığacak şekilde) ölçeklenir — hiçbir sütun sayfa dışına taşmaz.
    static func generateMaliyetTablosu(
        rows: [CostRow], brand: String, columns: [String],
        label1: String, label2: String, label3: String, label4: String, label5: String
    ) -> Data {
        func title(_ key: String) -> String {
            switch key {
            case "kod":            return "Kod"
            case "urun":           return "Ürün"
            case "rasyon":         return "Rasyon ₺/t"
            case "ipCuval":        return label1
            case "fire":           return label2
            case "elektrik":       return label3
            case "nakliye":        return label4
            case "iscilik":        return label5
            case "toplamMaliyet":  return "Toplam ₺/t"
            case "kar":            return "Kar%"
            case "brutKar":        return "B.Kar%"
            case "pesin":          return "Peşin ₺"
            case "yeniFiyat":      return "Yeni ₺"
            case "yeniKar":        return "Yeni Kar%"
            case "onceki":         return "Önceki ₺"
            case "oncekiKarlilik": return "Ö.Karlılık%"
            case "fark":           return "Fark ₺"
            default:               return key.hasPrefix("gider:") ? String(key.dropFirst(6)) : key
            }
        }
        func baseWidth(_ key: String) -> CGFloat {
            switch key {
            case "kod":  return 36
            case "urun": return 100
            case "kar", "brutKar", "yeniKar", "oncekiKarlilik": return 32
            default:     return 50
            }
        }
        func value(_ key: String, _ r: CostRow) -> String {
            switch key {
            case "kod":           return r.code
            case "urun":          return r.name
            case "rasyon":        return String(format: "%.0f", r.rasyon)
            case "ipCuval":       return String(format: "%.0f", r.ipCuval)
            case "fire":          return String(format: "%.0f", r.fire)
            case "elektrik":      return String(format: "%.0f", r.elektrik)
            case "nakliye":       return String(format: "%.0f", r.nakliye)
            case "iscilik":       return String(format: "%.0f", r.iscilik)
            case "toplamMaliyet": return String(format: "%.0f", r.toplamMaliyet)
            case "kar":           return String(format: "%.1f", r.karPct)
            case "brutKar":       return String(format: "%.1f", r.brutKarPct)
            case "pesin":         return String(format: "%.2f", r.pesin)
            case "yeniFiyat":     return r.yeniFiyat.map { String(format: "%.2f", $0) } ?? "—"
            case "yeniKar":       return r.yeniKarPct.map { String(format: "%.1f", $0) } ?? "—"
            case "onceki":        return r.lastPublishedPesin.map { String(format: "%.2f", $0) } ?? "—"
            case "oncekiKarlilik": return r.oncekiKarlilikPct.map { String(format: "%.1f", $0) } ?? "—"
            case "fark":          return r.lastPublishedPesin.map { String(format: "%+.2f", r.pesin - $0) } ?? "—"
            default:
                if key.hasPrefix("gider:") {
                    return String(format: "%.0f", r.giderValues[String(key.dropFirst(6))] ?? 0)
                }
                return "—"
            }
        }

        let baseCols   = columns.map { (title($0), baseWidth($0)) }
        let totalWidth = baseCols.reduce(0) { $0 + $1.1 }

        // BornPDFCanvas: M=36 sabit kenar boşluğu, portrait W=595.2, landscape W=841.8
        let portraitAvail  = 595.2 - 72.0
        let landscapeAvail = 841.8 - 72.0
        let useLandscape = totalWidth > portraitAvail
        let avail        = useLandscape ? landscapeAvail : portraitAvail
        let scale        = totalWidth > avail ? avail / totalWidth : 1.0
        let cols: [(String, CGFloat)] = baseCols.map { ($0.0, $0.1 * scale) }

        let canvas = BornPDFCanvas(landscape: useLandscape)
        return canvas.render { c in
            c.banner(title: "Maliyet Tablosu", subtitle: brand)
            c.metaBox([("Tarih", dateStr()), ("Ürün Sayısı", "\(rows.count)")])
            c.tableHeader(cols)
            for (i, r) in rows.enumerated() {
                c.tableRow(columns.map { value($0, r) }, cols, idx: i)
            }
        }
    }

    private static func dateStr() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "tr_TR")
        df.dateFormat = "dd MMMM yyyy, HH:mm"
        return df.string(from: Date())
    }
}

// MARK: - Son yayınlanan fiyat listesi araması (paylaşılan yardımcı)

extension PriceListArchive {
    /// Belirli bir markanın en son YAYINLANMIŞ (isPublished) listesini bulur.
    static func lastPublished(brand: String, in archives: [PriceListArchive]) -> PriceListArchive? {
        archives.filter { $0.brand == brand && $0.isPublished }.max { $0.savedAt < $1.savedAt }
    }
}
