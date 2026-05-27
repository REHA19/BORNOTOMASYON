import Foundation

struct FormulaDetailService {

    private let materialService = MaterialService()

    // MARK: - Ana çağrı

    func fetch(formulaID: Int? = nil,
               productCode: String,
               fallbackCode: String = "") async throws -> (items: [FormulaDetailItem], formula: FormulaActiveResponse?) {

        // 1) FormulaID varsa direkt getir (en hızlı yol)
        if let fid = formulaID, let result = try? await fetchByID(fid) {
            return try await joinWithMaterials(result)
        }

        // 2) Aktif formül — productCode ile
        if let result = try? await fetchActive(productCode),
           !result.details.isEmpty {
            return try await joinWithMaterials(result)
        }

        // 3) Aktif formül — formulaName ile
        if !fallbackCode.isEmpty, fallbackCode != productCode,
           let result = try? await fetchActive(fallbackCode),
           !result.details.isEmpty {
            return try await joinWithMaterials(result)
        }

        // 4) Formül listesinden customName ile ara
        if let result = try? await findByCustomName(fallbackCode.isEmpty ? productCode : fallbackCode) {
            return try await joinWithMaterials(result)
        }

        // 5) ID tarama (son çare): son 200 formülü dene
        if let result = await scanRecentIDs(customName: fallbackCode.isEmpty ? productCode : fallbackCode) {
            return try await joinWithMaterials(result)
        }

        throw NSError(domain: "FormulaDetail", code: -1, userInfo: [
            NSLocalizedDescriptionKey:
                "Formül bulunamadı.\n\nÜrün kodu: \(productCode)\nFormül adı: \(fallbackCode)\n\n" +
                "Backend'e FormulaID eklenmesi gerekiyor:\n" +
                "ConsumptionGroup yanıtına 'FormulaID' (int?) alanı ekleyin."
        ])
    }

    // MARK: - GET /api/Formula/GetFormula/{ID}

    func fetchByID(_ id: Int) async throws -> FormulaActiveResponse {
        guard let url = URL(string: AppConfig.baseURL + AppConfig.Endpoint.getFormulaByID + "/\(id)") else {
            throw URLError(.badURL)
        }
        return try await sendGET(url)
    }

    // MARK: - GET /api/GetActiveFormulaOfProduct/{code}

    private func fetchActive(_ code: String) async throws -> FormulaActiveResponse {
        let enc = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        guard let url = URL(string: AppConfig.baseURL + AppConfig.Endpoint.activeFormula + "/" + enc) else {
            throw URLError(.badURL)
        }
        return try await sendGET(url)
    }

    // MARK: - Formül listesinden customName ile ara

    private func findByCustomName(_ name: String) async throws -> FormulaActiveResponse? {
        // Birden fazla olası liste endpoint'ini dene
        let listPaths = [
            "/api/Formula/GetFormulas",
            "/api/GetFormulas",
            "/api/Formulas",
            "/api/Formula/List",
            "/api/GetFormulaList",
        ]

        for path in listPaths {
            guard let url = URL(string: AppConfig.baseURL + path) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }

            // Liste olarak ayrıştır
            if let list = try? JSONDecoder().decode([FormulaActiveResponse].self, from: data) {
                if let match = list.first(where: { $0.customName == name }) { return match }
            }
            // SR<[]> sarmalı
            struct ListWrapper: Decodable {
                let data: [FormulaActiveResponse]?
                enum CodingKeys: String, CodingKey { case data = "Data" }
            }
            if let wrapped = try? JSONDecoder().decode(ListWrapper.self, from: data),
               let match = wrapped.data?.first(where: { $0.customName == name }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Paralel ID Taraması (1-1000, batch=30)

    func scanRecentIDs(customName: String) async -> FormulaActiveResponse? {
        let totalRange = 1...3000
        let batchSize  = 50

        let batches = stride(from: totalRange.upperBound, through: totalRange.lowerBound, by: -batchSize).map { start in
            let end = start
            let from = max(start - batchSize + 1, totalRange.lowerBound)
            return from...end
        }

        for batch in batches {
            if let found = await scanBatch(ids: Array(batch), customName: customName) {
                return found
            }
        }
        return nil
    }

    private func scanBatch(ids: [Int], customName: String) async -> FormulaActiveResponse? {
        await withTaskGroup(of: FormulaActiveResponse?.self) { group in
            for id in ids {
                group.addTask {
                    guard let url = URL(string: AppConfig.baseURL + AppConfig.Endpoint.getFormulaByID + "/\(id)") else { return nil }
                    var req = URLRequest(url: url, timeoutInterval: 3)
                    req.httpMethod = "GET"
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    guard let (data, resp) = try? await URLSession.shared.data(for: req),
                          (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                    if let w = try? JSONDecoder().decode(FormulaActiveWrapper.self, from: data),
                       let f = w.data, f.customName == customName { return f }
                    if let f = try? JSONDecoder().decode(FormulaActiveResponse.self, from: data),
                       f.customName == customName { return f }
                    return nil
                }
            }
            for await result in group {
                if let found = result { return found }
            }
            return nil
        }
    }

    // MARK: - Ortak GET

    private func sendGET(_ url: URL) async throws -> FormulaActiveResponse {
        var req = URLRequest(url: url, timeoutInterval: AppConfig.Timeout.request)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        print("[FormulaDetail] GET \(url)")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let raw = String(data: data, encoding: .utf8) ?? ""
        print("[FormulaDetail] \(status) | \(raw.prefix(300))")

        if let wrapper = try? JSONDecoder().decode(FormulaActiveWrapper.self, from: data) {
            if let f = wrapper.data { return f }
            throw NSError(domain: "FormulaDetail", code: status, userInfo: [
                NSLocalizedDescriptionKey: wrapper.message ?? "Formül bulunamadı."
            ])
        }
        if let direct = try? JSONDecoder().decode(FormulaActiveResponse.self, from: data) {
            return direct
        }
        throw NSError(domain: "FormulaDetail", code: status, userInfo: [
            NSLocalizedDescriptionKey: "HTTP \(status)"
        ])
    }

    // MARK: - Dışarıdan çağrılabilir join

    func joinPublic(_ formula: FormulaActiveResponse) async throws -> (items: [FormulaDetailItem], formula: FormulaActiveResponse?) {
        try await joinWithMaterials(formula)
    }

    // MARK: - Malzeme isimleriyle birleştir

    private func joinWithMaterials(_ formula: FormulaActiveResponse) async throws -> (items: [FormulaDetailItem], formula: FormulaActiveResponse?) {
        guard !formula.details.isEmpty else { return ([], formula) }

        let materials = (try? await fetchMaterials()) ?? []
        let matDict: [Int: Material] = Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0) })

        let total = formula.details.reduce(0.0) { $0 + $1.amount }
        let items: [FormulaDetailItem] = formula.details
            .sorted { $0.rowNo < $1.rowNo }
            .map { d in
                let mat = matDict[d.materialID]
                return FormulaDetailItem(
                    materialCode: mat?.materialCode ?? "ID:\(d.materialID)",
                    materialName: mat?.materialName ?? "Malzeme #\(d.materialID)",
                    amount:       d.amount,
                    percentage:   total > 0 ? (d.amount / total * 100) : nil,
                    isAdditive:   d.isAdditive,
                    rowNo:        d.rowNo
                )
            }
        return (items, formula)
    }

    // MARK: - Malzeme listesi

    private func fetchMaterials() async throws -> [Material] {
        return (try? await materialService.fetchMaterials()) ?? []
    }
}
