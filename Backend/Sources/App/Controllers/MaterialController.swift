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

        materials.post("import", use: importText)

        // Any logged-in user can read the nutrient key/displayName/unit list —
        // used to build both the materials form and the formula constraint
        // picker, so it isn't gated behind the "hammadde" menu key specifically.
        routes.grouped("api", "nutrient-defs")
            .grouped(JWTBearerAuthenticator())
            .get(use: nutrientDefs)
    }

    struct ImportRequest: Content {
        let content: String
    }

    struct ImportResult: Content {
        let created: Int
        let updated: Int
        let failed: Int
        let errors: [String]
    }

    /// Column order (after name/code/price) matching the "HAMMADDE...txt" export
    /// format from the factory's reporting tool — same mapping used by the
    /// one-off migration script for Plan §4's initial data import.
    static let importColumnKeys: [String] = [
        "dryMatter", "crudeProtein", "crudeAsh", "crudeFiber", "crudeFat", "starch", "sugar",
        "ndf", "adf", "adl", "nel", "me1xNRC", "tse9610", "mePoultryFixed", "ufl", "ufv",
        "pdie", "pdia", "nfc", "nsc", "availP", "availPChick", "calcium", "phosphorus",
        "magnesium", "potassium", "sodium", "chlorine", "sulfur", "zinc", "manganese",
        "copper", "cobalt", "iron", "selenium", "iodine", "caP", "methionine", "lysine",
        "metCys", "cystine", "linoleicAcid", "dcap", "rdp", "rup", "rupCP", "frakA", "frakB",
        "frakC", "degradationRateB", "solProtein", "tdn", "rdsStarch", "solubleStarch",
        "peletRenk", "peletKalite", "prestKapasite", "negKazanc", "ndcip", "adicp", "paf",
        "totalPhosphorus", "sinMethionine", "sinLysine", "sinMetCys", "sinCystine",
        "tryptophan", "sinTryptophan", "meRuminantFixed", "meRumAlderman", "meRumMaff",
        "mePoultryCC", "mePoultryECNFE", "mePoultryEC", "mePoultryCobb", "arginine",
        "sinArginine", "sinThreonine", "threonine", "leucine", "sinLeucine", "isoleucine",
        "sinIsoleucine", "valine", "sinValine", "phenylalanin", "sinPhenylalanin", "phenyTyr",
        "glycine", "histidine", "sinHistidine", "pdin", "tyrosine", "serine", "proline",
        "alanine", "asparticAcid", "glutamicAcid", "glySer", "linolenicAcid", "arachidonicAcid",
        "choline", "lauricAcid", "myristicAcid", "palmiticAcid", "palmoleicAcid", "stearicAcid",
        "oleicAcid", "unsatFattyAcid", "satFattyAcid", "freeFat", "totalFattyAcid", "metLys",
        "mCLys", "argLys", "threLys", "leuLys", "valLys", "trpLys", "nfe", "sinMethCoeff",
        "sinLysCoeff", "sinCysCoeff", "sinArgCoeff", "sinThrCoeff", "sinLeuCoeff",
        "sinIsoCoeff", "sinValCoeff", "sinTryCoeff", "sinPheCoeff", "sinHisCoeff",
        "aldermanCoeff", "maffCoeff", "ccCoeff", "ecNFECoeff", "ecCoeff", "cobbCoeff",
        "slowStarch", "solStarchPct", "bypassStarch", "organicMatter", "maffME",
    ]

    private static func parseTurkishNumber(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let normalized = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    @Sendable
    func importText(req: Request) async throws -> ImportResult {
        let body = try req.content.decode(ImportRequest.self)
        let lines = body.content.split(separator: "\n", omittingEmptySubsequences: true)

        var created = 0
        var updated = 0
        var failed = 0
        var errors: [String] = []

        for line in lines.dropFirst() {
            let cols = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\t")
            guard cols.count >= 3 else { continue }
            let name = cols[0].trimmingCharacters(in: .whitespaces)
            let code = cols[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !code.isEmpty else { continue }

            do {
                let existing = try await FeedIngredient.query(on: req.db).filter(\.$code == code).first()
                let material = existing ?? FeedIngredient(code: code, name: name, sourceFile: "import")
                material.name = name
                material.priceTL = Self.parseTurkishNumber(cols[2])

                for (i, key) in Self.importColumnKeys.enumerated() {
                    let colIndex = 3 + i
                    guard colIndex < cols.count, let value = Self.parseTurkishNumber(cols[colIndex]) else { continue }
                    material.setNutrient(key: key, value: value)
                }

                if existing == nil {
                    try await material.save(on: req.db)
                    created += 1
                } else {
                    material.version += 1
                    try await material.save(on: req.db)
                    updated += 1
                }
            } catch {
                failed += 1
                if errors.count < 20 {
                    errors.append("\(code) \(name): \(error.localizedDescription)")
                }
            }
        }

        return ImportResult(created: created, updated: updated, failed: failed, errors: errors)
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
