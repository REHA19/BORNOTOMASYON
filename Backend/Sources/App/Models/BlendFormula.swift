import Fluent
import Vapor

/// Ported from iOS Models/BlendFormula.swift. JSON blob fields stay as opaque
/// strings (stored as Postgres JSONB) exactly like the SwiftData version —
/// RationSolver decodes/encodes them, so the wire format must match byte-for-byte,
/// including the ∞/-∞/NaN string convention (see JSONCoding.swift).
final class BlendFormula: Model, Content, @unchecked Sendable {
    static let schema = "blend_formulas"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "code")
    var code: String

    @Field(key: "name")
    var name: String

    @Field(key: "total_kg")
    var totalKg: Double

    @Field(key: "recorded_cost_tl")
    var recordedCostTL: Double

    @Field(key: "ingredients_json")
    var ingredientsJSON: String

    @Field(key: "constraints_json")
    var constraintsJSON: String

    @OptionalField(key: "last_solve_json")
    var lastSolveJSON: String?

    @Field(key: "combinations_json")
    var combinationsJSON: String

    /// Optimistic locking (Plan §6 risks) — bumped on every update; stale writes get 409.
    @Field(key: "version")
    var version: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, code: String, name: String, totalKg: Double = 1000) {
        self.id = id
        self.code = code
        self.name = name
        self.totalKg = totalKg
        self.recordedCostTL = 0
        self.ingredientsJSON = "[]"
        self.constraintsJSON = "[]"
        self.combinationsJSON = "[]"
        self.version = 1
    }

    var ingredients: [BFIngredient] {
        get { JSONCoding.decode([BFIngredient].self, from: ingredientsJSON) ?? [] }
        set { ingredientsJSON = JSONCoding.encode(newValue) }
    }

    var constraints: [BFConstraint] {
        get { JSONCoding.decode([BFConstraint].self, from: constraintsJSON) ?? [] }
        set { constraintsJSON = JSONCoding.encode(newValue) }
    }

    var lastSolve: BFSolveResult? {
        get { lastSolveJSON.flatMap { JSONCoding.decode(BFSolveResult.self, from: $0) } }
        set { lastSolveJSON = newValue.map { JSONCoding.encode($0) } }
    }

    var combinations: [BFCombination] {
        get { JSONCoding.decode([BFCombination].self, from: combinationsJSON) ?? [] }
        set { combinationsJSON = JSONCoding.encode(newValue) }
    }
}

// MARK: - Supporting structs (verbatim port from iOS BlendFormula.swift)

struct BFIngredient: Codable, Hashable, Content {
    var id: UUID = UUID()
    var code: String
    var name: String
    var isActive: Bool = true
    var hasStock: Bool = true
    var minPct: Double = 0
    var maxPct: Double = 100
    var mixPct: Double = 0
    var productionMixPct: Double = 0
    var previousMixPct: Double = 0
    var overridePriceTLPerTon: Double?
}

struct BFConstraint: Codable, Hashable, Content {
    var id: UUID = UUID()
    var nutrientKey: String
    var displayName: String
    var unit: String
    var isActive: Bool = true
    var showInResult: Bool = true
    var minValue: Double?
    var maxValue: Double?
    var currentValue: Double?
    var previousValue: Double?
    var productionValue: Double?
}

struct BFCombination: Codable, Hashable, Content {
    var id: UUID = UUID()
    var slot: Int
    var ingredientCodes: [String] = []
    var minKg: Double?
    var maxKg: Double?
}

struct BFSolveResult: Codable, Content {
    var percentagesByCode: [String: Double]
    var costPerTon: Double
    var nutrientValues: [String: Double]
    var isFeasible: Bool
    var message: String
    var solvedAt: Date = Date()
    var reducedCosts: [String: Double] = [:]
    var costRangeIncreases: [String: Double] = [:]
    var shadowPricesMin: [String: Double] = [:]
    var shadowPricesMax: [String: Double] = [:]
}
