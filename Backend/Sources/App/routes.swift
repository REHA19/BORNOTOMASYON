import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ in "ok" }

    try app.register(collection: AuthController())
    try app.register(collection: AdminController())
    try app.register(collection: FormulaController())
    try app.register(collection: MaterialController())
    try app.register(collection: MultiBlendController())
}
