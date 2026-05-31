import SwiftData
import Foundation

// MARK: - SwiftData Model

@Model
final class BlendFormula {
    var code: String            = ""
    var name: String            = ""
    var totalKg: Double         = 1000
    var createdAt: Date         = Date()
    var updatedAt: Date         = Date()
    var recordedCostTL: Double  = 0
    var ingredientsJSON: String = "[]"
    var constraintsJSON: String = "[]"
    var lastSolveJSON: String?

    init(code: String, name: String, totalKg: Double = 1000) {
        self.code           = code
        self.name           = name
        self.totalKg        = totalKg
        self.createdAt      = Date()
        self.updatedAt      = Date()
        self.recordedCostTL = 0
        self.ingredientsJSON = "[]"
        self.constraintsJSON = "[]"
    }

    var ingredients: [BFIngredient] {
        get { decode([BFIngredient].self, from: ingredientsJSON) ?? [] }
        set { ingredientsJSON = encode(newValue) }
    }

    var constraints: [BFConstraint] {
        get { decode([BFConstraint].self, from: constraintsJSON) ?? [] }
        set { constraintsJSON = encode(newValue) }
    }

    var lastSolve: BFSolveResult? {
        get {
            guard let j = lastSolveJSON else { return nil }
            return decode(BFSolveResult.self, from: j)
        }
        set { lastSolveJSON = newValue.map { encode($0) } }
    }

    var combinationsJSON: String = "[]"

    var combinations: [BFCombination] {
        get { decode([BFCombination].self, from: combinationsJSON) ?? [] }
        set { combinationsJSON = encode(newValue) }
    }

    var currentCostTL: Double { lastSolve?.costPerTon ?? 0 }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func encode<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "[]"
    }
}

// MARK: - Supporting structs

struct BFIngredient: Codable, Identifiable, Hashable {
    var id:                 UUID   = UUID()
    var code:               String
    var name:               String
    var isActive:           Bool   = true
    var hasStock:           Bool   = true
    var minPct:             Double = 0      // % minimum
    var maxPct:             Double = 100    // % maximum
    var mixPct:             Double = 0      // çözüm sonucu %
    var productionMixPct:   Double = 0
    var previousMixPct:     Double = 0
    var overridePriceTLPerTon: Double?      // nil → kütüphaneden al
}

struct BFConstraint: Codable, Identifiable, Hashable {
    var id:             UUID   = UUID()
    var nutrientKey:    String
    var displayName:    String
    var unit:           String
    var isActive:       Bool   = true
    var showInResult:   Bool   = true        // Sonuç sekmesinde göster
    var minValue:       Double?
    var maxValue:       Double?
    var currentValue:   Double?
    var previousValue:  Double?
    var productionValue: Double?

    // Always use the canonical name from allNutrientDefs; fall back to stored displayName
    var resolvedDisplayName: String {
        allNutrientDefs.first { $0.key == nutrientKey }?.displayName ?? displayName
    }
}

// Hammadde kombinasyon kısıtı: birden fazla hammaddenin birlikte max/min'i
struct BFCombination: Codable, Identifiable, Hashable {
    var id:               UUID     = UUID()
    var slot:             Int                   // 1-10
    var ingredientCodes:  [String] = []         // bu kombinasyondaki hammadde kodları
    var minKg:            Double?               // toplam min kg (nil = sınır yok)
    var maxKg:            Double?               // toplam max kg (nil = sınır yok)
}

struct BFSolveResult: Codable {
    var percentagesByCode:  [String: Double]  // code → %
    var costPerTon:         Double
    var nutrientValues:     [String: Double]
    var isFeasible:         Bool
    var message:            String
    var solvedAt:           Date    = Date()
    // Sensitivity — gölge fiyat analizi
    var reducedCosts:       [String: Double] = [:]   // rasyona girmeyen: gerekli fiyat düşüşü ₺/ton
    var costRangeIncreases: [String: Double] = [:]   // rasyondaki: maks fiyat artışı ₺/ton
}
