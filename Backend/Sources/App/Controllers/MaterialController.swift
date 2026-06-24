import Fluent
import Vapor

/// CRUD for feed_ingredients (Plan §1 Faz 1: hammadde kütüphanesi).
/// Update uses delete+recreate-with-same-id instead of field-by-field copy —
/// FeedIngredient has ~142 nutrient fields, too many to hand-write a merge.
struct MaterialController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let materials = routes.grouped("api", "materials")
            .grouped(JWTBearerAuthenticator())
            .grouped(MenuAccessMiddleware(menuKey: "hammadde"))

        materials.get(use: list)
        materials.get(":materialID", use: detail)
        materials.post(use: create)
        materials.put(":materialID", use: update)
        materials.delete(":materialID", use: delete)

        // Any logged-in user can read the nutrient key/displayName/unit list —
        // used to build both the materials form and the formula constraint
        // picker, so it isn't gated behind the "hammadde" menu key specifically.
        routes.grouped("api", "nutrient-defs")
            .grouped(JWTBearerAuthenticator())
            .get(use: nutrientDefs)
    }

    @Sendable
    func nutrientDefs(req: Request) async throws -> [NutrientDef] {
        allNutrientDefs
    }

    @Sendable
    func list(req: Request) async throws -> [FeedIngredient] {
        try await FeedIngredient.query(on: req.db).sort(\.$name).all()
    }

    @Sendable
    func detail(req: Request) async throws -> FeedIngredient {
        guard let material = try await find(req: req) else {
            throw Abort(.notFound)
        }
        return material
    }

    @Sendable
    func create(req: Request) async throws -> FeedIngredient {
        let incoming = try req.content.decode(FeedIngredient.self)
        incoming.id = nil
        try await incoming.save(on: req.db)
        return incoming
    }

    @Sendable
    func update(req: Request) async throws -> FeedIngredient {
        guard let id = req.parameters.get("materialID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard try await FeedIngredient.find(id, on: req.db) != nil else {
            throw Abort(.notFound)
        }
        let incoming = try req.content.decode(FeedIngredient.self)
        incoming.id = id

        return try await req.db.transaction { db in
            try await FeedIngredient.query(on: db).filter(\.$id == id).delete()
            try await incoming.create(on: db)
            return incoming
        }
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let material = try await find(req: req) else {
            throw Abort(.notFound)
        }
        try await material.delete(on: req.db)
        return .noContent
    }

    private func find(req: Request) async throws -> FeedIngredient? {
        guard let id = req.parameters.get("materialID", as: UUID.self) else { return nil }
        return try await FeedIngredient.find(id, on: req.db)
    }
}
