import Fluent
import Vapor

/// Ported from iOS Models/MultiBlendGroup.swift — same JSON-blob philosophy as
/// BlendFormula (Plan §1): values stay as opaque JSON strings, decoded on
/// demand via computed properties below.
final class MultiBlendGroup: Model, @unchecked Sendable {
    static let schema = "multiblend_groups"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "order_index")
    var orderIndex: Int

    @Field(key: "formula_codes_json")
    var formulaCodesJSON: String

    @Field(key: "production_tons_json")
    var productionTonsJSON: String

    @Field(key: "monthly_ing_limits_json")
    var monthlyIngLimitsJSON: String

    @Field(key: "production_snapshot_json")
    var productionSnapshotJSON: String

    @Field(key: "production_snapshot_tons_json")
    var productionSnapshotTonsJSON: String

    @OptionalField(key: "production_snapshot_at")
    var productionSnapshotAt: Date?

    @Field(key: "stok_yok_codes_json")
    var stokYokCodesJSON: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Field(key: "version")
    var version: Int

    init() {}

    init(id: UUID? = nil, name: String, orderIndex: Int = 0) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.formulaCodesJSON = "[]"
        self.productionTonsJSON = "{}"
        self.monthlyIngLimitsJSON = "{}"
        self.productionSnapshotJSON = "{}"
        self.productionSnapshotTonsJSON = "{}"
        self.stokYokCodesJSON = "[]"
        self.version = 1
    }

    var formulaCodes: [String] {
        get { JSONCoding.decode([String].self, from: formulaCodesJSON) ?? [] }
        set { formulaCodesJSON = JSONCoding.encode(newValue) }
    }

    var productionTons: [String: Double] {
        get { JSONCoding.decode([String: Double].self, from: productionTonsJSON) ?? [:] }
        set { productionTonsJSON = JSONCoding.encode(newValue) }
    }

    var monthlyIngLimits: [String: MonthlyIngLimit] {
        get { JSONCoding.decode([String: MonthlyIngLimit].self, from: monthlyIngLimitsJSON) ?? [:] }
        set { monthlyIngLimitsJSON = JSONCoding.encode(newValue) }
    }

    var productionSnapshot: [String: Double] {
        get { JSONCoding.decode([String: Double].self, from: productionSnapshotJSON) ?? [:] }
        set { productionSnapshotJSON = JSONCoding.encode(newValue) }
    }

    var productionSnapshotTons: [String: Double] {
        get { JSONCoding.decode([String: Double].self, from: productionSnapshotTonsJSON) ?? [:] }
        set { productionSnapshotTonsJSON = JSONCoding.encode(newValue) }
    }

    var stokYokCodes: [String] {
        get { JSONCoding.decode([String].self, from: stokYokCodesJSON) ?? [] }
        set { stokYokCodesJSON = JSONCoding.encode(newValue) }
    }
}

struct MonthlyIngLimit: Codable {
    var maxTons: Double?
    var minTons: Double?
}
