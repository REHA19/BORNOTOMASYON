import Foundation

struct DailyConsumption: Identifiable {
    let id = UUID()
    let date: Date
    let items: [ConsumptionItem]

    var totalConsumed: Double {
        items.filter { $0.consumption > 0 }.reduce(0) { $0 + $1.consumption }
    }

    var consumedItems: [ConsumptionItem] {
        items.filter { $0.consumption > 0 }.sorted { $0.consumption > $1.consumption }
    }
}
