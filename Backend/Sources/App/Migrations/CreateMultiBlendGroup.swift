import Fluent

struct CreateMultiBlendGroup: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("multiblend_groups")
            .id()
            .field("name", .string, .required)
            .field("order_index", .int, .required, .sql(.default(0)))
            .field("formula_codes_json", .string, .required, .sql(.default("[]")))
            .field("production_tons_json", .string, .required, .sql(.default("{}")))
            .field("monthly_ing_limits_json", .string, .required, .sql(.default("{}")))
            .field("production_snapshot_json", .string, .required, .sql(.default("{}")))
            .field("production_snapshot_tons_json", .string, .required, .sql(.default("{}")))
            .field("production_snapshot_at", .datetime)
            .field("stok_yok_codes_json", .string, .required, .sql(.default("[]")))
            .field("version", .int, .required, .sql(.default(1)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("multiblend_groups").delete()
    }
}
