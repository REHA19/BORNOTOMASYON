import SwiftData
import Foundation

// MARK: - Çeyreklik Oto-Hesap Servisi

enum BilancoService {

    struct OtoSonuc {
        var smm: Double       // Satılan Mal Maliyeti ₺
        var stok: Double      // Dönem sonu stok değeri ₺
        var toplamUretimTon: Double
    }

    // Çeyreğin 3 aylık verilerini FormulaCostEntry + GiderKalemi + StokAylikRapor'dan toplar
    static func hesapla(
        yil: Int,
        ceyrek: Int,
        context: ModelContext
    ) -> OtoSonuc {
        let (basAy, sonAy) = ayAraligi(ceyrek: ceyrek)

        // FormulaCostEntry: çeyrek tarih aralığındaki kayıtlar
        let costDesc = FetchDescriptor<FormulaCostEntry>()
        let tumKayitlar = (try? context.fetch(costDesc)) ?? []

        let aralikBaslangic = donemBaslangic(yil: yil, ay: basAy)
        let aralikBitis     = donemBitis(yil: yil, ay: sonAy)

        let donemKayitlar = tumKayitlar.filter {
            $0.recordedAt >= aralikBaslangic && $0.recordedAt <= aralikBitis
        }

        // Deduplicate: formulaCode + ay bazında son kaydı al.
        // "Üretime Kaydet" her basışta yeni satır ekler; toplamı değil sadece
        // her formülün o aydaki son üretim kaydını SMM'ye yansıtıyoruz.
        let cal = Calendar.current
        var latestPerKey: [String: FormulaCostEntry] = [:]
        for entry in donemKayitlar {
            let ay = cal.component(.month, from: entry.recordedAt)
            let key = "\(entry.formulaCode)_\(ay)"
            if let existing = latestPerKey[key] {
                if entry.recordedAt > existing.recordedAt { latestPerKey[key] = entry }
            } else {
                latestPerKey[key] = entry
            }
        }
        let tekilKayitlar = Array(latestPerKey.values)

        // SMM = Σ (costPerTon ₺/ton × tons ton) — tekil kayıtlar üzerinden
        let smm = tekilKayitlar.reduce(0.0) { $0 + $1.costPerTon * $1.tons }
        let toplamTon = tekilKayitlar.reduce(0.0) { $0 + $1.tons }

        // Dönem sonu stok — çeyreğin son ayının raporu
        let stokDesc = FetchDescriptor<StokAylikRapor>(
            predicate: #Predicate { $0.yil == yil && $0.ay == sonAy }
        )
        let stok = (try? context.fetch(stokDesc))?.first?.grandTotal ?? 0

        return OtoSonuc(smm: smm, stok: stok, toplamUretimTon: toplamTon)
    }

    // MARK: - Yardımcı

    private static func ayAraligi(ceyrek: Int) -> (bas: Int, son: Int) {
        let bas = (ceyrek - 1) * 3 + 1
        return (bas, bas + 2)
    }

    private static func donemBaslangic(yil: Int, ay: Int) -> Date {
        var c = DateComponents(); c.year = yil; c.month = ay; c.day = 1
        c.hour = 0; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? .distantPast
    }

    private static func donemBitis(yil: Int, ay: Int) -> Date {
        var c = DateComponents(); c.year = yil; c.month = ay + 1; c.day = 1
        c.hour = 0; c.minute = 0; c.second = -1
        return Calendar.current.date(from: c) ?? .distantFuture
    }
}
