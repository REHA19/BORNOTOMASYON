import SwiftData
import Foundation

// MARK: - Çeyreklik Bilanço Modeli

@Model final class CeyrekBilanco {
    var yil: Int      = 0    // örn. 2026
    var ceyrek: Int   = 0    // 1–4
    var notlar: String = ""
    var kayitTarihi: Date = Date()

    // ── Gelir Tablosu ──────────────────────────────────────────────────────
    var netSatislar: Double = 0    // MANUEL — ₺ (muhasebe girişi)
    var smmOto: Double      = 0    // OTO — Σ FormulaCostEntry.costPerTon × tons
    var opGiderOto: Double  = 0    // OTO — GiderKalemi × toplam üretim tonu

    // ── Aktif — Dönen Varlıklar ───────────────────────────────────────────
    var nakit: Double       = 0    // MANUEL
    var alacaklar: Double   = 0    // MANUEL
    var stokOto: Double     = 0    // OTO — StokAylikRapor (çeyreğin son ayı)
    var digerDonen: Double  = 0    // MANUEL

    // ── Aktif — Duran Varlıklar ───────────────────────────────────────────
    var sabitKiymetBrut: Double = 0   // MANUEL
    var birikmisBrut: Double    = 0   // MANUEL (birikmiş amortisman)
    var digerDuran: Double      = 0   // MANUEL

    // ── Pasif — Kısa Vadeli ───────────────────────────────────────────────
    var kisaVadeli: Double = 0     // MANUEL

    // ── Pasif — Uzun Vadeli ───────────────────────────────────────────────
    var uzunVadeli: Double = 0     // MANUEL

    // ── Öz Kaynak ─────────────────────────────────────────────────────────
    var sermaye: Double      = 0   // MANUEL
    var gecmisKarlar: Double = 0   // MANUEL (önceki dönemlerin net kar toplamı)

    init(yil: Int, ceyrek: Int) {
        self.yil    = yil
        self.ceyrek = ceyrek
    }
}

// MARK: - Hesaplanan Değerler

extension CeyrekBilanco {

    var brutKar: Double         { netSatislar - smmOto }
    var donemNetKari: Double    { brutKar - opGiderOto }

    var sabitKiymetNet: Double  { sabitKiymetBrut - birikmisBrut }
    var donenVarliklar: Double  { nakit + alacaklar + stokOto + digerDonen }
    var duranVarliklar: Double  { sabitKiymetNet + digerDuran }
    var toplamAktif: Double     { donenVarliklar + duranVarliklar }

    var ozKaynak: Double        { sermaye + gecmisKarlar + donemNetKari }
    var toplamPasif: Double     { kisaVadeli + uzunVadeli + ozKaynak }

    var fark: Double            { toplamAktif - toplamPasif }
    var dengeSaglandı: Bool     { abs(fark) < 1.0 }

    var ceyrekBasligi: String {
        ["", "Ocak–Mart", "Nisan–Haziran", "Temmuz–Eylül", "Ekim–Aralık"][max(0, min(4, ceyrek))]
    }

    var kisaBaslik: String { "Q\(ceyrek) \(yil)" }

    // Çeyreğin ayları: (başlangıç, bitiş) — 1-bazlı ay
    var ayAraligi: (bas: Int, son: Int) {
        let bas = (ceyrek - 1) * 3 + 1
        return (bas, bas + 2)
    }

    // MARK: - Veritabanı Yardımcıları

    static func existing(yil: Int, ceyrek: Int, in context: ModelContext) -> CeyrekBilanco? {
        let desc = FetchDescriptor<CeyrekBilanco>(
            predicate: #Predicate { $0.yil == yil && $0.ceyrek == ceyrek }
        )
        return (try? context.fetch(desc))?.first
    }

    @discardableResult
    static func upsert(yil: Int, ceyrek: Int, in context: ModelContext) -> CeyrekBilanco {
        if let existing = existing(yil: yil, ceyrek: ceyrek, in: context) {
            return existing
        }
        let bilanco = CeyrekBilanco(yil: yil, ceyrek: ceyrek)
        context.insert(bilanco)
        try? context.save()
        return bilanco
    }
}
