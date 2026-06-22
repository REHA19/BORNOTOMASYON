import Fluent
import Vapor
import JWT
import JWTKit

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Field(key: "display_name")
    var displayName: String

    @Field(key: "is_admin")
    var isAdmin: Bool

    @Field(key: "is_active")
    var isActive: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, username: String, passwordHash: String, displayName: String, isAdmin: Bool = false, isActive: Bool = true) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
        self.displayName = displayName
        self.isAdmin = isAdmin
        self.isActive = isActive
    }
}

extension User: ModelAuthenticatable {
    static let usernameKey = \User.$username
    static let passwordHashKey = \User.$passwordHash

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}

struct UserPayload: JWTPayload, Authenticatable {
    var userId: UUID
    var username: String
    var isAdmin: Bool
    var exp: ExpirationClaim

    func verify(using signer: JWTSigner) throws {
        try self.exp.verifyNotExpired()
    }
}

struct UserPublic: Content {
    let id: UUID
    let username: String
    let displayName: String
    let isAdmin: Bool

    init(_ user: User) {
        self.id = user.id!
        self.username = user.username
        self.displayName = user.displayName
        self.isAdmin = user.isAdmin
    }
}
