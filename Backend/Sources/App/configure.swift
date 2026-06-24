import Vapor
import Fluent
import FluentPostgresDriver
import JWT

public func configure(_ app: Application) async throws {
    try app.databases.use(.postgres(
        url: Environment.get("DATABASE_URL") ?? "postgres://vapor:vapor@localhost:5432/born_otomasyon"
    ), as: .psql)

    app.migrations.add(CreateUser())
    app.migrations.add(CreateMenuItem())
    app.migrations.add(CreateUserMenuAccess())
    app.migrations.add(CreateFeedIngredient())
    app.migrations.add(CreateBlendFormula())
    app.migrations.add(CreateMultiBlendGroup())
    app.migrations.add(SeedAdminUser())

    let jwtSecret = Environment.get("JWT_SECRET") ?? "change-me-in-production"
    app.jwt.signers.use(.hs256(key: jwtSecret))

    if app.environment != .testing {
        try await app.autoMigrate()
    }

    try routes(app)
}
