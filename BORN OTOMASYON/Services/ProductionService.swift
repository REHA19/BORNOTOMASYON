import Foundation

struct ProductionService {

    private let consumptionService = ConsumptionGroupService()
    private let formulaService     = FormulaDetailService()

    // MARK: - Aylık özet yükle (ürünler hemen, formüller sonra)

    func fetchSummary(month: Date) async throws -> ProductionSummary {
        let (start, end) = monthRange(month)
        let filter = ConsumptionGroupFilter(date1: start, date2: end, materialType: 2)
        let raw = try await consumptionService.fetchConsumption(filter: filter)

        // Aynı ürün birden fazla kez gelebilir — koda göre topla
        var grouped: [String: ProductionEntry] = [:]
        for item in raw {
            if let existing = grouped[item.code] {
                grouped[item.code] = ProductionEntry(
                    id:          existing.id,
                    productCode: existing.productCode,
                    productName: existing.productName,
                    formulaName: existing.formulaName ?? item.formulaName,
                    formulaID:   existing.formulaID   ?? item.formulaID,
                    totalKg:     existing.totalKg + item.realAmount
                )
            } else {
                grouped[item.code] = ProductionEntry(
                    id:          item.code,
                    productCode: item.code,
                    productName: item.name,
                    formulaName: item.formulaName,
                    formulaID:   item.formulaID,
                    totalKg:     item.realAmount
                )
            }
        }

        let entries = grouped.values.sorted { $0.totalKg > $1.totalKg }
        return ProductionSummary(month: month, entries: Array(entries))
    }

    // MARK: - Bir ürün için formül yükle ve ölçekle

    func loadFormula(for entry: ProductionEntry) async -> [ScaledMaterialItem] {
        guard let result = try? await formulaService.fetch(
            formulaID:    entry.formulaID,
            productCode:  entry.productCode,
            fallbackCode: entry.formulaName ?? ""
        ) else { return [] }

        let formulaTotal = result.formula?.totalAmount ?? 0
        guard formulaTotal > 0 else { return [] }

        let scale = entry.totalKg / formulaTotal

        return result.items.map { item in
            ScaledMaterialItem(
                id:           item.materialCode,
                materialCode: item.materialCode,
                materialName: item.materialName,
                totalKg:      item.amount * scale,
                isAdditive:   item.isAdditive
            )
        }.sorted { $0.totalKg > $1.totalKg }
    }

    // MARK: - Ay aralığı

    func monthRange(_ date: Date) -> (Date, Date) {
        let cal   = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let start = cal.date(from: comps) ?? date
        let end   = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return (start, end)
    }
}
