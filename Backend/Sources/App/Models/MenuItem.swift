import Fluent
import Vapor

/// Mirrors the menu keys in iOS MainTabView.swift — kept as a stable string key,
/// not an enum, so new menus can be added without a migration.
final class MenuItem: Model, Content, @unchecked Sendable {
    static let schema = "menu_items"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "key")
    var key: String

    @Field(key: "title")
    var title: String

    @Field(key: "order_index")
    var orderIndex: Int

    init() {}

    init(id: UUID? = nil, key: String, title: String, orderIndex: Int) {
        self.id = id
        self.key = key
        self.title = title
        self.orderIndex = orderIndex
    }
}

final class UserMenuAccess: Model, Content, @unchecked Sendable {
    static let schema = "user_menu_access"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "menu_key")
    var menuKey: String

    @Field(key: "can_view")
    var canView: Bool

    @Field(key: "can_edit")
    var canEdit: Bool

    init() {}

    init(id: UUID? = nil, userID: User.IDValue, menuKey: String, canView: Bool = true, canEdit: Bool = true) {
        self.id = id
        self.$user.id = userID
        self.menuKey = menuKey
        self.canView = canView
        self.canEdit = canEdit
    }
}
