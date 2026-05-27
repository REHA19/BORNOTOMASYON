import SwiftUI

struct MarketAnalysisView: View {
    @StateObject private var viewModel = MarketAnalysisViewModel()
    @State private var showAPISetup    = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isOffline, let date = viewModel.cacheDate {
                    OfflineBanner(cacheDate: date)
                }
                content
            }
            .navigationTitle("Piyasa Analizi")
            .toolbar { toolbar }
            .sheet(isPresented: $showAPISetup) {
                APISetupSheet(viewModel: viewModel)
            }
        }
        .task { await viewModel.onAppear() }
    }

    // MARK: - Ana içerik

    private var content: some View {
        List {
            if !viewModel.hasAlphaVantageKey || !viewModel.hasClaudeKey {
                Section { setupBanner }
            }

            // Döviz kuru
            if let rate = viewModel.usdTry {
                Section {
                    HStack {
                        Label("USD/TRY", systemImage: "dollarsign.circle.fill")
                            .foregroundColor(.blue)
                        Spacer()
                        Text("\(String(format: "%.2f", rate)) TL")
                            .font(.headline).fontWeight(.bold)
                    }
                } header: { Label("Döviz Kuru", systemImage: "arrow.left.arrow.right") }
            }

            // CBOT fiyatları
            if !viewModel.commodityPrices.isEmpty {
                Section {
                    cbotCards
                } header: {
                    Label("CBOT/ICE Fiyatları", systemImage: "chart.xyaxis.line")
                }
            }

            // Fabrika hammadde durumu
            stockSection

            // AI satın alma analizi
            aiSection
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - CBOT Kartları

    private var cbotCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.commodityPrices.values.sorted { $0.symbol < $1.symbol }) { price in
                    CBOTCard(price: price)
                }
            }
            .padding(.vertical, 6)
        }
        .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
    }

    // MARK: - Fabrika Hammadde Durumu

    @ViewBuilder
    private var stockSection: some View {
        if viewModel.isLoadingStock && viewModel.marketInfos.isEmpty {
            Section {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Stok verisi yükleniyor…")
                        .font(.caption).foregroundColor(.secondary)
                }
            } header: { Label("Fabrika Hammadde Durumu", systemImage: "shippingbox.fill") }
        } else if !viewModel.marketInfos.isEmpty {
            Section {
                if viewModel.isOffline, let d = viewModel.cacheDate {
                    Label("Önbellekten: \(d.trClock)", systemImage: "wifi.slash")
                        .font(.caption2).foregroundColor(.secondary)
                }
                ForEach(viewModel.marketInfos) { info in
                    MarketInfoRow(info: info, usdTry: viewModel.usdTry)
                }
            } header: {
                HStack {
                    Label("Fabrika Hammadde Durumu", systemImage: "shippingbox.fill")
                    Spacer()
                    if viewModel.isLoadingStock {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
        }
    }

    // MARK: - AI Satın Alma Analizi

    private var aiSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isLoadingAI {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("AI analiz yapıyor…")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else if !viewModel.aiAnalysis.isEmpty {
                    Text(viewModel.aiAnalysis)
                        .font(.subheadline)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundColor(.purple)
                        Text(viewModel.hasClaudeKey
                             ? "CBOT fiyatları + fabrika stoku birleştirilerek alım analizi yapılır."
                             : "Claude API anahtarı gerekli. 🔑 butonundan ekleyin.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    Task {
                        if !viewModel.hasClaudeKey { showAPISetup = true }
                        else { await viewModel.runAIAnalysis() }
                    }
                } label: {
                    Label(
                        viewModel.isLoadingAI ? "Analiz Ediliyor…" : "AI Satın Alma Analizi",
                        systemImage: "sparkles"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(viewModel.isLoadingAI || viewModel.marketInfos.isEmpty)
            }
        } header: {
            Label("AI Satın Alma Analizi", systemImage: "sparkles")
        } footer: {
            Text("CBOT fiyatları + fabrika stok durumu birleştirilerek Claude AI tarafından analiz edilir.")
                .font(.caption2)
        }
    }

    // MARK: - Setup banner

    private var setupBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundColor(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("API anahtarı eksik")
                    .font(.subheadline).fontWeight(.medium)
                Group {
                    if !viewModel.hasAlphaVantageKey { Text("• Alpha Vantage (CBOT fiyatları — ücretsiz)") }
                    if !viewModel.hasClaudeKey        { Text("• Claude (AI alım analizi)") }
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Ayarla") { showAPISetup = true }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let date = viewModel.lastUpdated {
            ToolbarItem(placement: .topBarLeading) {
                Label(date.trClock, systemImage: "clock")
                    .font(.caption2).foregroundColor(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showAPISetup = true } label: { Image(systemName: "key") }
            Button { Task { await viewModel.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(viewModel.isLoadingStock)
        }
    }
}

// MARK: - CBOT Fiyat Kartı

struct CBOTCard: View {
    let price: CommodityPrice

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: price.trend.icon)
                    .foregroundColor(price.trend.color)
                    .font(.system(size: 12))
                Text(price.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            Text(String(format: "$%.2f", price.latestPrice))
                .font(.title3).fontWeight(.bold)
            Text(price.unit)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                if let ch = price.changePercent { trendLabel("Haftalık:", ch) }
                if let ch3 = price.change3Month { trendLabel("Aylık:", ch3) }
            }
        }
        .padding(10)
        .frame(width: 150)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }

    private func trendLabel(_ label: String, _ pct: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            Text("\(pct > 0 ? "+" : "")\(String(format: "%.1f", pct))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(pct > 1 ? .red : pct < -1 ? .green : .orange)
        }
    }
}

// MARK: - Market Info Row

struct MarketInfoRow: View {
    let info:   MaterialMarketInfo
    let usdTry: Double?

    private var mapping: MaterialCommodityInfo? {
        CommodityPriceService.mapping(for: info.material.materialName)
    }

    private var turkeyPriceTL: Double? {
        guard let rate = usdTry,
              let m    = mapping,
              let cbot = info.commodity?.latestPrice else { return nil }
        return CommodityPriceService.estimateTurkeyPrice(
            cbotPricePerBushel: cbot, info: m, usdTry: rate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.material.materialName)
                        .font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    if let m = mapping {
                        Text(m.displayName)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let days = info.stockDays {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(days.rounded())) gün")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(info.urgency.color)
                        Text("kaldı").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                if let c = info.commodity {
                    HStack(spacing: 4) {
                        Image(systemName: c.trend.icon).font(.system(size: 9))
                        Text(c.trend.label).font(.system(size: 10, weight: .semibold))
                        if let ch = c.changePercent {
                            Text("(\(ch > 0 ? "+" : "")\(String(format: "%.1f", ch))%)")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(c.trend.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(c.trend.color.opacity(0.1))
                    .clipShape(Capsule())
                }
                if let tlPrice = turkeyPriceTL {
                    let rounded = (tlPrice / 100).rounded() * 100
                    Text("~\(Int(rounded)) TL/ton")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
                Spacer()
                Label(info.recommendation.label, systemImage: info.recommendation.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(info.recommendation.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(info.recommendation.color.opacity(0.12))
                    .clipShape(Capsule())
            }

            if let m = mapping {
                Text(m.relationship)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - API Kurulum Sayfası

struct APISetupSheet: View {
    @ObservedObject var viewModel: MarketAnalysisViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var avKey = ""
    @State private var clKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alpha Vantage").font(.subheadline).fontWeight(.medium)
                        Text("Ücretsiz CBOT tahıl fiyatları (Mısır, Buğday, Şeker, Pamuk)")
                            .font(.caption).foregroundColor(.secondary)
                        Text("alphavantage.co → ücretsiz kayıt")
                            .font(.caption2).foregroundColor(.blue)
                    }
                    .padding(.vertical, 2)
                    SecureField("Alpha Vantage API Key", text: $avKey)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: { Label("Piyasa Fiyatları", systemImage: "chart.xyaxis.line") }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anthropic Claude").font(.subheadline).fontWeight(.medium)
                        Text("CBOT fiyatları + fabrika stoku birleştirerek AI alım analizi yapar.")
                            .font(.caption).foregroundColor(.secondary)
                        Text("console.anthropic.com → claude-haiku-4-5")
                            .font(.caption2).foregroundColor(.blue)
                    }
                    .padding(.vertical, 2)
                    SecureField("Claude API Key (sk-ant-...)", text: $clKey)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: { Label("AI Analiz", systemImage: "sparkles") }

                Section {
                    Text("Anahtarlar yalnızca bu cihazda saklanır.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("API Anahtarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") {
                        if !avKey.trimmingCharacters(in: .whitespaces).isEmpty { viewModel.alphaVantageKey = avKey }
                        if !clKey.trimmingCharacters(in: .whitespaces).isEmpty { viewModel.claudeKey = clKey }
                        dismiss()
                        Task { await viewModel.refresh() }
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { avKey = viewModel.alphaVantageKey; clKey = viewModel.claudeKey }
        }
    }
}
