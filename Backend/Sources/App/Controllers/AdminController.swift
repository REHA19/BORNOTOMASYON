import Fluent
import Vapor

struct CreateUserRequest: Content {
    let username: String
    let password: String
    let displayName: String
    let isAdmin: Bool
}

struct SetMenuAccessRequest: Content {
    let menuKey: String
    let canView: Bool
    let canEdit: Bool
}

struct UserMenuAccessPublic: Content {
    let menuKey: String
    let canView: Bool
    let canEdit: Bool

    init(_ access: UserMenuAccess) {
        self.menuKey = access.menuKey
        self.canView = access.canView
        self.canEdit = access.canEdit
    }
}

/// Admin-only: user management + the per-user menu permission matrix (Plan §2).
struct AdminController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let admin = routes.grouped("api", "admin")
            .grouped(JWTBearerAuthenticator())
            .grouped(AdminOnlyMiddleware())

        admin.get("users", use: listUsers)
        admin.post("users", use: createUser)
        admin.get("menu-items", use: listMenuItems)
        admin.get("users", ":userID", "menu-access", use: getMenuAccess)
        admin.put("users", ":userID", "menu-access", use: setMenuAccess)
    }

    @Sendable
    func listUsers(req: Request) async throws -> [UserPublic] {
        try await User.query(on: req.db).all().map(UserPublic.init)
    }

    @Sendable
    func createUser(req: Request) async throws -> UserPublic {
        let body = try req.content.decode(CreateUserRequest.self)
        let hash = try Bcrypt.hash(body.password)
        let user = User(username: body.username, passwordHash: hash, displayName: body.displayName, isAdmin: body.isAdmin)
        try await user.save(on: req.db)
        return UserPublic(user)
    }

    @Sendable
    func listMenuItems(req: Request) async throws -> [MenuItem] {
        try await MenuItem.query(on: req.db).sort(\.$orderIndex).all()
    }

    @Sendable
    func getMenuAccess(req: Request) async throws -> [UserMenuAccessPublic] {
        guard let userID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await UserMenuAccess.query(on: req.db)
            .filter(\.$user.$id == userID)
            .all()
            .map(UserMenuAccessPublic.init)
    }

    @Sendable
    func setMenuAccess(req: Request) async throws -> UserMenuAccessPublic {
        guard let userID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(SetMenuAccessRequest.self)

        let existing = try await UserMenuAccess.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$menuKey == body.menuKey)
            .first()

        let access = existing ?? UserMenuAccess(userID: userID, menuKey: body.menuKey)
        access.canView = body.canView
        access.canEdit = body.canEdit
        try await access.save(on: req.db)
        return UserMenuAccessPublic(access)
    }
}

struct AdminOnlyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let payload = try request.auth.require(UserPayload.self)
        guard payload.isAdmin else {
            throw Abort(.forbidden, reason: "Bu işlem için admin yetkisi gerekli")
        }
        return try await next.respond(to: request)
    }
}
