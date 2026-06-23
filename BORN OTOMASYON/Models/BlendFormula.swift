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

    // MARK: - Decode cache (@Transient = persisted değil, render döngüsünde tekrar decode önler)
    @Transient private var _ingKey:   String = ""; @Transient private var _ingCache:   [BFIngredient]?  = nil
    @Transient private var _conKey:   String = ""; @Transient private var _conCache:   [BFConstraint]?  = nil
    @Transient private var _solKey:   String = ""; @Transient private var _solCache:   BFSolveResult??  = .some(nil)
    @Transient private var _combKey:  String = ""; @Transient private var _combCache:  [BFCombination]? = nil

    var ingredients: [BFIngredient] {
        get {
            if _ingKey != ingredientsJSON || _ingCache == nil {
                _ingCache = decode([BFIngredient].self, from: ingredientsJSON) ?? []
                _ingKey   = ingredientsJSON
            }
            return _ingCache!
        }
        set {
            let enc     = encode(newValue)
            ingredientsJSON = enc
            _ingCache   = newValue
            _ingKey     = enc
        }
    }

    var constraints: [BFConstraint] {
        get {
            if _conKey != constraintsJSON || _conCache == nil {
                _conCache = decode([BFConstraint].self, from: constraintsJSON) ?? []
                _conKey   = constraintsJSON
            }
            return _conCache!
        }
        set {
            let enc     = encode(newValue)
            constraintsJSON = enc
            _conCache   = newValue
            _conKey     = enc
        }
    }

    var lastSolve: BFSolveResult? {
        get {
            let key = lastSolveJSON ?? ""
            if _solKey != key {
                _solCache = lastSolveJSON.flatMap { decode(BFSolveResult.self, from: $0) }
                _solKey   = key
            }
            return _solCache ?? nil
        }
        set {
            let enc     = newValue.map { encode($0) }
            lastSolveJSON = enc
            _solCache   = .some(newValue)
            _solKey     = enc ?? ""
        }
    }

    var combinationsJSON: String = "[]"

    var combinations: [BFCombination] {
        get {
            if _combKey != combinationsJSON || _combCache == nil {
                _combCache = decode([BFCombination].self, from: combinationsJSON) ?? []
                _combKey   = combinationsJSON
            }
            return _combCache!
        }
        set {
            let enc     = encode(newValue)
            combinationsJSON = enc
            _combCache  = newValue
            _combKey    = enc
        }
    }

    var currentCostTL: Double { lastSolve?.costPerTon ?? 0 }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "∞", negativeInfinity: "-∞", nan: "NaN"
        )
        return try? dec.decode(type, from: data)
    }
    private func encode<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "∞", negativeInfinity: "-∞", nan: "NaN"
        )
        return (try? String(data: enc.encode(value), encoding: .utf8)) ?? "[]"
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
    // Kısıt dual değişkenleri — ₺/ton per 1 orijinal birim gevşeme
    var shadowPricesMin:    [String: Double] = [:]   // ≥ kısıtlar (besin min)
    var shadowPricesMax:    [String: Double] = [:]   // ≤ kısıtlar (besin max)
    // Kısıt sağlanamadığında: sınır gevşetme önerileri (maliyete göre sıralı)
    var shortfallReports:   [ConstraintShortfallReport] = []
}
