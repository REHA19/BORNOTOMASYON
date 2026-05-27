import Foundation
import Combine

@MainActor
final class MaterialListViewModel: ObservableObject {

    // MARK: - Published — UI State

    @Published var filteredMaterials: [Material] = []
    @Published var searchText: String = ""
    @Published var sortOption: SortOption = SortOption(rawValue: UserDefaults.standard.string(forKey: "lastSortOption") ?? "") ?? .nameAscending
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isOffline: Bool = false
    @Published var cacheDate: Date? = nil

    /// Son snapshot'a göre delta
    @Published var snapshotDeltas: [Int: Double] = [:]
    @Published var lastSnapshotDate: Date? = nil

    /// Geçen ay üretimine göre tahmini kaç günlük stok (materialCode → gün)
    @Published var stockDays: [String: Double] = [:]
    @Published var isDaysLoading = false

    // MARK: - Published — POST Filtresi

    @Published var filterRequest: StockRequest = StockRequest()
    @Published var isFilterActive: Bool = false

    // MARK: - Private

    private var allMaterials: [Material] = []
    nonisolated(unsafe) private let service: MaterialServiceProtocol
    nonisolated(unsafe) private let daysService = StockDaysService()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Sort Options

    enum SortOption: String, CaseIterable, Identifiable {
        case nameAscending  = "Ad (A-Z)"
        case nameDescending = "Ad (Z-A)"
        case stockHighest   = "En Yüksek Stok"
        case stockLowest    = "En Düşük Stok"

        var id: String { rawValue }
    }

    // MARK: - Init

    nonisolated init(service: MaterialServiceProtocol = MaterialService()) {
        self.service = service
    }

    // MARK: - Intent

    func onAppear() async {
        if cancellables.isEmpty { bindFilters() }
        guard allMaterials.isEmpty else { return }
        await loadWithGET()
    }

    /// Filtresiz yenileme — GET
    func refresh() async {
        await loadWithGET()
    }

    /// Filtreli yenileme — POST
    func applyFilter(_ request: StockRequest) async {
        filterRequest = request
        isFilterActive = true
        await loadWithPOST(request: request)
    }

    /// Filtreyi kaldır, GET'e dön
    func clearFilter() async {
        filterRequest = StockRequest()
        isFilterActive = false
        await loadWithGET()
    }

    // MARK: - Private — Network

    private func loadWithGET() async {
        await load { [weak self] in
            try await self?.service.fetchMaterials() ?? []
        }
    }

    private func loadWithPOST(request: StockRequest) async {
        await load { [weak self] in
            try await self?.service.fetchMaterials(request: request) ?? []
        }
    }

    private func load(fetch: @escaping () async throws -> [Material]) async {
        isLoading    = true
        errorMessage = nil
        isOffline    = false
        do {
            allMaterials = try await fetch()
            // Başarılı → önbelleğe yaz
            AppCache.shared.save(allMaterials, key: .materials)
            computeSnapshotDeltas()
            applyFilters()
            Task { await computeStockDays() }
        } catch {
            // Sunucu kapalı → önbellekten yükle
            if let cached = AppCache.shared.load([Material].self, key: .materials), !cached.value.isEmpty {
                allMaterials = cached.value
                cacheDate    = cached.savedAt
                isOffline    = true
                computeSnapshotDeltas()
                applyFilters()
                // stockDays önbelleği
                if let cachedDays = AppCache.shared.load([String: Double].self, key: .stockDays) {
                    stockDays = cachedDays.value
                } else {
                    Task { await computeStockDays() }
                }
            } else {
                errorMessage = error.localizedDescription
                allMaterials = []
                filteredMaterials = []
            }
        }
        isLoading = false
    }

    private func computeStockDays() async {
        guard !allMaterials.isEmpty else { return }
        isDaysLoading = true
        let rates = await daysService.calculateDailyRates(currentStock: allMaterials)
        stockDays = daysService.daysRemaining(stock: allMaterials, dailyRates: rates)
        // Önbelleğe yaz
        AppCache.shared.save(stockDays, key: .stockDays)
        isDaysLoading = false
    }

    private func computeSnapshotDeltas() {
        guard let lastSnapshot = SnapshotStore.shared.load().last else {
            snapshotDeltas = [:]
            lastSnapshotDate = nil
            return
        }
        lastSnapshotDate = lastSnapshot.date
        let snapMap = Dictionary(uniqueKeysWithValues: lastSnapshot.materials.map { ($0.id, $0.netStock) })
        var deltas: [Int: Double] = [:]
        for material in allMaterials {
            if let snapStock = snapMap[material.id] {
                let delta = snapStock - material.netStock
                if abs(delta) > 0.05 { deltas[material.id] = delta }
            }
        }
        snapshotDeltas = deltas
    }

    // MARK: - Private — Filtering & Sorting

    private func bindFilters() {
        Publishers.CombineLatest($searchText, $sortOption)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _, sort in
                UserDefaults.standard.set(sort.rawValue, forKey: "lastSortOption")
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }

    private func applyFilters() {
        var result = allMaterials

        if !searchText.isEmpty {
            result = result.filter {
                $0.materialName.localizedCaseInsensitiveContains(searchText) ||
                $0.materialCode.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOption {
        case .nameAscending:  result.sort { $0.materialName < $1.materialName }
        case .nameDescending: result.sort { $0.materialName > $1.materialName }
        case .stockHighest:   result.sort { $0.netStock > $1.netStock }
        case .stockLowest:    result.sort { $0.netStock < $1.netStock }
        }

        filteredMaterials = result
    }
}
