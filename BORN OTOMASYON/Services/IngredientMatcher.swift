import Foundation

// MARK: - LibEntry protocol — allows generic matching over FeedIngredient and IngSnap

protocol LibEntry {
    var code: String { get }
    var name: String { get }
    var priceTL: Double? { get }
    func nutrientValue(forKey key: String) -> Double?
}

// MARK: - Sendable value-type snapshot of FeedIngredient (safe for background threads)

struct IngSnap: Sendable, LibEntry {
    let code:      String
    let name:      String
    let priceTL:   Double?
    let nutrients: [String: Double]

    func nutrientValue(forKey key: String) -> Double? { nutrients[key] }

    static func from(_ f: FeedIngredient) -> IngSnap {
        var n: [String: Double] = [:]
        let keys = Set(allNutrientDefs.map(\.key))
                 .union(AlapalaFormulaParser.codeMap.values.map(\.key))
        for k in keys { if let v = f.nutrientValue(forKey: k) { n[k] = v } }
        for (k, v) in f.extras { n[k] = v }
        return IngSnap(code: f.code, name: f.name, priceTL: f.priceTL, nutrients: n)
    }
}

// MARK: - FeedIngredient conforms to LibEntry (code/name/priceTL + nutrientValue already exist)
extension FeedIngredient: LibEntry {}

/// Sarfiyat / üretim API verilerini SwiftData FeedIngredient kaydıyla eşleştirir.
/// Önce tam kod, sonra tam isim, sonra içerik eşleşmesi dener.
struct IngredientMatcher {

    static func find<T: LibEntry>(code: String, name: String, in list: [T]) -> T? {
        // 1. Tam kod eşleşmesi
        if !code.isEmpty,
           let m = list.first(where: { !$0.code.isEmpty && $0.code == code }) {
            return m
        }
        // 2. Tam isim eşleşmesi (büyük harf, Türkçe karakterlere duyarsız)
        let norm = normalized(name)
        if let m = list.first(where: { normalized($0.name) == norm }) { return m }
        // 3. Kısmi isim eşleşmesi (en uzun eşleşmeyi tercih et)
        let candidates = list.filter {
            let n = normalized($0.name)
            return norm.contains(n) || n.contains(norm)
        }
        return candidates.max(by: { $0.name.count < $1.name.count })
    }

    // Türkçe büyük/küçük ve aksan farklarını giderir: "Mısır" == "MISIR"
    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
         .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
         .uppercased(with: Locale(identifier: "en_US"))
    }

    /// Maliyet hesabı: fiyat ₺/ton, miktar kg.
    static func cost<T: LibEntry>(kg: Double, ingredient: T?) -> Double? {
        guard let p = ingredient?.priceTL, p > 0 else { return nil }
        return kg / 1000.0 * p
    }

    /// Toplam maliyet + eşleşme sayısı.
    struct CostSummary {
        var totalCostTL: Double = 0
        var matchedCount: Int  = 0
        var totalItems:   Int  = 0
    }

    static func summarize(
        items: [(code: String, name: String, kg: Double)],
        in list: [FeedIngredient]
    ) -> CostSummary {
        var s = CostSummary(totalItems: items.count)
        for item in items {
            let ing = find(code: item.code, name: item.name, in: list)
            if let c = cost(kg: item.kg, ingredient: ing) {
                s.totalCostTL += c
                s.matchedCount += 1
            }
        }
        return s
    }
}
