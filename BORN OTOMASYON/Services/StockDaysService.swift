import Foundation

struct StockDaysService {

    private let consumptionService = ConsumptionGroupService()
    private let formulaService     = FormulaDetailService()

    // MARK: - Ana hesaplama
    // Dönüş: materialCode → günlük tüketim (kg/gün)

    func calculateDailyRates(currentStock: [Material]) async -> [String: Double] {

        // 1) Geçen ay aralığı
        let (start, end) = lastMonthRange()
        let daysInPeriod = max(1, Calendar.current
            .dateComponents([.day], from: start, to: end).day ?? 30)

        // 2) Geçen ay üretilen yemler (materialType: 2 = Yem)
        let filter = ConsumptionGroupFilter(date1: start, date2: end, materialType: 2)
        guard let production = try? await consumptionService.fetchConsumption(filter: filter),
              !production.isEmpty else { return [:] }

        // 3) Her ürün için aktif formül → günlük hammadde tüketimi
        var dailyConsumption: [String: Double] = [:]

        await withTaskGroup(of: [String: Double].self) { group in
            for product in production where product.realAmount > 0 {
                group.addTask {
                    guard let result = try? await formulaService.fetch(
                        formulaID:    product.formulaID,
                        productCode:  product.code,
                        fallbackCode: product.formulaName ?? ""
                    ), let formula = result.formula,
                       formula.totalAmount > 0 else { return [:] }

                    // Ürünün günlük üretim hızı
                    let dailyKg = product.realAmount / Double(daysInPeriod)
                    // Formül batch'ini bu hıza ölçekle
                    let scale   = dailyKg / formula.totalAmount

                    var rates: [String: Double] = [:]
                    for item in result.items {
                        rates[item.materialCode, default: 0] += item.amount * scale
                    }
                    return rates
                }
            }
            for await rates in group {
                for (code, kg) in rates {
                    dailyConsumption[code, default: 0] += kg
                }
            }
        }

        return dailyConsumption
    }

    // MARK: - Stok bazında gün hesabı

    func daysRemaining(stock: [Material], dailyRates: [String: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        for mat in stock {
            guard let rate = dailyRates[mat.materialCode], rate > 0 else { continue }
            result[mat.materialCode] = max(0, mat.netStock / rate)
        }
        return result
    }

    // MARK: - Geçen ay aralığı

    private func lastMonthRange() -> (Date, Date) {
        let cal            = Calendar.current
        let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let start          = cal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? Date()
        let end            = cal.date(byAdding: .second, value: -1, to: thisMonthStart) ?? Date()
        return (start, end)
    }
}
