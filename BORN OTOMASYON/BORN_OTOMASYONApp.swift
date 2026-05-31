import SwiftUI
import SwiftData

@main
struct BornOtomasyonApp: App {

    let container: ModelContainer

    init() {
        Task {
            await NotificationManager.shared.requestAuthorization()
        }
        container = Self.makeContainer()
    }

    @AppStorage("appColorScheme") private var colorSchemeStr: String = "system"

    private var preferredScheme: ColorScheme? {
        switch colorSchemeStr {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .preferredColorScheme(preferredScheme)
        }
        .modelContainer(container)
    }

    // MARK: - Container

    private static func makeContainer() -> ModelContainer {
        // Şema değişikliği sonrası eski store'u tek seferlik temizle
        let resetKey = "swiftdata_reset_v9"
        if !UserDefaults.standard.bool(forKey: resetKey) {
            Self.nukeApplicationSupport()
            UserDefaults.standard.set(true, forKey: resetKey)
        }

        // 1. CloudKit — schema'yı ModelConfiguration'a verme, SwiftData kendisi çıkarsın
        do {
            let c = try ModelContainer(
                for: FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
                    FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self, FormulaCostEntry.self,
                configurations: ModelConfiguration(cloudKitDatabase: .automatic)
            )
            print("✅ BORN: CloudKit container aktif — sync çalışıyor")
            return c
        } catch {
            print("❌ BORN: CloudKit hatası: \(error)")
        }

        // 2. Yerel store
        do {
            let c = try ModelContainer(
                for: FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
                    FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self, FormulaCostEntry.self,
                configurations: ModelConfiguration(cloudKitDatabase: .none)
            )
            print("⚠️ BORN: Yerel store — sync YOK")
            return c
        } catch {
            print("❌ BORN: Yerel store hatası: \(error)")
        }

        // 3. Temizle ve tekrar dene
        Self.nukeApplicationSupport()
        if let c = try? ModelContainer(
            for: FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
                FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self,
            configurations: ModelConfiguration(cloudKitDatabase: .automatic)
        ) { return c }
        return try! ModelContainer(
            for: FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
                FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self
        )
    }

    private static func nukeApplicationSupport() {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        guard let contents = try? fm.contentsOfDirectory(
            at: support, includingPropertiesForKeys: nil, options: []
        ) else { return }
        for url in contents { try? fm.removeItem(at: url) }
    }
}
