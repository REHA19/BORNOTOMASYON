import SwiftData
import UIKit
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
    var logoName:        String  = ""       // Asset catalog logo adı
    var logoImagePath:   String  = ""       // (legacy — lokal fallback)
    var logoImageData: Data? = nil   // CloudKit inline Data olarak senkronize edilir
    var brand:           String  = "Alapala"
    var proteinOverride: Double  = -1.0    // ≥0 → manuel protein %, -1 → formül değeri
    var manualPesin:     Double  = -1.0    // ≥0 → manuel peşin ₺/çuval, -1 → hesaplanan

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

    // Logo yükle: CloudKit data → lokal dosya → asset catalog
    var logoImage: UIImage? {
        if let data = logoImageData, let img = UIImage(data: data) { return img }
        if !logoImagePath.isEmpty,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent(logoImagePath)
            if let img = UIImage(contentsOfFile: url.path) { return img }
        }
        if !logoName.isEmpty { return UIImage(named: logoName) }
        return nil
    }

    // Logo kaydet (galeriden seçilen görsel verisi)
    static func saveLogoData(_ data: Data) -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = docs.appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "logo_\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        guard let img = UIImage(data: data),
              let jpeg = img.jpegData(compressionQuality: 0.85)
        else { return nil }
        try? jpeg.write(to: url)
        return "logos/\(filename)"
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
        rasyon:     Double,
        ipCuval:    Double, firePct: Double,
        elektrik:   Double, nakliye: Double, iscilik: Double,
        karPct:     Double, bagKg:   Int,
        extraItems: [(value: Double, isPercent: Bool)] = []
    ) -> PricingCalc {
        let fire       = rasyon * firePct / 100
        let extraTotal = extraItems.reduce(0.0) {
            $0 + ($1.isPercent ? rasyon * $1.value / 100 : $1.value)
        }
        let toplam = rasyon + ipCuval + fire + elektrik + nakliye + iscilik + extraTotal
        let pesin  = toplam * (1 + karPct / 100) * (Double(bagKg) / 1000)
        return PricingCalc(
            rasyon: rasyon, ipCuval: ipCuval, fire: fire,
            elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
            toplam: toplam, karPct: karPct, pesin: pesin, bagKg: bagKg
        )
    }
}
