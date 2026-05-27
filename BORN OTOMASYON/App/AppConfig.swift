import Foundation

// MARK: - AppConfig
// IP adresini buradan merkezi olarak yönet.
// Prod/Dev ortamı için ayrı scheme veya xcconfig kullanabilirsin.

enum AppConfig {
    static let baseURL = "http://192.168.2.77:5001"

    enum Endpoint {
        static let factoryNetStockOut    = "/api/FactoryNetStockOut"
        static let vehicleTransactions   = "/api/GetVehicleTransactions"
        static let consumptionGroup      = "/api/ConsumptionGroup"
        static let formulaDetail         = "/api/GetFormulaDetail"
        static let activeFormula         = "/api/GetActiveFormulaOfProduct"
        static let getFormulaByID        = "/api/Formula/GetFormulaApp"
        static let createFormula         = "/api/CreateNewFormulaFromApp"
    }

    enum Timeout {
        static let request: TimeInterval = 30
        static let resource: TimeInterval = 60
    }
}
