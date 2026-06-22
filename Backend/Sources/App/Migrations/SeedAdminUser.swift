import Fluent
import Vapor

/// Creates a default admin/admin123 account on first boot so there's something
/// to log in with immediately — change the password via /api/admin/users after
/// first login. Only runs if no users exist yet.
struct SeedAdminUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        let existing = try await User.query(on: database).count()
        guard existing == 0 else { return }

        let hash = try Bcrypt.hash("admin123")
        let admin = User(username: "admin", passwordHash: hash, displayName: "Yönetici", isAdmin: true)
        try await admin.save(on: database)
    }

    func revert(on database: Database) async throws {
        try await User.query(on: database).filter(\.$username == "admin").delete()
    }
}
