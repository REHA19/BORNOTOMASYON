import SwiftUI
import Combine

@MainActor
final class ProductionViewModel: ObservableObject {

    // MARK: - State

    @Published var selectedMonth: Date = {
        let cal   = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()

    @Published var summary:       ProductionSummary?
    @Published var isLoading      = false
    @Published var isLoadingFormulas = false
    @Published var errorMessage:  String?
    @Published var segment:       Int = 0   // 0 = Ürünler, 1 = Hammaddeler

    private let service   = ProductionService()
    private var formulaTask: Task<Void, Never>?

    // MARK: - Computed

    var monthTitle: String { selectedMonth.trMonthYear }

    var aggregatedMaterials: [ScaledMaterialItem] {
        summary?.aggregatedMaterials ?? []
    }

    // MARK: - Ay navigasyonu

    func previousMonth() {
        selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        Task { await load() }
    }

    func nextMonth() {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        // Gelecek aya gitme
        let startOfNow = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        guard next <= startOfNow else { return }
        selectedMonth = next
        Task { await load() }
    }

    var canGoNext: Bool {
        let startOfNow = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        return next <= startOfNow
    }

    // MARK: - Yükle

    func load() async {
        formulaTask?.cancel()
        isLoading    = true
        errorMessage = nil
        summary      = nil

        do {
            var s = try await service.fetchSummary(month: selectedMonth)
            summary   = s
            isLoading = false

            // Formülleri arka planda paralel yükle
            guard !s.entries.isEmpty else { return }
            isLoadingFormulas = true

            formulaTask = Task {
                await withTaskGroup(of: (Int, [ScaledMaterialItem]).self) { group in
                    for (idx, entry) in s.entries.enumerated() {
                        group.addTask { [service] in
                            let items = await service.loadFormula(for: entry)
                            return (idx, items)
                        }
                    }
                    for await (idx, items) in group {
                        guard !Task.isCancelled else { break }
                        s.entries[idx].formulaItems  = items
                        s.entries[idx].formulaLoaded = true
                        summary = s   // UI'yı güncelle
                    }
                }
                isLoadingFormulas = false
            }
            await formulaTask?.value

        } catch {
            errorMessage = error.localizedDescription
            isLoading    = false
        }
    }
}
