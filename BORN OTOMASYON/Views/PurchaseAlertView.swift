import SwiftUI

struct PurchaseAlertView: View {
    @StateObject private var viewModel = PurchaseAlertViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isOffline, let date = viewModel.cacheDate {
                    OfflineBanner(cacheDate: date)
                }
                Group {
                if viewModel.isLoading {
                    ProgressView("Stok süresi hesaplanıyor…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = viewModel.errorMessage {
                    errorView(err)
                } else if viewModel.alertGroups.isEmpty {
                    ContentUnavailableView(
                        "Tüm Stoklar Yeterli",
                        systemImage: "checkmark.seal.fill",
                        description: Text("14 günün altında stoku olan malzeme bulunmuyor")
                    )
                } else {
                    list
                }
                } // Group
            } // VStack
            .navigationTitle("Satın Alma Planı")
            .toolbar {
                if let date = viewModel.lastUpdated {
                    ToolbarItem(placement: .topBarLeading) {
                        Label(date.trClock, systemImage: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await viewModel.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .task { await viewModel.onAppear() }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(viewModel.alertGroups, id: \.urgency) { group in
                Section {
                    ForEach(group.items) { info in
                        PurchaseAlertRow(info: info)
                    }
                } header: {
                    urgencyHeader(group.urgency, count: group.items.count)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Section Header

    private func urgencyHeader(_ urgency: PurchaseUrgency, count: Int) -> some View {
        HStack {
            Circle()
                .fill(urgency.color)
                .frame(width: 8, height: 8)
            Text(urgency.label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(urgency.color)
            Text("·  \(urgency.daysLabel)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count) malzeme")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
            Text(msg).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button("Tekrar Dene") { Task { await viewModel.refresh() } }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct PurchaseAlertRow: View {
    let info: MaterialMarketInfo

    var body: some View {
        HStack(spacing: 12) {
            // Urgency indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(info.urgency.color)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.material.materialName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(info.material.materialCode)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Days remaining
                if let days = info.stockDays {
                    Text("\(Int(days.rounded())) gün")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(info.urgency.color)
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }

                // Recommendation badge
                Label(info.recommendation.label, systemImage: info.recommendation.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(info.recommendation.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(info.recommendation.color.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
