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

    private static let ckContainerID = "iCloud.com.rehabasmaci.BORNOTOM"

    // CloudKit'te sync'lenen ana modeller
    private static let ckModels: [any PersistentModel.Type] = [
        FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
        FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self
    ]

    // Local-only modeller (CloudKit sync yok)
    private static let localModels: [any PersistentModel.Type] = [
        FormulaCostEntry.self, ProductPricingMeta.self, PriceListArchive.self
    ]

    private static func makeContainer() -> ModelContainer {
        let fullSchema = Schema([
            FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
            FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self,
            FormulaCostEntry.self, ProductPricingMeta.self, PriceListArchive.self
        ])

        // 1. CloudKit + Local (tercih edilen)
        do {
            let ckConfig = ModelConfiguration(
                "ckStore",
                schema: Schema(ckModels),
                cloudKitDatabase: .private(ckContainerID)
            )
            let localConfig = ModelConfiguration(
                "localStore",
                schema: Schema(localModels),
                cloudKitDatabase: .none
            )
            let c = try ModelContainer(for: fullSchema, configurations: [ckConfig, localConfig])
            print("✅ BORN: CloudKit aktif + local store — veri senkronize ediliyor")
            return c
        } catch {
            print("❌ BORN: CloudKit+local hatası: \(error)")
        }

        // 2. CloudKit tek config
        do {
            let c = try ModelContainer(
                for: FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
                    FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self,
                    FormulaCostEntry.self, ProductPricingMeta.self, PriceListArchive.self,
                configurations: ModelConfiguration(cloudKitDatabase: .private(ckContainerID))
            )
            print("✅ BORN: CloudKit container aktif")
            return c
        } catch {
            print("❌ BORN: CloudKit hatası: \(error)")
        }

        // 3. Yerel store
        do {
            let c = try ModelContainer(
                for: FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
                    FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self,
                    FormulaCostEntry.self, ProductPricingMeta.self, PriceListArchive.self,
                configurations: ModelConfiguration(cloudKitDatabase: .none)
            )
            print("⚠️ BORN: Yerel store — sync YOK")
            return c
        } catch {
            print("❌ BORN: Yerel store hatası: \(error)")
        }

        // 4. Son çare
        return try! ModelContainer(
            for: FeedIngredient.self, PriceHistoryEntry.self, BlendFormula.self,
                FormulaTemplate.self, MultiBlendGroup.self, SendRecord.self,
                FormulaCostEntry.self, ProductPricingMeta.self,
            configurations: ModelConfiguration(cloudKitDatabase: .none)
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
