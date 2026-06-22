import Fluent
import Vapor
import JWT

struct LoginRequest: Content {
    let username: String
    let password: String
}

struct LoginResponse: Content {
    let token: String
    let user: UserPublic
}

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("api", "auth")
        auth.post("login", use: login)

        let protected = routes.grouped("api", "auth").grouped(JWTBearerAuthenticator())
        protected.get("me", use: me)
    }

    @Sendable
    func login(req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(LoginRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$username == body.username)
            .first()
        else {
            throw Abort(.unauthorized, reason: "Kullanıcı adı veya şifre hatalı")
        }

        guard user.isActive else {
            throw Abort(.forbidden, reason: "Kullanıcı pasif")
        }

        guard try user.verify(password: body.password) else {
            throw Abort(.unauthorized, reason: "Kullanıcı adı veya şifre hatalı")
        }

        let payload = UserPayload(
            userId: try user.requireID(),
            username: user.username,
            isAdmin: user.isAdmin,
            exp: .init(value: Date().addingTimeInterval(60 * 60 * 12))
        )
        let token = try await req.jwt.sign(payload)

        return LoginResponse(token: token, user: UserPublic(user))
    }

    @Sendable
    func me(req: Request) async throws -> UserPublic {
        let payload = try req.auth.require(UserPayload.self)
        guard let user = try await User.find(payload.userId, on: req.db) else {
            throw Abort(.unauthorized)
        }
        return UserPublic(user)
    }
}

/// Verifies the JWT bearer token and authenticates the request as a UserPayload.
struct JWTBearerAuthenticator: AsyncBearerAuthenticator {
    @Sendable
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let payload = try await request.jwt.verify(bearer.token, as: UserPayload.self)
        request.auth.login(payload)
    }
}
