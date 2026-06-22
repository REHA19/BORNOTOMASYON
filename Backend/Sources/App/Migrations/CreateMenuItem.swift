import Fluent

struct CreateMenuItem: AsyncMigration {
    /// Mirrors the ~19 menu entries from iOS Views/MainTabView.swift, seeded once.
    static let seedKeys: [(key: String, title: String)] = [
        ("hammadde", "Hammaddeler"),
        ("single_blend", "Tek Formül"),
        ("multiblend", "MultiBlend"),
        ("rasyon_aktar", "Rasyon Aktarımı"),
        ("sablonlar", "Şablonlar"),
        ("gonderilen", "Gönderilen Formüller"),
        ("stok", "Stok Raporu"),
        ("hareket", "Araç Hareketleri"),
        ("sarfiyat", "Sarfiyat/Tüketim"),
        ("urt_cetveli", "Üretim Çizelgesi"),
        ("fiyat_listesi", "Fiyat Listesi"),
        ("fiyat_gecmisi", "Fiyat Geçmişi"),
        ("piyasa_analiz", "Piyasa Analizi"),
        ("lp_analizi", "LP Analizi"),
        ("iskonto_analiz", "İskonto Analizi"),
        ("maliyet", "Maliyetlendirme"),
        ("stok_mal", "Stok Maliyeti"),
        ("uyarilar", "Uyarılar/Bildirimler"),
        ("satin_alma", "Satın Alma Uyarıları"),
        ("marka_kategori", "Marka/Kategori Yönetimi"),
        ("ayarlar", "Ayarlar"),
    ]

    func prepare(on database: Database) async throws {
        try await database.schema("menu_items")
            .id()
            .field("key", .string, .required)
            .unique(on: "key")
            .field("title", .string, .required)
            .field("order_index", .int, .required)
            .create()

        for (index, entry) in Self.seedKeys.enumerated() {
            try await MenuItem(key: entry.key, title: entry.title, orderIndex: index).save(on: database)
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema("menu_items").delete()
    }
}
