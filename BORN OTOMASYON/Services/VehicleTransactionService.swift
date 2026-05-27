import Foundation

// MARK: - Protocol

protocol VehicleTransactionServiceProtocol {
    func fetchTransactions(filter: VehicleListFilter) async throws -> [VehicleListModel]
    func grouped(by transactions: [VehicleListModel]) -> [String: [VehicleListModel]]
}

// MARK: - VehicleTransactionService

final class VehicleTransactionService: VehicleTransactionServiceProtocol {

    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func fetchTransactions(filter: VehicleListFilter) async throws -> [VehicleListModel] {
        do {
            // Önce sarmalı yanıt (Data/Success/Message) dene
            let response: VehicleTransactionResponse = try await network.post(
                endpoint: AppConfig.Endpoint.vehicleTransactions,
                body: filter
            )
            guard response.success else {
                throw APIError.businessError(message: response.message ?? "Sunucu hatası")
            }
            return response.data
        } catch let e as APIError {
            throw e
        } catch {
            // Sarmal yoksa düz dizi olarak dene
            return try await network.post(
                endpoint: AppConfig.Endpoint.vehicleTransactions,
                body: filter
            )
        }
    }

    func grouped(by transactions: [VehicleListModel]) -> [String: [VehicleListModel]] {
        Dictionary(grouping: transactions) { $0.materialName ?? "Belirtilmemiş" }
    }
}
