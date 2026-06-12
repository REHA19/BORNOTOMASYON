import SwiftData
import Foundation

@Model final class StokAylikRapor {
    var yil:             Int    = 0
    var ay:              Int    = 0    // 1–12
    var snapshotJSON:    String = "{}"
    var hammaddeToplam:  Double = 0
    var manuelToplam:    Double = 0
    var grandTotal:      Double = 0
    var kayitTarihi:     Date   = Date()
    var kayitSayisi:     Int    = 1    // bu ay kaç kez kaydedildi
    var isOtomatik:      Bool   = false

    init(yil: Int, ay: Int) {
        self.yil = yil
        self.ay  = ay
    }

    // MARK: - Başlık

    var ayBaslik: String {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year  = yil
        comps.month = ay
        comps.day   = 1
        guard let date = cal.date(from: comps) else { return "\(ay)/\(yil)" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date).capitalized
    }

    // MARK: - Snapshot erişimi

    var snapshot: StokRaporSnapshot? {
        StokRaporSnapshot.from(json: snapshotJSON)
    }

    func update(with snap: StokRaporSnapshot, otomatik: Bool = false) {
        snapshotJSON   = snap.toJSON()
        hammaddeToplam = snap.hammaddeToplam
        manuelToplam   = snap.manuelToplam
        grandTotal     = snap.grandTotal
        kayitTarihi    = Date()
        kayitSayisi   += 1
        isOtomatik     = otomatik
    }
}

// MARK: - Snapshot oluşturma yardımcıları

extension StokAylikRapor {

    static func buildSnapshot(
        hammaddeRows: [HammaddeSnapshot],
        manuelKalemler: [StokManuelKalem],
        hammaddeToplam: Double,
        manuelToplam: Double,
        grandTotal: Double,
        usdRate: Double,
        eurRate: Double
    ) -> StokRaporSnapshot {

        let manuelSnaps = manuelKalemler.map { item in
            ManuelKalemSnapshot(
                name:      item.name,
                category:  item.category,
                quantity:  item.quantity,
                unit:      item.unit,
                unitPrice: item.unitPrice,
                currency:  item.currency,
                totalTL:   item.totalTL(usdRate: usdRate, eurRate: eurRate)
            )
        }

        return StokRaporSnapshot(
            hammaddeler:     hammaddeRows,
            manuelKalemler:  manuelSnaps,
            hammaddeToplam:  hammaddeToplam,
            manuelToplam:    manuelToplam,
            grandTotal:      grandTotal,
            usdRate:         usdRate,
            eurRate:         eurRate,
            olusturmaTarihi: Date()
        )
    }

    // Aynı yıl/ay kontrolü
    static func existing(yil: Int, ay: Int, in context: ModelContext) -> StokAylikRapor? {
        let desc = FetchDescriptor<StokAylikRapor>(
            predicate: #Predicate { $0.yil == yil && $0.ay == ay }
        )
        return (try? context.fetch(desc))?.first
    }

    @discardableResult
    static func upsert(
        snapshot: StokRaporSnapshot,
        yil: Int, ay: Int,
        otomatik: Bool = false,
        context: ModelContext
    ) -> StokAylikRapor {
        if let existing = existing(yil: yil, ay: ay, in: context) {
            existing.update(with: snapshot, otomatik: otomatik)
            try? context.save()
            return existing
        } else {
            let rapor = StokAylikRapor(yil: yil, ay: ay)
            rapor.snapshotJSON   = snapshot.toJSON()
            rapor.hammaddeToplam = snapshot.hammaddeToplam
            rapor.manuelToplam   = snapshot.manuelToplam
            rapor.grandTotal     = snapshot.grandTotal
            rapor.kayitSayisi    = 1
            rapor.isOtomatik     = otomatik
            context.insert(rapor)
            try? context.save()
            return rapor
        }
    }
}
