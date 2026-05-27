import SwiftUI

struct StockReportView: View {
    @StateObject private var viewModel = StockReportViewModel()
    @State private var showFilter = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Yükleniyor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    errorView(message: error)
                } else {
                    reportList
                }
            }
            .navigationTitle("Hareketler")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilter = true } label: {
                        Label("Tarih", systemImage: "calendar")
                    }
                }
            }
            .sheet(isPresented: $showFilter) {
                NavigationStack {
                    Form {
                        Section("Tarih Aralığı") {
                            DatePicker("Başlangıç", selection: $viewModel.date1, displayedComponents: .date)
                            DatePicker("Bitiş",     selection: $viewModel.date2, displayedComponents: .date)
                        }
                    }
                    .navigationTitle("Tarih Seç")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Uygula") {
                                showFilter = false
                                Task { await viewModel.refresh() }
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - List

    private var reportList: some View {
        List {

            // ── Hammadde Girişleri ──────────────────────────────
            Section {
                summaryRow("Toplam Sefer", value: "\(viewModel.entryCount) araç")
                summaryRow("Toplam Net",   value: weight(viewModel.entryNet))
            } header: {
                Label("Hammadde Girişleri", systemImage: "arrow.down.circle.fill")
                    .foregroundColor(.green)
            }

            if viewModel.entrySummaries.isEmpty {
                Section {
                    Text("Bu dönemde giriş kaydı bulunamadı.")
                        .foregroundColor(.secondary).font(.subheadline)
                }
            } else {
                Section {
                    ForEach(viewModel.entrySummaries) { s in
                        NavigationLink(destination: StockReportDetailView(summary: s)) {
                            summaryRow(s)
                        }
                    }
                } header: {
                    Text("Malzeme Bazında (\(viewModel.entrySummaries.count))")
                }
            }

            // ── İçerideki Araçlar ───────────────────────────────
            Section {
                if viewModel.insideVehicles.isEmpty {
                    Text("Şu an içeride araç bulunmuyor.")
                        .foregroundColor(.secondary).font(.subheadline)
                } else {
                    ForEach(viewModel.insideVehicles) { vehicle in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(vehicle.vehicleCode)
                                    .font(.subheadline).fontWeight(.semibold)
                                Text(vehicle.materialName ?? "—")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(weight(vehicle.gross))
                                    .font(.subheadline).fontWeight(.semibold)
                                Text(fmtDate(vehicle.entryDate))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Label("İçerideki Araçlar (\(viewModel.insideVehicles.count))", systemImage: "truck.box.fill")
                    .foregroundColor(.blue)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func summaryRow(_ s: MaterialSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.materialName).font(.body).fontWeight(.medium)
                Text("\(s.count) sefer").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(weight(s.totalNet))
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.accentColor)
                Text("net").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    private func fmtDate(_ d: Date) -> String { d.trLong }

    private func weight(_ v: Double) -> String { v.kgWholeString }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
            Text(message).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button("Tekrar Dene") { Task { await viewModel.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
