import Foundation
import Combine

@MainActor
final class ConsumptionViewModel: ObservableObject {

    // MARK: - Published

    @Published var items: [ConsumptionItem] = []
    @Published var dailyConsumptions: [DailyConsumption] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @Published var endDate: Date = .now
    @Published var availableSnapshots: [StockSnapshot] = []

    private let cal = Calendar.current
    private let store = SnapshotStore.shared

    // MARK: - Init

    init() {
        availableSnapshots = store.load()
    }

    func refreshSnapshots() {
        availableSnapshots = store.load()
    }

    // MARK: - Intent

    func calculate() async {
        guard startDate < endDate else {
            errorMessage = "Başlangıç tarihi bitiş tarihinden önce olmalı"
            return
        }

        isLoading = true
        errorMessage = nil
        items = []
        dailyConsumptions = []

        availableSnapshots = store.load()
        let snapshots = store.snapshots(from: startDate, to: endDate)

        guard snapshots.count >= 2 else {
            errorMessage = "Bu tarih aralığında yeterli kayıt yok. Uygulama her açıldığında anlık stok kaydedilir, \(snapshots.count) kayıt mevcut."
            isLoading = false
            return
        }

        // Günlük kırılım
        var daily: [DailyConsumption] = []
        for i in 1..<snapshots.count {
            let dayItems = buildItems(
                opening: snapshots[i - 1].materials,
                closing: snapshots[i].materials
            )
            if !dayItems.isEmpty {
                daily.append(DailyConsumption(date: snapshots[i].date, items: dayItems))
            }
        }
        dailyConsumptions = daily

        // Toplam (ilk → son snapshot)
        items = buildItems(
            opening: snapshots.first!.materials,
            closing: snapshots.last!.materials
        )

        isLoading = false
    }

    // MARK: - Computed

    var totalConsumption: Double {
        items.filter { $0.consumption > 0 }.reduce(0) { $0 + $1.consumption }
    }

    var avgDailyConsumption: Double {
        let days = cal.dateComponents([.day], from: startDate, to: endDate).day ?? 1
        return days > 0 ? totalConsumption / Double(days) : 0
    }

    var consumedItems: [ConsumptionItem] {
        items.filter { $0.consumption > 0 }.sorted { $0.consumption > $1.consumption }
    }

    var replenishedItems: [ConsumptionItem] {
        items.filter { $0.consumption < 0 }.sorted { $0.consumption < $1.consumption }
    }

    // MARK: - Private

    private func buildItems(opening: [Material], closing: [Material]) -> [ConsumptionItem] {
        let closeMap = Dictionary(uniqueKeysWithValues: closing.map { ($0.id, $0.netStock) })
        return opening.compactMap { material in
            let closeStock = closeMap[material.id] ?? material.netStock
            guard material.netStock != closeStock else { return nil }
            return ConsumptionItem(
                id: material.id,
                materialCode: material.materialCode,
                materialName: material.materialName,
                openingStock: material.netStock,
                closingStock: closeStock
            )
        }.sorted { abs($0.consumption) > abs($1.consumption) }
    }
}
