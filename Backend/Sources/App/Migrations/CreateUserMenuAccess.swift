import Fluent

struct CreateUserMenuAccess: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("user_menu_access")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("menu_key", .string, .required)
            .field("can_view", .bool, .required, .sql(.default(true)))
            .field("can_edit", .bool, .required, .sql(.default(true)))
            .unique(on: "user_id", "menu_key")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_menu_access").delete()
    }
}
