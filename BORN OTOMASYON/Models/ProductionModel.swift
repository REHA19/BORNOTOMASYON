import Foundation

// MARK: - Aylık üretimde bir ürün

struct ProductionEntry: Identifiable {
    let id:          String   // productCode
    let productCode: String
    let productName: String
    let formulaName: String?
    let formulaID:   Int?
    let totalKg:     Double   // ay içinde toplam üretilen miktar

    var formulaItems:  [ScaledMaterialItem] = []
    var formulaLoaded: Bool = false
}

// MARK: - Formül malzemesi, gerçek üretim miktarına ölçeklenmiş

struct ScaledMaterialItem: Identifiable {
    let id:           String  // materialCode
    let materialCode: String
    let materialName: String
    let totalKg:      Double  // gerçek üretim × (ingredient% / 100)
    let isAdditive:   Bool
}

// MARK: - Ay özeti

struct ProductionSummary {
    let month:   Date
    var entries: [ProductionEntry]

    var totalKg:      Double { entries.reduce(0) { $0 + $1.totalKg } }
    var productCount: Int    { entries.count }

    // Tüm ürünlerin hammaddelerini toplar
    var aggregatedMaterials: [ScaledMaterialItem] {
        var dict: [String: ScaledMaterialItem] = [:]
        for entry in entries {
            for item in entry.formulaItems {
                if let existing = dict[item.materialCode] {
                    dict[item.materialCode] = ScaledMaterialItem(
                        id:           existing.id,
                        materialCode: existing.materialCode,
                        materialName: existing.materialName,
                        totalKg:      existing.totalKg + item.totalKg,
                        isAdditive:   existing.isAdditive
                    )
                } else {
                    dict[item.materialCode] = item
                }
            }
        }
        return dict.values.sorted { $0.totalKg > $1.totalKg }
    }
}
