import Foundation
import Combine

@MainActor
final class PurchaseAlertViewModel: ObservableObject {

    // MARK: - Published

    @Published var alertGroups: [(urgency: PurchaseUrgency, items: [MaterialMarketInfo])] = []
    @Published var isLoading   = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var isOffline:   Bool = false
    @Published var cacheDate:   Date? = nil

    // MARK: - Private

    nonisolated(unsafe) private let materialService = MaterialService()
    nonisolated(unsafe) private let daysService     = StockDaysService()

    // MARK: - Intent

    func onAppear() async {
        guard alertGroups.isEmpty else { return }
        await load()
    }

    func refresh() async { await load() }

    // MARK: - Load

    private func load() async {
        isLoading    = true
        errorMessage = nil
        isOffline    = false

        var materials: [Material] = []
        var days:      [String: Double] = [:]

        do {
            materials = try await materialService.fetchMaterials()
            AppCache.shared.save(materials, key: .materials)

            let rates = await daysService.calculateDailyRates(currentStock: materials)
            days      = daysService.daysRemaining(stock: materials, dailyRates: rates)
            AppCache.shared.save(days, key: .stockDays)

        } catch {
            // Sunucu kapalı → önbellekten yükle
            if let cachedMat  = AppCache.shared.load([Material].self,       key: .materials),
               let cachedDays = AppCache.shared.load([String: Double].self, key: .stockDays) {
                materials  = cachedMat.value
                days       = cachedDays.value
                cacheDate  = cachedMat.savedAt
                isOffline  = true
            } else {
                errorMessage = "Sunucu kapalı ve önbellek bulunamadı."
                isLoading    = false
                return
            }
        }

        // Alert grupları oluştur
        let infos: [MaterialMarketInfo] = materials.compactMap { mat in
            let d       = days[mat.materialCode]
            let urgency = PurchaseUrgency.from(days: d)
            guard urgency <= .planning else { return nil }
            return MaterialMarketInfo(id: mat.materialCode, material: mat, stockDays: d, commodity: nil)
        }.sorted { lhs, rhs in
            lhs.urgency != rhs.urgency
                ? lhs.urgency < rhs.urgency
                : (lhs.stockDays ?? 999) < (rhs.stockDays ?? 999)
        }

        let grouped  = Dictionary(grouping: infos) { $0.urgency }
        let order: [PurchaseUrgency] = [.critical, .warning, .planning]
        alertGroups  = order.compactMap { u in
            guard let items = grouped[u], !items.isEmpty else { return nil }
            return (urgency: u, items: items)
        }

        lastUpdated = Date()

        // Kritik/uyarı için bildirim planla
        let urgent = infos.filter { $0.urgency <= .warning }
        await NotificationManager.shared.schedulePurchaseAlerts(urgentItems: urgent)

        isLoading = false
    }
}
