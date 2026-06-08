import SwiftData
import Foundation

// MARK: - Ürün başına fiyatlandırma metadata'sı

@Model final class ProductPricingMeta {
    var formulaCode:    String  = ""     // BlendFormula.code ile eşleşir
    var form:           String  = "Pelet"  // "Pelet-Granül", "Pelet", "Toz", "TANELİ"
    var categoryGroup:  String  = ""     // "SIĞIR SÜT YEMLERİ( 50 kg)" vb.
    var bagKg:          Int     = 50     // çuval ağırlığı: 50 veya 40
    var orderIndex:     Int     = 0      // listede sıra
    var isVisible:      Bool    = true   // fiyat listesinde göster
    var overrideKarPct: Double  = -1.0   // -1 → global KAR% kullanılır, ≥0 → ürüne özel
    var logoName:       String  = ""     // Asset catalog logo adı (boş = logo yok)
    var brand:          String  = "Alapala"  // "Alapala" veya "Karadeniz"

    init(formulaCode: String,
         form: String = "Pelet",
         categoryGroup: String = "",
         bagKg: Int = 50,
         orderIndex: Int = 0,
         isVisible: Bool = true,
         overrideKarPct: Double = -1,
         logoName: String = "",
         brand: String = "Alapala") {
        self.formulaCode    = formulaCode
        self.form           = form
        self.categoryGroup  = categoryGroup
        self.bagKg          = bagKg
        self.orderIndex     = orderIndex
        self.isVisible      = isVisible
        self.overrideKarPct = overrideKarPct
        self.logoName       = logoName
        self.brand          = brand
    }
}

// MARK: - Hesaplama sonucu (anlık)

struct PricingCalc {
    let rasyon:   Double
    let ipCuval:  Double
    let fire:     Double
    let elektrik: Double
    let nakliye:  Double
    let iscilik:  Double
    let toplam:   Double   // Genel Mailyeti ₺/ton
    let karPct:   Double
    let pesin:    Double   // ₺/çuval (peşin barem)
    let bagKg:    Int

    func vadePrice(pct: Double) -> Double { pesin * (1 + pct / 100) }

    static func calculate(
        rasyon:   Double,
        ipCuval:  Double, firePct: Double,
        elektrik: Double, nakliye: Double, iscilik: Double,
        karPct:   Double, bagKg:   Int
    ) -> PricingCalc {
        let fire   = rasyon * firePct / 100
        let toplam = rasyon + ipCuval + fire + elektrik + nakliye + iscilik
        let pesin  = toplam * (1 + karPct / 100) * (Double(bagKg) / 1000)
        return PricingCalc(
            rasyon: rasyon, ipCuval: ipCuval, fire: fire,
            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
            toplam: toplam, karPct: karPct, pesin: pesin, bagKg: bagKg
        )
    }
}
