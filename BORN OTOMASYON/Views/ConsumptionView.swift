import SwiftUI
import SwiftData

struct ConsumptionView: View {
    @StateObject private var viewModel = ConsumptionGroupViewModel()
    @Query private var ingredients: [FeedIngredient]

    var body: some View {
        NavigationStack {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Yükleniyor...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text(error)
                        .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
                    Button("Tekrar Dene") { Task { await viewModel.refresh() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                reportList
            }
        }
        .navigationTitle("Sarfiyat Raporu")
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
        }
    }

    private var reportList: some View {
        List {
            Section {
                DatePicker("Başlangıç", selection: $viewModel.date1, displayedComponents: .date)
                DatePicker("Bitiş",     selection: $viewModel.date2, displayedComponents: .date)
                Picker("Malzeme Tipi", selection: $viewModel.materialType) {
                    Text("Hammadde").tag(1)
                    Text("Yem").tag(2)
                }
                .pickerStyle(.segmented)
            } header: { Text("Filtre") }

            if !viewModel.items.isEmpty {
                Section {
                    summaryRow("Toplam Plan",   value: fmt(viewModel.totalPlan),  color: .primary)
                    summaryRow("Toplam Gerçek", value: fmt(viewModel.totalReal),  color: .primary)
                    summaryRow("Fark",          value: fmt(viewModel.totalDiff),
                               color: viewModel.totalDiff > 0 ? .red : viewModel.totalDiff < 0 ? .orange : .green)

                    // Maliyet (yalnızca hammadde tipinde ve fiyat girilmiş kayıtlar)
                    if viewModel.materialType == 1, !ingredients.isEmpty {
                        let costResult = IngredientMatcher.summarize(
                            items: viewModel.items.map { (code: $0.code, name: $0.name, kg: $0.realAmount) },
                            in: ingredients
                        )
                        if costResult.matchedCount > 0 {
                            Divider()
                            summaryRow(
                                "Tahmini Maliyet (\(costResult.matchedCount)/\(costResult.totalItems) eşleşti)",
                                value: costResult.totalCostTL.tlString,
                                color: .orange
                            )
                        }
                    }
                } header: { Text("Genel Özet") }
            }

            if !viewModel.overItems.isEmpty {
                Section {
                    ForEach(viewModel.overItems) { item in
                        NavigationLink(destination: ConsumptionDetailView(item: item, date1: viewModel.date1, date2: viewModel.date2)) {
                            ConsumptionRowView(item: item)
                        }
                    }
                } header: {
                    Label("Fazla Tüketim (\(viewModel.overItems.count))", systemImage: "arrow.up.circle.fill")
                        .foregroundColor(.red)
                }
            }

            if !viewModel.underItems.isEmpty {
                Section {
                    ForEach(viewModel.underItems) { item in
                        NavigationLink(destination: ConsumptionDetailView(item: item, date1: viewModel.date1, date2: viewModel.date2)) {
                            ConsumptionRowView(item: item)
                        }
                    }
                } header: {
                    Label("Eksik Tüketim (\(viewModel.underItems.count))", systemImage: "arrow.down.circle.fill")
                        .foregroundColor(.orange)
                }
            }

            if !viewModel.onTarget.isEmpty {
                Section {
                    ForEach(viewModel.onTarget) { item in
                        NavigationLink(destination: ConsumptionDetailView(item: item, date1: viewModel.date1, date2: viewModel.date2)) {
                            ConsumptionRowView(item: item)
                        }
                    }
                } header: {
                    Label("Plana Uygun (\(viewModel.onTarget.count))", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            if viewModel.items.isEmpty {
                Section {
                    Text("Seçili tarih aralığında tüketim kaydı bulunamadı.")
                        .foregroundColor(.secondary).font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func summaryRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundColor(color)
        }
    }

    private func fmt(_ value: Double) -> String { value.kgString }
}

// MARK: - ConsumptionRowView

struct ConsumptionRowView: View {
    let item: ConsumptionGroupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.subheadline).fontWeight(.semibold)
                    if let formula = item.formulaName, !formula.isEmpty {
                        Text(formula).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(diffText)
                        .font(.subheadline).fontWeight(.bold).foregroundColor(diffColor)
                    Text("Fark").font(.caption2).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 16) {
                labeledValue("Plan",   value: fmt(item.planAmount))
                labeledValue("Gerçek", value: fmt(item.realAmount))
            }
        }
        .padding(.vertical, 4)
    }

    private var diffColor: Color {
        item.diff > 0 ? .red : item.diff < 0 ? .orange : .green
    }

    private var diffText: String {
        (item.diff > 0 ? "+" : "") + fmt(item.diff)
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.caption).fontWeight(.medium)
        }
    }

    private func fmt(_ value: Double) -> String { value.kgString }
}
