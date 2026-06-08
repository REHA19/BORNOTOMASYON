import SwiftData
import UIKit
import SwiftUI
import Foundation

@Model final class KategoriTanim {
    var name:       String = ""
    var colorHex:   String = "#B07C28"
    var orderIndex: Int    = 0
    var brand:      String = "Alapala"

    init(name: String, colorHex: String = "#B07C28",
         orderIndex: Int = 0, brand: String = "Alapala") {
        self.name       = name
        self.colorHex   = colorHex
        self.orderIndex = orderIndex
        self.brand      = brand
    }

    var uiColor: UIColor { UIColor(hex: colorHex) ?? UIColor(red: 0.69, green: 0.49, blue: 0.16, alpha: 1) }
    var swiftColor: Color { Color(hex: colorHex) }
}

// MARK: - Varsayılan kategori tanımları

extension KategoriTanim {
    static let alapalaDefaults: [(name: String, hex: String)] = [
        ("SIĞIR SÜT YEMLERİ( 50 kg)",       "#1A5E9A"),  // koyu mavi
        ("SIĞIR BESİ YEMLERİ( 50 kg)",       "#8B4513"),  // kahve
        ("SIĞIR BESİ TOZ YEMLERİ( 50 kg)",   "#4A6741"),  // koyu yeşil
        ("KUZU TOKLU YEMLERİ( 50 kg)",        "#2D6A4F"),  // orman yeşili
        ("BUZAĞI YEMLERİ( 40-50 kg)",         "#1B4F8A"),  // lacivert
        ("ÖZEL YEMLER( 50 kg)",               "#6B3FA0"),  // mor
        ("KANATLI YEMLERİ ( 50 KG)",          "#C0392B"),  // kırmızı
    ]

    static func seedIfNeeded(brand: String, existing: [KategoriTanim]) -> [KategoriTanim] {
        guard existing.isEmpty else { return [] }
        let defaults = brand == "Alapala" ? alapalaDefaults : alapalaDefaults
        return defaults.enumerated().map { idx, item in
            KategoriTanim(name: item.name, colorHex: item.hex,
                          orderIndex: idx, brand: brand)
        }
    }
}
