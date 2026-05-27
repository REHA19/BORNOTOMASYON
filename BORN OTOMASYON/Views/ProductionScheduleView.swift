import SwiftUI
import SwiftData

struct ProductionScheduleView: View {
    @StateObject private var vm = ProductionViewModel()
    @Query private var ingredients: [FeedIngredient]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                segmentBar

                Group {
                    if vm.isLoading {
                        loadingView
                    } else if let error = vm.errorMessage {
                        errorView(error)
                    } else if let summary = vm.summary {
                        if vm.segment == 0 {
                            productList(summary)
                        } else {
                            materialList(summary)
                        }
                    } else {
                        emptyView
                    }
                }
            }
            .navigationTitle("Üretim Cetveli")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
        }
    }

    // MARK: - Ay başlığı

    private var monthHeader: some View {
        HStack(spacing: 20) {
            Button { vm.previousMonth() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }

            VStack(spacing: 2) {
                Text(vm.monthTitle)
                    .font(.title3).fontWeight(.bold)
                if let s = vm.summary {
                    Text("\(s.productCount) ürün · \(s.totalKg.kgString)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Button { vm.nextMonth() } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundColor(vm.canGoNext ? .accentColor : .secondary.opacity(0.3))
            }
            .disabled(!vm.canGoNext)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Segment

    private var segmentBar: some View {
        Picker("Görünüm", selection: $vm.segment) {
            Text("Ürünler").tag(0)
            Text("Hammaddeler").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Ürün listesi

    private func productList(_ summary: ProductionSummary) -> some View {
        // Hammadde maliyeti hesapla (formüller yüklendiyse)
        let hammadde   = summary.aggregatedMaterials.filter { !$0.isAdditive }
        let costResult = IngredientMatcher.summarize(
            items: hammadde.map { (code: $0.materialCode, name: $0.materialName, kg: $0.totalKg) },
            in: ingredients
        )
        let hasCost = costResult.matchedCount > 0 && summary.totalKg > 0
        let avgPerKg  = hasCost ? costResult.totalCostTL / summary.totalKg  : 0
        let avgPerTon = avgPerKg * 1000

        return List {
            if vm.isLoadingFormulas {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Hammadde hesaplanıyor…")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section {
                summaryCard(summary)
            }

            // Maliyet özeti — formüller yüklendiğinde ve en az bir eşleşme varsa göster
            if !vm.isLoadingFormulas && hasCost {
                Section {
                    HStack {
                        Label("Toplam Hammadde Maliyeti", systemImage: "banknote")
                            .foregroundStyle(.secondary).font(.subheadline)
                        Spacer()
                        Text(costResult.totalCostTL.tlString)
                            .font(.subheadline).bold().foregroundStyle(.orange)
                    }
                    HStack {
                        Label("Ortalama Maliyet / kg", systemImage: "scalemass")
                            .foregroundStyle(.secondary).font(.subheadline)
                        Spacer()
                        Text(String(format: "%.2f ₺/kg", avgPerKg))
                            .font(.subheadline).bold().foregroundStyle(.orange)
                    }
                    HStack {
                        Label("Ortalama Maliyet / ton", systemImage: "truck.box")
                            .foregroundStyle(.secondary).font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f ₺/ton", avgPerTon))
                            .font(.subheadline).bold().foregroundStyle(.orange)
                    }
                    if costResult.matchedCount < costResult.totalItems {
                        Label(
                            "\(costResult.totalItems - costResult.matchedCount) kalem fiyatsız — maliyet eksik hesaplanmış olabilir",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption2).foregroundStyle(.orange)
                    }
                } header: { Text("Üretim Maliyeti") }
            }

            Section {
                ForEach(summary.entries) { entry in
                    NavigationLink(destination: ProductionDetailView(entry: entry)) {
                        ProductionEntryRow(entry: entry)
                    }
                }
            } header: {
                Text("Üretilen Yemler (\(summary.productCount) kalem)")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Hammadde listesi (tüm ürünler toplanmış)

    private func materialList(_ summary: ProductionSummary) -> some View {
        let materials = summary.aggregatedMaterials
        let ings      = ingredients         // @Query yerel kopyası

        return List {
            if vm.isLoadingFormulas {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Hesaplanıyor…")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if materials.isEmpty && !vm.isLoadingFormulas {
                Text("Formül verisi yüklenince hammaddeler görünür.")
                    .font(.subheadline).foregroundColor(.secondary)
            } else {
                let hammadde = materials.filter { !$0.isAdditive }
                let katki    = materials.filter {  $0.isAdditive }

                // Maliyet özeti (hammadde kütüphanesi ile eşleşen kalemler)
                if !hammadde.isEmpty && !ings.isEmpty {
                    let costResult = IngredientMatcher.summarize(
                        items: hammadde.map { (code: $0.materialCode, name: $0.materialName, kg: $0.totalKg) },
                        in: ings
                    )
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Toplam Hammadde Maliyeti")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("\(costResult.matchedCount)/\(costResult.totalItems) kalem fiyatlandı")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if costResult.matchedCount > 0 {
                                Text(costResult.totalCostTL.tlString)
                                    .font(.title3).fontWeight(.bold).foregroundColor(.orange)
                            } else {
                                Text("Fiyat girilmemiş")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: { Text("Maliyet Özeti") }
                }

                if !hammadde.isEmpty {
                    Section {
                        ForEach(hammadde) { item in
                            MaterialUsageRow(item: item, totalProduced: summary.totalKg,
                                            ingredient: IngredientMatcher.find(
                                                code: item.materialCode, name: item.materialName, in: ings))
                        }
                    } header: {
                        HStack {
                            Text("Hammaddeler (\(hammadde.count) kalem)")
                            Spacer()
                            Text(hammadde.reduce(0) { $0 + $1.totalKg }.kgString)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                if !katki.isEmpty {
                    Section {
                        ForEach(katki) { item in
                            MaterialUsageRow(item: item, totalProduced: summary.totalKg, ingredient: nil)
                        }
                    } header: {
                        HStack {
                            Text("Katkılar (\(katki.count) kalem)")
                            Spacer()
                            Text(katki.reduce(0) { $0 + $1.totalKg }.kgString)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Özet kart

    private func summaryCard(_ summary: ProductionSummary) -> some View {
        HStack(spacing: 0) {
            statCell("Toplam Üretim",  value: summary.totalKg.kgString,              icon: "scalemass.fill",    color: .blue)
            Divider().frame(height: 40)
            statCell("Ürün Çeşidi",   value: "\(summary.productCount) kalem",       icon: "list.bullet",       color: .green)
            Divider().frame(height: 40)
            statCell("Ton",           value: String(format: "%.1f t", summary.totalKg / 1000), icon: "truck.box.fill", color: .orange)
        }
        .padding(.vertical, 8)
    }

    private func statCell(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.title3)
            Text(value).font(.subheadline).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Yardımcı durumlar

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Üretim verileri yükleniyor…")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 44)).foregroundColor(.secondary)
            Text("Bu ay için üretim verisi bulunamadı.")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
            Text(msg).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button("Tekrar Dene") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ürün satırı

private struct ProductionEntryRow: View {
    let entry: ProductionEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.productName)
                    .font(.subheadline).fontWeight(.semibold)
                Text(entry.productCode)
                    .font(.caption).foregroundColor(.secondary)
                if entry.formulaLoaded {
                    Text("\(entry.formulaItems.count) hammadde")
                        .font(.caption2).foregroundColor(.secondary)
                } else {
                    Text("Formül yükleniyor…")
                        .font(.caption2).foregroundColor(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.totalKg.kgString)
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.accentColor)
                Text(String(format: "%.2f ton", entry.totalKg / 1000))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Hammadde satırı

private struct MaterialUsageRow: View {
    let item:          ScaledMaterialItem
    let totalProduced: Double
    let ingredient:    FeedIngredient?

    private var percentage: Double {
        totalProduced > 0 ? item.totalKg / totalProduced * 100 : 0
    }

    private var costTL: Double? {
        IngredientMatcher.cost(kg: item.totalKg, ingredient: ingredient)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.materialName)
                    .font(.subheadline).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(item.materialCode)
                        .font(.caption).foregroundColor(.secondary)
                    if ingredient?.priceTL == nil {
                        Text("fiyatsız")
                            .font(.caption2).foregroundColor(.orange)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.totalKg.kgString)
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.accentColor)
                if let c = costTL {
                    Text(c.tlString)
                        .font(.caption).fontWeight(.medium).foregroundColor(.orange)
                } else {
                    Text(String(format: "%.1f%%", percentage))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Ürün detay ekranı (hammadde dökümü)

struct ProductionDetailView: View {
    let entry: ProductionEntry

    var body: some View {
        List {
            Section {
                infoRow("Ürün Kodu",   value: entry.productCode)
                infoRow("Üretim",      value: entry.totalKg.kgString)
                infoRow("Ton",         value: String(format: "%.2f ton", entry.totalKg / 1000))
                if let fn = entry.formulaName, !fn.isEmpty {
                    infoRow("Formül", value: fn)
                }
            } header: { Text("Ürün Bilgisi") }

            if entry.formulaItems.isEmpty {
                Section {
                    Label("Formül verisi bulunamadı.", systemImage: "exclamationmark.circle")
                        .foregroundColor(.orange)
                }
            } else {
                let hammadde = entry.formulaItems.filter { !$0.isAdditive }
                let katki    = entry.formulaItems.filter {  $0.isAdditive }

                if !hammadde.isEmpty {
                    Section {
                        ForEach(hammadde) { item in detailRow(item) }
                    } header: {
                        HStack {
                            Text("Hammaddeler")
                            Spacer()
                            Text(hammadde.reduce(0) { $0 + $1.totalKg }.kgString)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                if !katki.isEmpty {
                    Section {
                        ForEach(katki) { item in detailRow(item) }
                    } header: {
                        HStack {
                            Text("Katkılar")
                            Spacer()
                            Text(katki.reduce(0) { $0 + $1.totalKg }.kgString)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.productName)
        .navigationBarTitleDisplayMode(.large)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    private func detailRow(_ item: ScaledMaterialItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.materialName).font(.subheadline).fontWeight(.medium)
                Text(item.materialCode).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(item.totalKg.kgString)
                .font(.subheadline).fontWeight(.bold).foregroundColor(.accentColor)
        }
        .padding(.vertical, 3)
    }
}
