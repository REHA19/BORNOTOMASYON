import Foundation

struct FormulaListService {

    // MARK: - 1. Consumption API → bu ayın formulaID'leri
    // ConsumptionGroupService'i yeniden kullanır — aynı format, aynı encoder

    func fetchFromConsumptionDebug(monthStart: Date, today: Date) async -> ([FormulaActiveResponse], String) {
        let svc    = ConsumptionGroupService()
        let filter = ConsumptionGroupFilter(date1: monthStart, date2: today, materialType: 2)

        let groups: [ConsumptionGroupModel]
        do {
            groups = try await svc.fetchConsumption(filter: filter)
        } catch {
            return ([], "❌ Consumption hatası: \(error.localizedDescription.prefix(100))")
        }

        if groups.isEmpty {
            return ([], "⚠️ Consumption boş döndü (materialType:2, \(monthStart.trShort)–\(today.trShort))")
        }

        let ids   = Array(Set(groups.compactMap { $0.formulaID }))
        let names = groups.compactMap { $0.formulaName }.prefix(5).joined(separator: ", ")

        if ids.isEmpty {
            return ([], "⚠️ \(groups.count) satır, FormulaID hepsi nil. İsimler: \(names)")
        }

        // Her ID için formül detayını paralel çek
        let formulas = await withTaskGroup(of: FormulaActiveResponse?.self) { group in
            var results: [FormulaActiveResponse] = []
            for id in ids { group.addTask { await fetchOne(id) } }
            for await result in group { if let f = result { results.append(f) } }
            return results
        }

        if formulas.isEmpty {
            return ([], "⚠️ \(ids.count) ID var (\(ids.prefix(4).map{String($0)}.joined(separator:","))), GetFormulaApp boş döndü")
        }
        return (formulas, "✓ \(formulas.count) formül")
    }

    func fetchFromConsumption(monthStart: Date, today: Date) async -> [FormulaActiveResponse] {
        await fetchFromConsumptionDebug(monthStart: monthStart, today: today).0
    }

    // MARK: - 2. Genel liste endpoint'leri (backend tam desteği varsa)

    func fetchAll() async -> [FormulaActiveResponse] {
        let paths = [
            "/api/Formula/GetFormulaApps",
            "/api/Formula/GetFormulas",
            "/api/GetFormulas",
            "/api/Formula/List",
            "/api/GetFormulaList",
        ]
        for path in paths {
            guard let url = URL(string: AppConfig.baseURL + path) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            if let list = try? JSONDecoder().decode([FormulaActiveResponse].self, from: data), !list.isEmpty { return list }
            struct W: Decodable {
                let data: [FormulaActiveResponse]?
                enum CodingKeys: String, CodingKey { case data = "Data" }
            }
            if let w = try? JSONDecoder().decode(W.self, from: data), let list = w.data, !list.isEmpty { return list }
        }
        return []
    }

    // MARK: - 3. Yedek: ID taraması (yavaş, son çare)

    func scan(maxID: Int = 3000,
              batchSize: Int = 15,
              cutoff: Date,
              interBatchDelay: Double = 0.15,
              onProgress: @escaping (Int) -> Void) -> AsyncStream<FormulaActiveResponse> {

        return AsyncStream { continuation in
            Task {
                var base = 1

                while base <= maxID {
                    guard !Task.isCancelled else { continuation.finish(); return }

                    let lo = base
                    let hi = min(base + batchSize - 1, maxID)

                    await withTaskGroup(of: FormulaActiveResponse?.self) { group in
                        for id in lo...hi {
                            group.addTask { await fetchOne(id) }
                        }
                        for await result in group {
                            guard let f = result else { continue }
                            let date = f.effectiveDate
                            if date == nil || date! >= cutoff {
                                continuation.yield(f)
                            }
                        }
                    }

                    base = hi + 1
                    onProgress(base)

                    if base <= maxID {
                        try? await Task.sleep(nanoseconds: UInt64(interBatchDelay * 1_000_000_000))
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Tek ID getir

    func fetchOne(_ id: Int) async -> FormulaActiveResponse? {
        guard let url = URL(string: AppConfig.baseURL + AppConfig.Endpoint.getFormulaByID + "/\(id)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        if let w = try? JSONDecoder().decode(FormulaActiveWrapper.self, from: data), let f = w.data { return f }
        if let f = try? JSONDecoder().decode(FormulaActiveResponse.self, from: data) { return f }
        return nil
    }
}
