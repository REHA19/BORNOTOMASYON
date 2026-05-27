import Foundation

// MARK: - Protocol

protocol MaterialServiceProtocol {
    /// GET /api/FactoryNetStockOut — tüm stok listesi
    func fetchMaterials() async throws -> [Material]
    /// POST /api/FactoryNetStockOut — filtreli stok listesi
    func fetchMaterials(request: StockRequest) async throws -> [Material]
}

// MARK: - MaterialService

final class MaterialService: MaterialServiceProtocol {

    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    // MARK: - GET

    func fetchMaterials() async throws -> [Material] {
        let response: StockResponse = try await network.get(
            endpoint: AppConfig.Endpoint.factoryNetStockOut
        )
        return try validated(response)
    }

    // MARK: - POST

    func fetchMaterials(request: StockRequest) async throws -> [Material] {
        let response: StockResponse = try await network.post(
            endpoint: AppConfig.Endpoint.factoryNetStockOut,
            body: request
        )
        return try validated(response)
    }

    // MARK: - Private

    /// Success: true  → Data listesini döner
    /// Success: false → Message'ı APIError.businessError olarak fırlatır
    private func validated(_ response: StockResponse) throws -> [Material] {
        guard response.success else {
            let message = response.message ?? "Bilinmeyen sunucu hatası"
            throw APIError.businessError(message: message)
        }
        return response.data
    }
}

// MARK: - MockMaterialService (Test / SwiftUI Preview)

#if DEBUG
final class MockMaterialService: MaterialServiceProtocol {
    var mockMaterials: [Material] = []
    var shouldFail = false
    var failureMessage = "Test hatası"

    func fetchMaterials() async throws -> [Material] {
        if shouldFail { throw APIError.businessError(message: failureMessage) }
        return mockMaterials
    }

    func fetchMaterials(request: StockRequest) async throws -> [Material] {
        if shouldFail { throw APIError.businessError(message: failureMessage) }
        return mockMaterials.filter { material in
            guard let codes = request.materialCodes else { return true }
            return codes.contains(material.materialCode)
        }
    }
}
#endif // DEBUG
