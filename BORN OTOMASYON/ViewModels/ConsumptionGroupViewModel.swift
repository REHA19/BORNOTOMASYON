import Foundation
import Combine

@MainActor
final class ConsumptionGroupViewModel: ObservableObject {

    // MARK: - Filtre

    @Published var date1: Date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    @Published var date2: Date = .now
    @Published var materialType: Int = 1   // 1 = Hammadde, 2 = Yem

    // MARK: - UI State

    @Published var items: [ConsumptionGroupModel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Hesaplamalar

    var totalPlan:  Double { items.reduce(0) { $0 + $1.planAmount } }
    var totalReal:  Double { items.reduce(0) { $0 + $1.realAmount } }
    var totalDiff:  Double { items.reduce(0) { $0 + $1.diff } }

    var overItems:  [ConsumptionGroupModel] { items.filter { $0.diff > 0 } }   // Fazla tüketim
    var underItems: [ConsumptionGroupModel] { items.filter { $0.diff < 0 } }   // Eksik tüketim
    var onTarget:   [ConsumptionGroupModel] { items.filter { $0.diff == 0 } }  // Plana uygun

    // MARK: - Private

    private let service: ConsumptionGroupServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    @MainActor
    init(service: ConsumptionGroupServiceProtocol = ConsumptionGroupService()) {
        self.service = service
    }

    // MARK: - Intent

    func onAppear() async {
        Publishers.CombineLatest3($date1, $date2, $materialType)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _, _, _ in Task { await self?.fetch() } }
            .store(in: &cancellables)
        await fetch()
    }

    func refresh() async { await fetch() }

    // MARK: - Private

    private func fetch() async {
        print("🔥 fetch başladı \(date1) / \(date2) / type:\(materialType)")
        isLoading = true
        errorMessage = nil

        let filter = ConsumptionGroupFilter(date1: date1, date2: date2, materialType: materialType)

        do {
            let result = try await service.fetchConsumption(filter: filter)
            print("🔥 gelen kayıt: \(result.count)")
            items = result.sorted { abs($0.diff) > abs($1.diff) }
        } catch {
            print("🔥 HATA: \(error)")
            errorMessage = error.localizedDescription
            items = []
        }

        isLoading = false
    }
}
