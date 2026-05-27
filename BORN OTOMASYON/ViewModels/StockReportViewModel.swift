import Foundation
import Combine

struct MaterialSummary: Identifiable {
    let materialName: String
    let transactions: [VehicleListModel]

    var id: String { materialName }
    var count: Int         { transactions.count }
    var totalNet: Double   { transactions.reduce(0) { $0 + $1.net } }
    var totalGross: Double { transactions.reduce(0) { $0 + $1.gross } }
    var totalTare: Double  { transactions.reduce(0) { $0 + $1.tare } }
}

struct VehicleSummary: Identifiable {
    let vehicleCode: String
    let entryDate: Date
    let transactions: [VehicleListModel]

    // id: araç + sefer başlangıç dakikası (aynı araç birden fazla sefer yapabilir)
    var id: String { "\(vehicleCode)_\(Int(entryDate.timeIntervalSince1970 / 60))" }

    // Kamyon tartısı tüm ürünlerde aynı → bir kez alınır
    var tripNet: Double   { transactions.first?.net   ?? 0 }
    var tripGross: Double { transactions.first?.gross ?? 0 }
    var tripTare: Double  { transactions.first?.tare  ?? 0 }

    // WaybillAmount: irsaliyedeki ürün miktarı (net ağırlıktan daha doğru)
    var products: [(name: String, amount: Double)] {
        transactions.compactMap { t in
            guard let name = t.materialName else { return nil }
            return (name: name, amount: t.waybillAmount ?? t.net)
        }
    }
}

@MainActor
final class StockReportViewModel: ObservableObject {

    @Published var date1: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @Published var date2: Date = .now

    // Girişler — malzeme bazında
    @Published var entrySummaries: [MaterialSummary] = []
    // Çıkışlar — malzeme bazında
    @Published var exitSummaries: [MaterialSummary] = []
    // Çıkışlar — araç bazında
    @Published var exitByVehicle: [VehicleSummary] = []
    // İçerideki araçlar (giriş var, çıkış yok)
    @Published var insideVehicles: [VehicleListModel] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: VehicleTransactionServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(service: VehicleTransactionServiceProtocol = VehicleTransactionService()) {
        self.service = service
    }

    // MARK: - Hesaplamalar

    var entryCount: Int    { entrySummaries.reduce(0) { $0 + $1.count } }
    var entryNet: Double   { entrySummaries.reduce(0) { $0 + $1.totalNet } }

    // Sefer sayısı ve toplam net — araç bazlı (çift sayımı önler)
    var exitCount: Int     { exitByVehicle.count }
    var exitNet: Double    { exitByVehicle.reduce(0) { $0 + $1.tripNet } }

    // MARK: - Intent

    func onAppear() async {
        Publishers.CombineLatest($date1, $date2)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _, _ in Task { await self?.fetch() } }
            .store(in: &cancellables)
        await fetch()
    }

    func refresh() async { await fetch() }

    // MARK: - Private

    private func fetch() async {
        isLoading = true
        errorMessage = nil

        let entryFilter = VehicleListFilter(
            date1: date1, date2: date2,
            inside: true, exited: true,
            sale: false, purchase: true,
            withoutOrder: true, withOrder: true
        )
        let exitFilter = VehicleListFilter(
            date1: date1, date2: date2,
            inside: true, exited: true,
            sale: true, purchase: false,
            withoutOrder: true, withOrder: true
        )
        // İçerideki araçlar: geniş tarih aralığı, exitDate == nil olanları Swift tarafında filtrele
        let insideFilter = VehicleListFilter(
            date1: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
            date2: .now,
            inside: true, exited: true,
            sale: true, purchase: true,
            withoutOrder: true, withOrder: true
        )

        do {
            async let entryResult  = service.fetchTransactions(filter: entryFilter)
            async let exitResult   = service.fetchTransactions(filter: exitFilter)
            async let insideResult = service.fetchTransactions(filter: insideFilter)
            let (entries, exits, inside) = try await (entryResult, exitResult, insideResult)

            entrySummaries = service.grouped(by: entries)
                .map { MaterialSummary(materialName: $0.key, transactions: $0.value) }
                .sorted { $0.totalNet > $1.totalNet }

            exitSummaries = service.grouped(by: exits)
                .map { MaterialSummary(materialName: $0.key, transactions: $0.value) }
                .sorted { $0.totalNet > $1.totalNet }

            // exitDate nil = araç hâlâ içeride
            insideVehicles = inside
                .filter { $0.exitDate == nil }
                .sorted { $0.entryDate > $1.entryDate }

            // Sefer bazında gruplama: aynı araç + aynı dakika = tek sefer
            exitByVehicle = Dictionary(
                grouping: exits,
                by: { "\($0.vehicleCode)|\(Int($0.entryDate.timeIntervalSince1970 / 60))" }
            )
            .map { _, txs -> VehicleSummary in
                let sorted = txs.sorted { $0.entryDate < $1.entryDate }
                return VehicleSummary(
                    vehicleCode: sorted[0].vehicleCode,
                    entryDate:   sorted[0].entryDate,
                    transactions: sorted
                )
            }
            .sorted { $0.entryDate > $1.entryDate }
        } catch {
            errorMessage = error.localizedDescription
            entrySummaries = []
            exitSummaries  = []
            exitByVehicle  = []
            insideVehicles = []
        }
        isLoading = false
    }
}
