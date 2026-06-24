import Fluent
import Vapor

struct MultiBlendFormulaEntry: Content {
    let code: String
    let name: String
    let tons: Double
    let liveCostPerTon: Double?
    let snapshotCostPerTon: Double?
    let snapshotTons: Double?
}

struct MultiBlendGroupDTO: Content {
    let id: UUID
    let name: String
    let orderIndex: Int
    let version: Int
    let productionSnapshotAt: Date?
    let stokYokCodes: [String]
    let monthlyIngLimits: [String: MonthlyIngLimit]
    let entries: [MultiBlendFormulaEntry]

    init(_ group: MultiBlendGroup, formulas: [BlendFormula]) {
        self.id = group.id!
        self.name = group.name
        self.orderIndex = group.orderIndex
        self.version = group.version
        self.productionSnapshotAt = group.productionSnapshotAt
        self.stokYokCodes = group.stokYokCodes
        self.monthlyIngLimits = group.monthlyIngLimits

        let formulasByCode = Dictionary(uniqueKeysWithValues: formulas.map { ($0.code, $0) })
        let tonsByCode = group.productionTons
        let snapshotCost = group.productionSnapshot
        let snapshotTons = group.productionSnapshotTons

        self.entries = group.formulaCodes.map { code in
            let formula = formulasByCode[code]
            return MultiBlendFormulaEntry(
                code: code,
                name: formula?.name ?? code,
                tons: tonsByCode[code] ?? 0,
                liveCostPerTon: formula?.lastSolve?.costPerTon,
                snapshotCostPerTon: snapshotCost[code],
                snapshotTons: snapshotTons[code]
            )
        }
    }
}

struct UpdateMultiBlendRequest: Content {
    let version: Int
    let formulaCodes: [String]
    let productionTons: [String: Double]
    let monthlyIngLimits: [String: MonthlyIngLimit]?
    let stokYokCodes: [String]?
}

/// CRUD + production snapshot locking for multiblend_groups (Plan §2 Faz 2).
/// "Save to production" mirrors the iOS app's behavior: locks in the formulas'
/// *current* solved cost/tons so later re-solves don't retroactively change
/// numbers already used for a production run.
struct MultiBlendController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let groups = routes.grouped("api", "multiblend")
            .grouped(JWTBearerAuthenticator())
            .grouped(MenuAccessMiddleware(menuKey: "multiblend"))

        groups.get(use: list)
        groups.post(use: create)
        groups.get(":groupID", use: detail)
        groups.put(":groupID", use: update)
        groups.post(":groupID", "save-production", use: saveProduction)
    }

    @Sendable
    func list(req: Request) async throws -> [MultiBlendGroupDTO] {
        let groups = try await MultiBlendGroup.query(on: req.db).sort(\.$orderIndex).all()
        var result: [MultiBlendGroupDTO] = []
        for group in groups {
            result.append(try await dto(for: group, db: req.db))
        }
        return result
    }

    struct CreateMultiBlendRequest: Content {
        let name: String
    }

    @Sendable
    func create(req: Request) async throws -> MultiBlendGroupDTO {
        let body = try req.content.decode(CreateMultiBlendRequest.self)
        let count = try await MultiBlendGroup.query(on: req.db).count()
        let group = MultiBlendGroup(name: body.name, orderIndex: count)
        try await group.save(on: req.db)
        return try await dto(for: group, db: req.db)
    }

    @Sendable
    func detail(req: Request) async throws -> MultiBlendGroupDTO {
        guard let group = try await find(req: req) else { throw Abort(.notFound) }
        return try await dto(for: group, db: req.db)
    }

    @Sendable
    func update(req: Request) async throws -> MultiBlendGroupDTO {
        guard let group = try await find(req: req) else { throw Abort(.notFound) }
        let body = try req.content.decode(UpdateMultiBlendRequest.self)

        guard body.version == group.version else {
            throw Abort(.conflict, reason: "Grup başka biri tarafından güncellendi, lütfen sayfayı yenileyin.")
        }

        group.formulaCodes = body.formulaCodes
        group.productionTons = body.productionTons
        if let limits = body.monthlyIngLimits { group.monthlyIngLimits = limits }
        if let stokYok = body.stokYokCodes { group.stokYokCodes = stokYok }
        group.version += 1
        try await group.save(on: req.db)
        return try await dto(for: group, db: req.db)
    }

    @Sendable
    func saveProduction(req: Request) async throws -> MultiBlendGroupDTO {
        guard let group = try await find(req: req) else { throw Abort(.notFound) }

        let formulas = try await BlendFormula.query(on: req.db)
            .filter(\.$code ~~ group.formulaCodes)
            .all()
        let formulasByCode = Dictionary(uniqueKeysWithValues: formulas.map { ($0.code, $0) })
        let tons = group.productionTons

        var snapshotCost: [String: Double] = [:]
        var snapshotTons: [String: Double] = [:]
        for code in group.formulaCodes {
            guard let cost = formulasByCode[code]?.lastSolve?.costPerTon else { continue }
            snapshotCost[code] = cost
            snapshotTons[code] = tons[code] ?? 0
        }

        group.productionSnapshot = snapshotCost
        group.productionSnapshotTons = snapshotTons
        group.productionSnapshotAt = Date()
        group.version += 1
        try await group.save(on: req.db)
        return try await dto(for: group, db: req.db)
    }

    private func dto(for group: MultiBlendGroup, db: Database) async throws -> MultiBlendGroupDTO {
        let formulas = try await BlendFormula.query(on: db)
            .filter(\.$code ~~ group.formulaCodes)
            .all()
        return MultiBlendGroupDTO(group, formulas: formulas)
    }

    private func find(req: Request) async throws -> MultiBlendGroup? {
        guard let id = req.parameters.get("groupID", as: UUID.self) else { return nil }
        return try await MultiBlendGroup.find(id, on: req.db)
    }
}
