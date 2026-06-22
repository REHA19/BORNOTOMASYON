import Fluent

struct CreateBlendFormula: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("blend_formulas")
            .id()
            .field("code", .string, .required)
            .unique(on: "code")
            .field("name", .string, .required)
            .field("total_kg", .double, .required, .sql(.default(1000)))
            .field("recorded_cost_tl", .double, .required, .sql(.default(0)))
            .field("ingredients_json", .string, .required, .sql(.default("[]")))
            .field("constraints_json", .string, .required, .sql(.default("[]")))
            .field("last_solve_json", .string)
            .field("combinations_json", .string, .required, .sql(.default("[]")))
            .field("version", .int, .required, .sql(.default(1)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("blend_formulas").delete()
    }
}
