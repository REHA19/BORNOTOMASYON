import SwiftData
import Foundation

@Model final class StokKategori {
    var name:       String  = ""
    var isFixed:    Bool    = false
    var orderIndex: Int     = 0

    init(name: String, isFixed: Bool = false, orderIndex: Int = 0) {
        self.name       = name
        self.isFixed    = isFixed
        self.orderIndex = orderIndex
    }
}

// MARK: - Seed verileri

extension StokKategori {

    // Silinemeyen sabit kategoriler
    static let fixedNames: [String] = [
        "Ribon",
        "Etiket",
        "Stoktaki Yemler",
        "Kazan Kimyasalları",
        "Kazan Tuz",
        "Lab Kimyasalları",
        "Kan Kiti",
        "Ankom",
    ]

    // Varsayılan kullanıcı kategorileri (silinebilir)
    static let defaultUserNames: [String] = [
        "Çuval İp",
        "Alapala Yem Çuval",
        "Karadeniz Yem Çuval",
        "Tarkon Yem Çuval",
    ]

    static func seedIfNeeded(context: ModelContext) {
        let fetchDesc = FetchDescriptor<StokKategori>()
        guard let existing = try? context.fetch(fetchDesc), existing.isEmpty else { return }

        var idx = 0
        for name in fixedNames {
            context.insert(StokKategori(name: name, isFixed: true, orderIndex: idx))
            idx += 1
        }
        for name in defaultUserNames {
            context.insert(StokKategori(name: name, isFixed: false, orderIndex: idx))
            idx += 1
        }
        try? context.save()
    }
}
