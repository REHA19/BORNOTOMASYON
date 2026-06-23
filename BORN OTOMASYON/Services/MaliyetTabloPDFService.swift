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
        let toplamMaliyet:       Double   // ₺/ton (rasyon + gider kalemleri)
        let karPct:              Double
        let pesin:               Double   // ₺/çuval
        let lastPublishedPesin:  Double?  // ₺/çuval — son yayınlanan listeden
    }

    static func generateMaliyetTablosu(rows: [CostRow], brand: String) -> Data {
        let canvas = BornPDFCanvas()
        return canvas.render { c in
            c.banner(title: "Maliyet Tablosu", subtitle: brand)
            c.metaBox([("Tarih", dateStr()), ("Ürün Sayısı", "\(rows.count)")])
            let cols: [(String, CGFloat)] = [
                ("Kod", 42), ("Ürün", 145), ("Rasyon ₺/t", 60), ("Toplam ₺/t", 60),
                ("Kar%", 32), ("Peşin ₺", 58), ("Önceki ₺", 58), ("Fark ₺", 66)
            ]
            c.tableHeader(cols)
            for (i, r) in rows.enumerated() {
                let farkStr: String = r.lastPublishedPesin.map {
                    String(format: "%+.2f", r.pesin - $0)
                } ?? "—"
                c.tableRow([
                    r.code, r.name,
                    String(format: "%.0f", r.rasyon),
                    String(format: "%.0f", r.toplamMaliyet),
                    String(format: "%.1f", r.karPct),
                    String(format: "%.2f", r.pesin),
                    r.lastPublishedPesin.map { String(format: "%.2f", $0) } ?? "—",
                    farkStr
                ], cols, idx: i)
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
