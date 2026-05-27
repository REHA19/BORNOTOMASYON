import SwiftUI
import Combine

struct StockHistoryView: View {
    @StateObject private var viewModel = StockHistoryViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // Tarih Seçimi
                Section("Tarih Aralığı") {
                    DatePicker("Başlangıç", selection: $viewModel.startDate, displayedComponents: .date)
                    DatePicker("Bitiş",     selection: $viewModel.endDate,   displayedComponents: .date)

                    Button {
                        Task { await viewModel.query() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                            } else {
                                Label("Sorgula", systemImage: "calendar.badge.magnifyingglass")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }

                // Hata
                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                }

                // Sonuçlar
                if !viewModel.materials.isEmpty {
                    Section {
                        LabeledContent("Toplam Malzeme", value: "\(viewModel.materials.count) kalem")
                        LabeledContent("Toplam Stok") {
                            Text(viewModel.formattedTotal + " kg")
                                .fontWeight(.bold)
                        }
                    } header: {
                        Text("Özet")
                    }

                    Section("Malzemeler") {
                        ForEach(viewModel.materials) { material in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(stockColor(material.netStock))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(material.materialName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text(viewModel.formattedDate(material.effective))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(viewModel.formattedStock(material.netStock))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Tarihli Stok")
        }
    }

    private func stockColor(_ stock: Double) -> Color {
        if stock < 0      { return .red }
        if stock < 1_000  { return .orange }
        if stock < 50_000 { return .yellow }
        return .green
    }
}

// MARK: - ViewModel

@MainActor
final class StockHistoryViewModel: ObservableObject {

    @Published var materials: [Material] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @Published var endDate: Date = .now

    nonisolated(unsafe) private let service: MaterialServiceProtocol

    nonisolated init(service: MaterialServiceProtocol = MaterialService()) {
        self.service = service
    }

    func query() async {
        guard startDate <= endDate else {
            errorMessage = "Başlangıç tarihi bitiş tarihinden önce olmalı"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            var request = StockRequest()
            request.startDate = startDate
            request.endDate   = endDate
            materials = try await service.fetchMaterials(request: request)
        } catch {
            errorMessage = error.localizedDescription
            materials = []
        }

        isLoading = false
    }

    // MARK: - Format Helpers

    var formattedTotal: String {
        materials.reduce(0) { $0 + $1.netStock }.decimalString
    }

    func formattedStock(_ value: Double) -> String { value.kgString }

    func formattedDate(_ date: Date) -> String { date.trClock }
}
