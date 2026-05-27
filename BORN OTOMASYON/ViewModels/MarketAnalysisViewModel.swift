import Foundation
import Combine

@MainActor
final class MarketAnalysisViewModel: ObservableObject {

    // MARK: - Published

    @Published var commodityPrices:    [String: CommodityPrice] = [:]
    @Published var usdTry:             Double?
    @Published var marketInfos:        [MaterialMarketInfo] = []
    @Published var isLoadingStock      = false
    @Published var isOffline:          Bool = false
    @Published var cacheDate:          Date? = nil
    @Published var aiAnalysis:         String = ""
    @Published var isLoadingAI         = false
    @Published var lastUpdated:        Date?
    @Published var hasAlphaVantageKey: Bool = false
    @Published var hasClaudeKey:       Bool = false

    // MARK: - Services

    private let materialService  = MaterialService()
    private let daysService      = StockDaysService()
    private let commodityService = CommodityPriceService()
    private let aiService        = AIAnalysisService()
    private let fxService        = ExchangeRateService()

    // MARK: - API keys

    var alphaVantageKey: String {
        get { UserDefaults.standard.string(forKey: "alphaVantageKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "alphaVantageKey"); refreshKeyStatus() }
    }

    var claudeKey: String {
        get { UserDefaults.standard.string(forKey: "claudeKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "claudeKey"); refreshKeyStatus() }
    }

    init() {
        refreshKeyStatus()
        if let cached = AppCache.shared.load([String: CommodityPrice].self, key: .commodityPrices) {
            commodityPrices = cached.value
        }
        if let cached = AppCache.shared.load(Double.self, key: .usdTry) {
            usdTry = cached.value
        }
        if let cached = AppCache.shared.load(String.self, key: .aiAnalysis) {
            aiAnalysis = cached.value
        }
    }

    func refreshKeyStatus() {
        hasAlphaVantageKey = !alphaVantageKey.isEmpty
        hasClaudeKey       = !claudeKey.isEmpty
    }

    // MARK: - Intent

    func onAppear() async {
        guard marketInfos.isEmpty else { return }
        await loadMarketPricesAndStock()
    }

    func refresh() async {
        await loadMarketPricesAndStock()
    }

    // MARK: - Veri Yükleme

    func loadMarketPricesAndStock() async {
        isLoadingStock = true
        isOffline      = false

        // CBOT fiyatları
        if !alphaVantageKey.isEmpty {
            let fetched = await commodityService.fetchAll(apiKey: alphaVantageKey)
            if !fetched.isEmpty {
                commodityPrices = fetched
                AppCache.shared.save(fetched, key: .commodityPrices)
            } else if let cached = AppCache.shared.load([String: CommodityPrice].self, key: .commodityPrices) {
                commodityPrices = cached.value
            }
        }

        // Döviz kuru
        if let rate = await fxService.fetchUSDTRY() {
            usdTry = rate
            AppCache.shared.save(rate, key: .usdTry)
        } else if let cached = AppCache.shared.load(Double.self, key: .usdTry) {
            usdTry = cached.value
        }

        // Fabrika hammadde verisi
        var materials: [Material] = []
        do {
            materials = try await materialService.fetchMaterials()
            AppCache.shared.save(materials, key: .materials)
        } catch {
            if let cached = AppCache.shared.load([Material].self, key: .materials) {
                materials = cached.value
                cacheDate = cached.savedAt
                isOffline = true
            }
        }

        // Stok günleri
        var days: [String: Double] = [:]
        if !materials.isEmpty {
            let rates = await daysService.calculateDailyRates(currentStock: materials)
            days      = daysService.daysRemaining(stock: materials, dailyRates: rates)
            AppCache.shared.save(days, key: .stockDays)
        } else if let cached = AppCache.shared.load([String: Double].self, key: .stockDays) {
            days = cached.value
        }

        // MarketInfo
        marketInfos = materials.compactMap { mat in
            let d      = days[mat.materialCode]
            let mapInf = CommodityPriceService.mapping(for: mat.materialName)
            let com    = mapInf.flatMap { commodityPrices[$0.cbotSymbol] }
            guard d != nil || com != nil else { return nil }
            return MaterialMarketInfo(id: mat.materialCode, material: mat, stockDays: d, commodity: com)
        }.sorted { lhs, rhs in
            lhs.urgency != rhs.urgency
                ? lhs.urgency < rhs.urgency
                : (lhs.stockDays ?? 999) < (rhs.stockDays ?? 999)
        }

        isLoadingStock = false
        lastUpdated    = Date()
    }

    // MARK: - AI Analizi

    func runAIAnalysis() async {
        guard !marketInfos.isEmpty else { return }
        isLoadingAI = true
        let ctx = MarketContext(
            marketInfos:     marketInfos,
            commodities:     commodityPrices,
            usdTry:          usdTry,
            hammersmithNews: "",
            grainsReport:    ""
        )
        aiAnalysis = await aiService.analyze(context: ctx, apiKey: claudeKey)
        AppCache.shared.save(aiAnalysis, key: .aiAnalysis)
        isLoadingAI = false
    }
}
