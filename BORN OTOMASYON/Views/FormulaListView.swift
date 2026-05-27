import SwiftUI

struct FormulaListView: View {
    @EnvironmentObject private var vm: FormulaListViewModel

    var body: some View {
        NavigationStack {
            Group {
                if vm.isScanning && vm.formulas.isEmpty {
                    loadingView
                } else if vm.rasyonGroups.isEmpty && !vm.isScanning {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("Formüller")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.initialLoad() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(vm.statusMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    if vm.isScanning {
                        Button("Durdur") { vm.cancelScan() }
                            .foregroundColor(.red)
                    } else {
                        Button { Task { await vm.reload() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Yükleniyor

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(vm.statusMessage)
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if vm.isScanning {
                VStack(spacing: 6) {
                    ProgressView(value: vm.scanProgress).frame(width: 220)
                    Text(String(format: "%.0f%%", vm.scanProgress * 100))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Boş

    private var emptyView: some View {
        ContentUnavailableView(
            "Bu Ay Rasyon Bulunamadı",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Bu ay içinde formül bulunamadı.\nYenilemek için 🔄 butonuna dokunun.")
        )
    }

    // MARK: - Ana liste: Ay → Gün → Rasyon

    private var listView: some View {
        List {
            // Tarama devam ediyorsa ilerleme satırı
            if vm.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.statusMessage)
                            .font(.caption).foregroundColor(.secondary)
                        ProgressView(value: vm.scanProgress)
                    }
                }
                .padding(.vertical, 4)
            }

            // Ay bölümleri
            ForEach(vm.rasyonGroups, id: \.month) { monthSection in
                Section {
                    ForEach(monthSection.days) { dayGroup in
                        // ── Gün başlığı ──
                        dayHeader(dayGroup)

                        // ── O güne ait rasyonlar ──
                        ForEach(dayGroup.rasyons) { rasyon in
                            NavigationLink(destination: FormulaProductsView(group: rasyon)) {
                                RasyonRowView(rasyon: rasyon, vm: vm)
                            }
                            .padding(.leading, 12)  // Gün başlığına görsel girintili görünüm
                        }
                    }
                } header: {
                    monthHeader(monthSection.month, dayCount: monthSection.days.count,
                                rasyonCount: monthSection.days.reduce(0) { $0 + $1.rasyons.count })
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Ay başlığı

    private func monthHeader(_ month: String, dayCount: Int, rasyonCount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(month.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary)
            Spacer()
            Text("\(dayCount) gün · \(rasyonCount) rasyon")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Gün başlığı (tıklanamaz ayırıcı satır)

    private func dayHeader(_ dayGroup: DayGroup) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(dayGroup.dayLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text("\(dayGroup.rasyons.count) rasyon")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .listRowBackground(Color.accentColor.opacity(0.05))
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

// MARK: - Rasyon satırı

private struct RasyonRowView: View {
    let rasyon: RasyonGroup
    let vm:     FormulaListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(rasyon.customName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(rasyon.productCount) ürün")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }

            HStack(spacing: 12) {
                let total = rasyon.formulas.reduce(0.0) { $0 + $1.totalAmount }
                Label(total.kgWholeString, systemImage: "scalemass")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Label("\(rasyon.formulas.count) formül", systemImage: "doc.plaintext")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
