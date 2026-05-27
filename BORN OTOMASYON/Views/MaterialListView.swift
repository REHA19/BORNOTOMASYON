import SwiftUI

struct MaterialListView: View {
    @StateObject private var viewModel = MaterialListViewModel()
    @State private var showFilterSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isOffline, let date = viewModel.cacheDate {
                    OfflineBanner(cacheDate: date)
                }
                ZStack {
                    materialList
                        .refreshable { await viewModel.refresh() }

                    if viewModel.isLoading && viewModel.filteredMaterials.isEmpty {
                        ProgressView("Yükleniyor...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                    }

                    if let error = viewModel.errorMessage, !viewModel.isLoading {
                        errorView(message: error)
                            .background(.ultraThinMaterial)
                    }
                }
            }
            .navigationTitle("Stok Listesi")
            .searchable(text: $viewModel.searchText, prompt: "Malzeme ara...")
            .toolbar {
                if let date = viewModel.lastSnapshotDate {
                    ToolbarItem(placement: .topBarLeading) {
                        Label(snapshotLabel(date), systemImage: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.isFilterActive {
                        Button {
                            Task { await viewModel.clearFilter() }
                        } label: {
                            Label("Filtreyi Kaldır", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    Button {
                        showFilterSheet = true
                    } label: {
                        Label(
                            "Filtrele",
                            systemImage: viewModel.isFilterActive
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }

                    sortMenu
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                StockFilterView { request in
                    Task { await viewModel.applyFilter(request) }
                }
            }
        }
        .task {
            await viewModel.onAppear()
        }
    }

    // MARK: - Subviews

    private var materialList: some View {
        AdaptiveListView(
            materials: viewModel.filteredMaterials,
            searchText: viewModel.searchText,
            snapshotDeltas: viewModel.snapshotDeltas,
            stockDays: viewModel.stockDays
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sırala", selection: $viewModel.sortOption) {
                ForEach(MaterialListViewModel.SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Label("Sırala", systemImage: "arrow.up.arrow.down")
        }
    }

    private func snapshotLabel(_ date: Date) -> String { date.trClock }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button("Tekrar Dene") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
