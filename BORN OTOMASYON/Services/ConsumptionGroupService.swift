import Foundation

// MARK: - Protocol

protocol ConsumptionGroupServiceProtocol {
    func fetchConsumption(filter: ConsumptionGroupFilter) async throws -> [ConsumptionGroupModel]
}

// MARK: - ConsumptionGroupService

final class ConsumptionGroupService: ConsumptionGroupServiceProtocol {

    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func fetchConsumption(filter: ConsumptionGroupFilter) async throws -> [ConsumptionGroupModel] {
        guard let url = URL(string: AppConfig.baseURL + AppConfig.Endpoint.consumptionGroup) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(filter)

        print("🌐 URL: \(url)")
        if let body = req.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
            print("🌐 Body: \(bodyStr)")
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse {
            print("🌐 HTTP Status: \(http.statusCode)")
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("🌐 RAW: \(raw.prefix(500))")
        }

        let decoder = JSONDecoder()
        if let resp = try? decoder.decode(ConsumptionGroupResponse.self, from: data) {
            guard resp.success else {
                throw APIError.businessError(message: resp.message ?? "Sunucu hatası")
            }
            return resp.data
        }
        if let list = try? decoder.decode([ConsumptionGroupModel].self, from: data) {
            return list
        }
        throw APIError.decodingFailed(
            NSError(domain: "ConsumptionGroup", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Yanıt formatı tanınamadı"])
        )
    }
}
