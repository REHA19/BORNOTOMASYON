import SwiftData
import Foundation

// MARK: - Template ingredient (lighter than BFIngredient — no LP result fields)

struct TemplateIngredient: Codable, Identifiable, Hashable {
    var id:     UUID   = UUID()
    var code:   String
    var name:   String
    var minPct: Double = 0
    var maxPct: Double = 100
}

// MARK: - SwiftData model

@Model
final class FormulaTemplate {
    var name:            String = ""
    var createdAt:       Date   = Date()
    var ingredientsJSON: String = "[]"  // [TemplateIngredient]
    var constraintsJSON: String = "[]"  // [BFConstraint]

    init(name: String) {
        self.name            = name
        self.createdAt       = Date()
        self.ingredientsJSON = "[]"
        self.constraintsJSON = "[]"
    }

    var ingredients: [TemplateIngredient] {
        get { decode([TemplateIngredient].self, from: ingredientsJSON) ?? [] }
        set { ingredientsJSON = encode(newValue) }
    }

    var constraints: [BFConstraint] {
        get { decode([BFConstraint].self, from: constraintsJSON) ?? [] }
        set { constraintsJSON = encode(newValue) }
    }

    private func decode<T: Decodable>(_ t: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(t, from: data)
    }
    private func encode<T: Encodable>(_ v: T) -> String {
        (try? String(data: JSONEncoder().encode(v), encoding: .utf8)) ?? "[]"
    }
}
