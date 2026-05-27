import SwiftUI
import SwiftData
import UserNotifications
import Combine

// MARK: - NotificationsView

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @Query private var library:     [FeedIngredient]
    @Query private var allFormulas: [BlendFormula]

    // Formüllerde aktif olarak kullanılan ama stokta olmayan hammaddeler
    private var outOfStockActiveIngs: [FeedIngredient] {
        library.filter { ing in
            guard !ing.isAvailable else { return false }
            return allFormulas.contains { formula in
                formula.ingredients.contains { $0.code == ing.code && $0.isActive }
            }
        }
        .sorted { $0.name < $1.name }
    }

    // Düşük stok: sadece kütüphanede eşleşen VE en az bir formülde aktif kullanılan malzemeler
    private var activeLowStockMaterials: [Material] {
        viewModel.lowStockMaterials.filter { material in
            guard let ing = IngredientMatcher.find(
                code: material.materialCode,
                name: material.materialName,
                in: library
            ) else { return false }
            guard ing.isAvailable else { return false }
            return allFormulas.contains { formula in
                formula.ingredients.contains { $0.code == ing.code && $0.isActive }
            }
        }
    }

    private var totalCount: Int {
        outOfStockActiveIngs.count + activeLowStockMaterials.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Kontrol ediliyor…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    errorView(message: error)
                } else if totalCount == 0 {
                    ContentUnavailableView(
                        "Bildirim Yok",
                        systemImage: "bell.slash.fill",
                        description: Text("Tüm stoklar yeterli, tüm hammaddeler aktif.")
                    )
                } else {
                    notificationsList
                }
            }
            .navigationTitle("Bildirimler")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await viewModel.onAppear()
            await clearBadge()
        }
        .onAppear {
            Task { await clearBadge() }
        }
    }

    // MARK: - List

    private var notificationsList: some View {
        List {
            // ── Stokta Yok — Formülde Aktif ────────────────────────────────────
            if !outOfStockActiveIngs.isEmpty {
                Section {
                    ForEach(outOfStockActiveIngs, id: \.code) { ing in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.title3)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ing.name)
                                    .font(.body).fontWeight(.medium)
                                if !ing.code.isEmpty {
                                    Text(ing.code)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text("Formüllerde aktif — stokta yok")
                                    .font(.caption2).foregroundStyle(.red)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Label(
                        "Stokta Yok — Formülde Aktif (\(outOfStockActiveIngs.count))",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            // ── Düşük Stok (API) ────────────────────────────────────────────────
            if !activeLowStockMaterials.isEmpty {
                Section {
                    ForEach(activeLowStockMaterials) { material in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(stockColor(material.netStock).opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(stockColor(material.netStock))
                                    .font(.title3)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(material.materialName)
                                    .font(.body).fontWeight(.medium)
                                Text(material.materialCode)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(formatted(material.netStock) + " kg")
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundStyle(stockColor(material.netStock))
                                Text("Eşik: 1.000 kg")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Label(
                        "Düşük Stok (\(activeLowStockMaterials.count))",
                        systemImage: "shippingbox.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func clearBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Tekrar Dene") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stockColor(_ stock: Double) -> Color {
        stock <= 0 ? .red : stock < 500 ? .orange : .yellow
    }

    private func formatted(_ value: Double) -> String { value.decimalString }
}

// MARK: - ViewModel

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var lowStockMaterials: [Material] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    nonisolated(unsafe) private let service: MaterialServiceProtocol

    nonisolated init(service: MaterialServiceProtocol = MaterialService()) {
        self.service = service
    }

    func onAppear() async {
        guard lowStockMaterials.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await service.fetchMaterials()
            lowStockMaterials = all
                .filter { $0.netStock < NotificationManager.lowStockThreshold && $0.netStock >= 0 }
                .sorted { $0.netStock < $1.netStock }
            await NotificationManager.shared.scheduleLowStockNotifications(for: all)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
