import Fluent
import Vapor

/// Gates a route group behind a specific menu key from the per-user permission matrix.
/// Admins bypass the check. Plan §2: backend is the real enforcement point, the
/// frontend only hides nav items it doesn't have access to as a UX nicety.
struct MenuAccessMiddleware: AsyncMiddleware {
    let menuKey: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let payload = try request.auth.require(UserPayload.self)

        if payload.isAdmin {
            return try await next.respond(to: request)
        }

        let access = try await UserMenuAccess.query(on: request.db)
            .filter(\.$user.$id == payload.userId)
            .filter(\.$menuKey == menuKey)
            .first()

        guard let access, access.canView else {
            throw Abort(.forbidden, reason: "Bu menü için erişim izniniz yok: \(menuKey)")
        }

        return try await next.respond(to: request)
    }
}
