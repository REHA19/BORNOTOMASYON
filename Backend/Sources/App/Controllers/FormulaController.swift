import Fluent
import Vapor

struct UpdateFormulaRequest: Content {
    let version: Int
    let ingredients: [BFIngredient]
    let constraints: [BFConstraint]
    let combinations: [BFCombination]?
}

/// BlendFormula's ingredients/constraints/lastSolve/combinations are computed
/// properties (decoded from *_JSON string columns), so Fluent's synthesized
/// Codable conformance skips them — only the raw JSON string columns would
/// serialize. This DTO exposes the parsed values to API clients instead.
struct FormulaDTO: Content {
    let id: UUID
    let code: String
    let name: String
    let totalKg: Double
    let recordedCostTL: Double
    let version: Int
    let ingredients: [BFIngredient]
    let constraints: [BFConstraint]
    let combinations: [BFCombination]
    let lastSolve: BFSolveResult?

    init(_ formula: BlendFormula) {
        self.id = formula.id!
        self.code = formula.code
        self.name = formula.name
        self.totalKg = formula.totalKg
        self.recordedCostTL = formula.recordedCostTL
        self.version = formula.version
        self.ingredients = formula.ingredients
        self.constraints = formula.constraints
        self.combinations = formula.combinations
        self.lastSolve = formula.lastSolve
    }
}

/// CRUD + solve for blend_formulas — Plan §1 (Faz 1 milestone: materials + formulas + LP solve).
struct FormulaController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let formulas = routes.grouped("api", "formulas")
            .grouped(JWTBearerAuthenticator())
            .grouped(MenuAccessMiddleware(menuKey: "single_blend"))

        formulas.get(use: list)
        formulas.post(use: create)
        formulas.get(":formulaID", use: detail)
        formulas.put(":formulaID", use: update)
        formulas.post(":formulaID", "solve", use: solve)
    }

    @Sendable
    func list(req: Request) async throws -> [FormulaDTO] {
        try await BlendFormula.query(on: req.db).sort(\.$name).all().map(FormulaDTO.init)
    }

    @Sendable
    func detail(req: Request) async throws -> FormulaDTO {
        guard let formula = try await find(req: req) else {
            throw Abort(.notFound)
        }
        return FormulaDTO(formula)
    }

    struct CreateFormulaRequest: Content {
        let code: String
        let name: String
        let totalKg: Double?
    }

    @Sendable
    func create(req: Request) async throws -> FormulaDTO {
        let body = try req.content.decode(CreateFormulaRequest.self)
        let formula = BlendFormula(code: body.code, name: body.name, totalKg: body.totalKg ?? 1000)
        try await formula.save(on: req.db)
        return FormulaDTO(formula)
    }

    /// Optimistic locking (Plan §6): caller must send the version it last read;
    /// a stale version means someone else edited the formula concurrently.
    @Sendable
    func update(req: Request) async throws -> FormulaDTO {
        guard let formula = try await find(req: req) else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(UpdateFormulaRequest.self)

        guard body.version == formula.version else {
            throw Abort(.conflict, reason: "Formül başka biri tarafından güncellendi, lütfen sayfayı yenileyin.")
        }

        formula.ingredients = body.ingredients
        formula.constraints = body.constraints
        if let combos = body.combinations {
            formula.combinations = combos
        }
        formula.version += 1
        try await formula.save(on: req.db)
        return FormulaDTO(formula)
    }

    @Sendable
    func solve(req: Request) async throws -> FormulaDTO {
        guard let formula = try await find(req: req) else {
            throw Abort(.notFound)
        }

        let ingredientCodes = formula.ingredients.filter(\.isActive).map(\.code)
        let library = try await FeedIngredient.query(on: req.db)
            .filter(\.$code ~~ ingredientCodes)
            .filter(\.$isAvailable == true)
            .all()
        let libraryByCode = Dictionary(uniqueKeysWithValues: library.map { ($0.code, $0) })

        let solverIngredients: [SolverIngredient] = formula.ingredients.compactMap { bfIng in
            guard bfIng.isActive, let lib = libraryByCode[bfIng.code] else { return nil }
            let price = bfIng.overridePriceTLPerTon ?? lib.priceTL ?? 0
            let nutrients = Dictionary(uniqueKeysWithValues: allNutrientDefs.compactMap { def -> (String, Double)? in
                guard let v = lib.nutrientValue(forKey: def.key) else { return nil }
                return (def.key, v)
            })
            return SolverIngredient(code: bfIng.code, name: bfIng.name, priceTLPerTon: price,
                                     minPct: bfIng.minPct, maxPct: bfIng.maxPct, nutrients: nutrients)
        }

        let solverConstraints = formula.constraints.filter(\.isActive).map {
            SolverConstraint(key: $0.nutrientKey, minValue: $0.minValue, maxValue: $0.maxValue)
        }

        let solverCombinations = formula.combinations.map {
            SolverCombination(ingredientCodes: $0.ingredientCodes, minPct: $0.minKg, maxPct: $0.maxKg)
        }

        let result = RationSolver.solve(ingredients: solverIngredients, constraints: solverConstraints, combinations: solverCombinations)

        formula.lastSolve = BFSolveResult(
            percentagesByCode: result.percentagesByCode,
            costPerTon: result.costPerTon,
            nutrientValues: result.nutrientValues,
            isFeasible: result.isFeasible,
            message: result.message,
            reducedCosts: result.reducedCosts,
            costRangeIncreases: result.costRangeIncreases,
            shadowPricesMin: result.shadowPricesMin,
            shadowPricesMax: result.shadowPricesMax
        )
        if result.isFeasible {
            formula.recordedCostTL = result.costPerTon
        }
        formula.version += 1
        try await formula.save(on: req.db)
        return FormulaDTO(formula)
    }

    private func find(req: Request) async throws -> BlendFormula? {
        guard let id = req.parameters.get("formulaID", as: UUID.self) else { return nil }
        return try await BlendFormula.find(id, on: req.db)
    }
}
