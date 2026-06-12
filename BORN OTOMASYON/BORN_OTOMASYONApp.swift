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

    // Tüm modeller — hepsinde CloudKit için default değer zorunlu
    private static let allModels: [any PersistentModel.Type] = [
        FeedIngredient.self,
        PriceHistoryEntry.self,
        BlendFormula.self,
        FormulaTemplate.self,
        MultiBlendGroup.self,
        SendRecord.self,
        ProductPricingMeta.self,
        BrandDefinition.self,
        KategoriTanim.self,
        GiderKalemi.self,
        FormulaCostEntry.self,
        PriceListArchive.self,
        StokManuelKalem.self,
        StokKategori.self,
        StokAylikRapor.self,
    ]

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(allModels)

        // ── 1. CloudKit  ──────────────────────────────────────────────────
        // "ckStore" adını koruyoruz — mevcut CloudKit kaydıyla uyumlu.
        // Yeni modeller ekleniyor: lightweight migration (yeni tablolar).
        do {
            let config = ModelConfiguration(
                "ckStore",
                schema: schema,
                cloudKitDatabase: .private(ckContainerID)
            )
            let c = try ModelContainer(for: schema, configurations: [config])
            print("✅ BORN: CloudKit aktif — iPhone ↔ Mac senkronize")
            return c
        } catch {
            print("❌ BORN: CloudKit hatası: \(error)")
        }

        // ── 2. Yerel (iCloud yoksa) ────────────────────────────────────────
        do {
            let config = ModelConfiguration(
                "localStore",
                schema: schema,
                cloudKitDatabase: .none
            )
            let c = try ModelContainer(for: schema, configurations: [config])
            print("⚠️ BORN: Yerel store — sync YOK")
            return c
        } catch {
            print("❌ BORN: Yerel store hatası: \(error)")
        }

        // ── 3. In-memory (asla crash vermez) ──────────────────────────────
        print("🚨 BORN: In-memory store — veri kalıcı değil")
        return try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
