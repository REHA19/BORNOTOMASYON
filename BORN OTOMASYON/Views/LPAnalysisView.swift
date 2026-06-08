import SwiftUI
import SwiftData
import Charts

// MARK: - Ana Menü Girişi: Formül Seçici

struct LPAnalysisMenuView: View {
    @Query private var formulas:  [BlendFormula]
    @Query private var allGroups: [MultiBlendGroup]

    private var solvedFormulas: [BlendFormula] {
        formulas.filter { $0.lastSolve != nil }.sorted { $0.name < $1.name }
    }

    /// Bu formülün ait olduğu MultiBlend grup sayısı
    private func groupCount(for formula: BlendFormula) -> Int {
        allGroups.filter { $0.formulaCodes.contains(formula.code) }.count
    }

    /// Son çözümde kritik risk seviyesindeki hammadde sayısı (tolerans < %5)
    private func criticalCount(for formula: BlendFormula) -> Int {
        guard let solve = formula.lastSolve else { return 0 }
        return solve.costRangeIncreases.filter { _, maxInc in
            let price = formulas.first { $0.code == formula.code }? // kendi fiyatını bul — yaklaşık
                .ingredients.first { _ in true }?.overridePriceTLPerTon ?? 0
            _ = price
            return maxInc != .infinity && maxInc / max(1, maxInc + 1) < 0.05
        }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if solvedFormulas.isEmpty {
                    ContentUnavailableView(
                        "Çözülmüş Formül Yok",
                        systemImage: "function",
                        description: Text("SingleBlend veya MultiBlend'den bir formül çözünce burada analiz edilebilir.")
                    )
                } else {
                    List(solvedFormulas) { formula in
                        NavigationLink(destination: LPAnalysisView(formula: formula)) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(formula.name).font(.subheadline.bold())
                                    Text(formula.code).font(.caption).foregroundStyle(.secondary)
                                    if let s = formula.lastSolve {
                                        Text(String(format: "Son çözüm: %.0f ₺/ton — %@",
                                                    s.costPerTon,
                                                    s.solvedAt.formatted(date: .abbreviated, time: .omitted)))
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                // MultiBlend + kritik uyarı rozetleri
                                VStack(alignment: .trailing, spacing: 4) {
                                    let gc = groupCount(for: formula)
                                    if gc > 0 {
                                        Label("\(gc)", systemImage: "rectangle.3.group.fill")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.indigo)
                                            .labelStyle(.titleAndIcon)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("LP Analizi")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Formüle Özgü Analiz (5 Sekme)

struct LPAnalysisView: View {
    let formula: BlendFormula

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // 5 sekmeyi scrollable segmented picker ile göster
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([
                        (0, "📉 İnd. Maliyet"),
                        (1, "🔍 Kısıt Baskısı"),
                        (2, "⚠️ Risk"),
                        (3, "📋 Değişim"),
                        (4, "🔗 MultiBlend")
                    ], id: \.0) { tag, label in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tag }
                        } label: {
                            Text(label)
                                .font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(
                                    selectedTab == tag
                                        ? Color.blue : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                                .foregroundStyle(selectedTab == tag ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            Divider()

            switch selectedTab {
            case 0: ReducedCostTab(formula: formula)
            case 1: ConstraintShadowPriceTab(formula: formula)
            case 2: SensitivityRiskTab(formula: formula)
            case 3: ComparisonTab(formula: formula)
            default: MultiBlendContextTab(formula: formula)
            }
        }
        .navigationTitle(formula.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sekme 0: İndirgenmış Maliyet (Rasyona girmeyen hammaddeler)

private struct ReducedCostTab: View {
    let formula: BlendFormula
    @Query private var library: [FeedIngredient]

    struct ShadowRow: Identifiable {
        let id = UUID()
        let name:         String
        let code:         String
        let currentPrice: Double
        let requiredDrop: Double
        let hasStock:     Bool
        let hasMinPct:    Bool    // formülde MIN kısıtı tanımlı ama yine de dışarıda
        var targetPrice:  Double { max(0, currentPrice - requiredDrop) }
        var urgencyPct:   Double { requiredDrop / max(currentPrice, 1) }
        var urgencyColor: Color {
            if urgencyPct < 0.05  { return .green }
            if urgencyPct < 0.15  { return .orange }
            return .red
        }
        var urgencyLabel: String {
            if urgencyPct < 0.05  { return "Hemen Aday" }
            if urgencyPct < 0.15  { return "Orta Mesafe" }
            return "Uzak"
        }
    }

    private struct ChartSegment: Identifiable {
        let id      = UUID()
        let ingName: String
        let segment: String
        let value:   Double
    }

    private var rows: [ShadowRow] {
        guard let solve = formula.lastSolve else { return [] }
        return solve.reducedCosts
            .compactMap { code, drop -> ShadowRow? in
                guard drop > 0.5 else { return nil }
                let ing   = formula.ingredients.first { $0.code == code }
                let name  = ing?.name ?? library.first { $0.code == code }?.name ?? code
                let price = library.first { $0.code == code }?.priceTL
                         ?? ing?.overridePriceTLPerTon ?? 0
                let hasStock  = library.first { $0.code == code }?.isAvailable ?? true
                let hasMinPct = (ing?.minPct ?? 0) > 0.001
                return ShadowRow(name: name, code: code, currentPrice: price,
                                 requiredDrop: drop, hasStock: hasStock, hasMinPct: hasMinPct)
            }
            .sorted { $0.requiredDrop < $1.requiredDrop }
    }

    private var chartData: [ChartSegment] {
        rows.prefix(10).flatMap { row -> [ChartSegment] in
            let short = row.name.count > 15 ? String(row.name.prefix(14)) + "…" : row.name
            return [
                ChartSegment(ingName: short, segment: "Eşik Fiyat",    value: max(0, row.targetPrice)),
                ChartSegment(ingName: short, segment: "Gereken Düşüş", value: row.requiredDrop)
            ]
        }
    }

    private var closestRow:  ShadowRow? { rows.first }
    private var nearCount:   Int        { rows.filter { $0.urgencyPct < 0.05 }.count }
    private var avgDropPct:  Double {
        guard !rows.isEmpty else { return 0 }
        return rows.map(\.urgencyPct).reduce(0, +) / Double(rows.count) * 100
    }

    var body: some View {
        List {
            if rows.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                        Text("Tüm aktif hammaddeler rasyonda kullanılıyor ya da sensitivity verisi henüz yok.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                // ── Özet Kart ────────────────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Maliyet Sınırı Analizi")
                                    .font(.headline)
                                Text("Rasyona girmeyen \(rows.count) hammadde — hangi fiyata inerlerse girebilir?")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chart.bar.xaxis.ascending")
                                .font(.title2).foregroundStyle(.blue)
                        }

                        Divider()

                        HStack(spacing: 0) {
                            if let best = closestRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("En Yakın").font(.caption2).foregroundStyle(.secondary)
                                    Text(String(best.name.prefix(16)))
                                        .font(.caption.bold()).lineLimit(1)
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(best.urgencyColor).font(.caption2)
                                        Text(String(format: "−%.0f ₺/ton", best.requiredDrop))
                                            .font(.caption.bold().monospacedDigit())
                                            .foregroundStyle(best.urgencyColor)
                                    }
                                }
                            }
                            Spacer()
                            Divider().frame(height: 36)
                            Spacer()
                            VStack(alignment: .center, spacing: 2) {
                                Text("Hemen Aday").font(.caption2).foregroundStyle(.secondary)
                                Text("\(nearCount)")
                                    .font(.title3.bold())
                                    .foregroundStyle(nearCount > 0 ? .green : .secondary)
                                Text("< %5 düşüş yeter").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Divider().frame(height: 36)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Ort. Düşüş").font(.caption2).foregroundStyle(.secondary)
                                Text(String(format: "%%%.1f", avgDropPct))
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(avgDropPct < 5 ? .green : avgDropPct < 15 ? .orange : .red)
                                Text("gerekli").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.blue.opacity(0.05))

                // ── Grafik ───────────────────────────────────────────────────
                Section("Eşik Fiyat Grafiği (İlk \(min(rows.count, 10)))") {
                    Chart(chartData) { seg in
                        BarMark(x: .value("₺/ton", seg.value),
                                y: .value("Hammadde", seg.ingName))
                            .foregroundStyle(by: .value("Segment", seg.segment))
                            .cornerRadius(3)
                    }
                    .chartForegroundStyleScale([
                        "Eşik Fiyat":    Color.blue.opacity(0.65),
                        "Gereken Düşüş": Color.red.opacity(0.30)
                    ])
                    .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
                    .chartXAxis {
                        AxisMarks { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = val.as(Double.self) {
                                    Text(v >= 1000
                                         ? String(format: "%.0fK", v / 1000)
                                         : String(format: "%.0f", v))
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(min(rows.count, 10)) * 34 + 48)
                    .padding(.vertical, 4)

                    Text("🔵 Eşik Fiyat = Bu fiyata düşerse rasyona girer   🔴 Gereken Düşüş = Şu anki fazlalık")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // ── Detay Listesi ────────────────────────────────────────────
                Section("Hammadde Detayları (\(rows.count))") {
                    ForEach(rows) { row in
                        ReducedCostRow(row: row)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ReducedCostRow: View {
    let row: ReducedCostTab.ShadowRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Başlık satırı
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.name).font(.subheadline.bold())
                        // Stok rozeti
                        if !row.hasStock {
                            Text("STOK YOK")
                                .font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.red, in: Capsule())
                        }
                    }
                    Text(row.code).font(.caption2).foregroundStyle(.secondary)
                    // MIN kısıtı var ama dışarıda uyarısı
                    if row.hasMinPct {
                        Label("MIN kısıtı var ama maliyet hâlâ yüksek", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.urgencyLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(row.urgencyColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(row.urgencyColor)
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(row.urgencyColor)
                        Text(String(format: "−%.0f ₺/ton", row.requiredDrop))
                            .font(.subheadline.bold().monospacedDigit()).foregroundStyle(row.urgencyColor)
                    }
                    Text(String(format: "%%%.1f düşüş gerek", row.urgencyPct * 100))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            // Pratik aksiyon metni
            if row.currentPrice > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "target").foregroundStyle(.blue).font(.caption)
                    Text(String(format: "Fiyat %.0f ₺/ton'a inerse rasyona girebilir  (şu an: %.0f ₺/ton)",
                                row.targetPrice, row.currentPrice))
                        .font(.caption).foregroundStyle(.blue)
                }

                // Görsel bar
                GeometryReader { geo in
                    let safeFrac = CGFloat(row.targetPrice / max(row.currentPrice, 1))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.15)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.55))
                            .frame(width: geo.size.width * safeFrac, height: 8)
                        Rectangle().fill(Color.blue).frame(width: 2, height: 14)
                            .offset(x: geo.size.width * safeFrac - 1)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("0 ₺").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Spacer()
                    Text(String(format: "Eşik: %.0f ₺", row.targetPrice))
                        .font(.system(size: 9)).foregroundStyle(.blue)
                    Spacer()
                    Text(String(format: "%.0f ₺", row.currentPrice))
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Sekme 1: Kısıt Baskısı (Shadow Price — daha açıklayıcı)

private struct ConstraintShadowPriceTab: View {
    let formula: BlendFormula

    struct ShadowEntry: Identifiable {
        let id = UUID()
        let nutrientKey:  String
        let displayName:  String
        let unit:         String
        let isMinBound:   Bool
        let shadowPrice:  Double   // ₺/ton — kısıtı 1 birim gevşetince tasarruf
        let currentValue: Double?
        let boundValue:   Double
        // Doluluk: currentValue / boundValue (0-1, 1 = tam sınırda)
        var fillRatio: Double {
            guard let cur = currentValue, boundValue > 0.001 else { return 0 }
            return isMinBound ? cur / boundValue : boundValue / cur
        }
        var impactColor: Color {
            if shadowPrice > 200 { return .red }
            if shadowPrice > 50  { return .orange }
            return .yellow
        }
        var impactLabel: String {
            if shadowPrice > 200 { return "Yüksek Baskı" }
            if shadowPrice > 50  { return "Orta Baskı" }
            return "Düşük Baskı"
        }
        // Öneri metni
        var suggestion: String {
            let boundStr = String(format: "%.2f %@", boundValue, unit)
            if isMinBound {
                let relaxed = boundValue * 0.97  // %3 gevşetme
                return String(format: "Min kısıtı %.2f %@'dan %.2f'ye düşürülürse ₺%.0f/ton tasarruf",
                              boundValue, unit, relaxed, shadowPrice * (boundValue - relaxed))
            } else {
                let relaxed = boundValue * 1.03
                return String(format: "Max kısıtı %@ → %.2f'ye yükseltilirse ₺%.0f/ton tasarruf",
                              boundStr, relaxed, shadowPrice * (relaxed - boundValue))
            }
        }
    }

    private var entries: [ShadowEntry] {
        guard let solve = formula.lastSolve else { return [] }
        var result: [ShadowEntry] = []

        for (key, sp) in solve.shadowPricesMin {
            guard sp > 0.01 else { continue }
            let con = formula.constraints.first { $0.nutrientKey == key }
            let def = allNutrientDefs.first { $0.key == key }
            result.append(ShadowEntry(
                nutrientKey:  key,
                displayName:  con?.resolvedDisplayName ?? def?.displayName ?? key,
                unit:         con?.unit ?? def?.unit ?? "",
                isMinBound:   true,
                shadowPrice:  sp,
                currentValue: con?.currentValue,
                boundValue:   con?.minValue ?? 0
            ))
        }
        for (key, sp) in solve.shadowPricesMax {
            guard sp > 0.01 else { continue }
            let con = formula.constraints.first { $0.nutrientKey == key }
            let def = allNutrientDefs.first { $0.key == key }
            result.append(ShadowEntry(
                nutrientKey:  key,
                displayName:  con?.resolvedDisplayName ?? def?.displayName ?? key,
                unit:         con?.unit ?? def?.unit ?? "",
                isMinBound:   false,
                shadowPrice:  sp,
                currentValue: con?.currentValue,
                boundValue:   con?.maxValue ?? 0
            ))
        }
        return result.sorted { $0.shadowPrice > $1.shadowPrice }
    }

    // Toplam baskı: en pahalı kısıtların maliyet toplamı
    private var totalPressure: Double { entries.prefix(5).map(\.shadowPrice).reduce(0, +) }

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hiçbir kısıt bağlayıcı değil").font(.subheadline.bold())
                            Text("Tüm besin sınırları rahat — formülün maliyetini kısıtlar değil, piyasa fiyatları belirliyor.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                // ── Açıklama + Özet ─────────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Kısıt Baskısı Analizi").font(.headline)
                                Text("Bağlayıcı besin kısıtları formül maliyetini artırıyor.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "lock.fill").font(.title2).foregroundStyle(.orange)
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("En Baskılı").font(.caption2).foregroundStyle(.secondary)
                                Text(entries.first?.displayName ?? "—")
                                    .font(.caption.bold()).lineLimit(1)
                                Text(String(format: "%.1f ₺/ton", entries.first?.shadowPrice ?? 0))
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(entries.first?.impactColor ?? .secondary)
                            }
                            Spacer()
                            Divider().frame(height: 36)
                            Spacer()
                            VStack(alignment: .center, spacing: 2) {
                                Text("Bağlayıcı Kısıt").font(.caption2).foregroundStyle(.secondary)
                                Text("\(entries.count)").font(.title3.bold())
                                Text("adet").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Divider().frame(height: 36)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("İlk 5 Top.").font(.caption2).foregroundStyle(.secondary)
                                Text(String(format: "%.0f ₺", totalPressure))
                                    .font(.title3.bold().monospacedDigit()).foregroundStyle(.red)
                                Text("maliyet baskısı").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.orange.opacity(0.05))

                // ── Kısıt Listesi ────────────────────────────────────────────
                Section("Bağlayıcı Kısıtlar (\(entries.count)) — Baskı yüksekten düşüğe") {
                    ForEach(entries) { entry in
                        ConstraintPressureRow(entry: entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ConstraintPressureRow: View {
    let entry: ConstraintShadowPriceTab.ShadowEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Başlık
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.displayName).font(.subheadline.bold())
                        Text(entry.isMinBound ? "MIN" : "MAX")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(entry.isMinBound
                                ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                            .foregroundStyle(entry.isMinBound ? .blue : .purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(entry.impactLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(entry.impactColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(entry.impactColor)
                    }
                    if let cur = entry.currentValue {
                        Text(String(format: "Mevcut: %.3f %@  |  Sınır: %.3f %@",
                                    cur, entry.unit, entry.boundValue, entry.unit))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f ₺/ton", entry.shadowPrice))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(entry.impactColor)
                    Text("ton başı tasarruf").font(.caption2).foregroundStyle(.secondary)
                    Text("sınır 1 birim gevşese").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            // Doluluk barı — ne kadar sıkışık?
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Kısıta Ne Kadar Yakın?").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%%%.0f", entry.fillRatio * 100))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(entry.fillRatio > 0.95 ? entry.impactColor : .secondary)
                }
                GeometryReader { geo in
                    let frac = CGFloat(min(entry.fillRatio, 1.0))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.impactColor.opacity(0.75))
                            .frame(width: geo.size.width * frac, height: 6)
                        // %100 çizgisi
                        if entry.fillRatio > 0.9 {
                            Rectangle().fill(entry.impactColor).frame(width: 2, height: 12)
                                .offset(x: geo.size.width - 2)
                        }
                    }
                }
                .frame(height: 6)
            }

            // Sade Türkçe yorum
            let dir = entry.isMinBound ? "MIN değeri düşürülürse" : "MAX değeri artırılırsa"
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.caption2)
                Text(String(format: "%@ → ton başı maliyetten %.1f ₺ tasarruf edilebilir.",
                            dir, entry.shadowPrice))
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Öneri
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue.opacity(0.7)).font(.caption2)
                Text(entry.suggestion).font(.caption2).foregroundStyle(.blue.opacity(0.8))
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Sekme 2: Risk (Sensitivity — triage ile)

private struct SensitivityRiskTab: View {
    let formula: BlendFormula
    @Query private var library:   [FeedIngredient]
    @Query private var allGroups: [MultiBlendGroup]

    struct RiskRow: Identifiable {
        let id = UUID()
        let name:         String
        let code:         String
        let currentPrice: Double
        let mixPct:       Double
        let maxIncrease:  Double
        var riskLevel: RiskLevel {
            if maxIncrease == .infinity { return .safe }
            let pct = maxIncrease / max(currentPrice, 1)
            if pct < 0.05 { return .critical }
            if pct < 0.20 { return .warning }
            return .safe
        }
        var ceilingPrice: Double { currentPrice + (maxIncrease == .infinity ? 0 : maxIncrease) }
    }

    enum RiskLevel { case critical, warning, safe }

    private var rows: [RiskRow] {
        guard let solve = formula.lastSolve else { return [] }
        return solve.costRangeIncreases
            .compactMap { code, maxInc -> RiskRow? in
                let ing    = formula.ingredients.first { $0.code == code }
                let name   = ing?.name ?? library.first { $0.code == code }?.name ?? code
                let price  = library.first { $0.code == code }?.priceTL
                           ?? ing?.overridePriceTLPerTon ?? 0
                let mixPct = ing?.mixPct ?? 0
                guard mixPct > 0.01 else { return nil }
                return RiskRow(name: name, code: code, currentPrice: price,
                               mixPct: mixPct, maxIncrease: maxInc)
            }
            .sorted { $0.maxIncrease < $1.maxIncrease }
    }

    private var criticalRows: [RiskRow] { rows.filter { $0.riskLevel == .critical } }
    private var warningRows:  [RiskRow] { rows.filter { $0.riskLevel == .warning  } }
    private var safeRows:     [RiskRow] { rows.filter { $0.riskLevel == .safe     } }

    /// Bu formülün bulunduğu gruplar ve o gruplardaki diğer formül kodları
    private var groupsContainingFormula: [MultiBlendGroup] {
        allGroups.filter { $0.formulaCodes.contains(formula.code) }
    }

    /// code → bu kodu kullanan grup sayısı
    private func groupUsageCount(code: String) -> Int {
        allGroups.filter { grp in
            grp.formulaCodes.contains(formula.code) && grp.formulaCodes.contains(code)
        }.count
    }

    var body: some View {
        List {
            if rows.isEmpty {
                Section {
                    Text("Sensitivity verisi bulunamadı. Önce formülü çözün.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                // ── Özet ────────────────────────────────────────────────────
                Section {
                    HStack(spacing: 16) {
                        riskSummaryBadge(count: criticalRows.count, level: .critical, label: "Kritik")
                        Divider().frame(height: 40)
                        riskSummaryBadge(count: warningRows.count,  level: .warning,  label: "Uyarı")
                        Divider().frame(height: 40)
                        riskSummaryBadge(count: safeRows.count,     level: .safe,     label: "Güvenli")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                // ── Kritik ──────────────────────────────────────────────────
                if !criticalRows.isEmpty {
                    Section {
                        ForEach(criticalRows) { row in
                            RiskRowView(row: row, groupCount: groupUsageCount(code: row.code))
                        }
                    } header: {
                        Label("🔴 Kritik (\(criticalRows.count)) — Fiyat biraz artarsa rasyondan çıkar",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold()).foregroundStyle(.red).textCase(nil)
                    }
                }

                // ── Uyarı ───────────────────────────────────────────────────
                if !warningRows.isEmpty {
                    Section {
                        ForEach(warningRows) { row in
                            RiskRowView(row: row, groupCount: groupUsageCount(code: row.code))
                        }
                    } header: {
                        Label("🟡 Uyarı (\(warningRows.count)) — Belirli bir fiyat artışına dayanabilir",
                              systemImage: "exclamationmark.circle")
                            .font(.caption.bold()).foregroundStyle(.orange).textCase(nil)
                    }
                }

                // ── Güvenli ─────────────────────────────────────────────────
                if !safeRows.isEmpty {
                    Section {
                        ForEach(safeRows) { row in
                            RiskRowView(row: row, groupCount: groupUsageCount(code: row.code))
                        }
                    } header: {
                        Label("🟢 Güvenli (\(safeRows.count)) — Fiyat artışına karşı dayanıklı",
                              systemImage: "checkmark.shield")
                            .font(.caption.bold()).foregroundStyle(.green).textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func riskSummaryBadge(count: Int, level: RiskLevel, label: String) -> some View {
        let color: Color = level == .critical ? .red : level == .warning ? .orange : .green
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(count > 0 ? color : .secondary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RiskRowView: View {
    let row:        SensitivityRiskTab.RiskRow
    let groupCount: Int   // kaç MultiBlend grubunda bu hammadde ortak kullanılıyor

    private var color: Color {
        switch row.riskLevel {
        case .critical: return .red
        case .warning:  return .orange
        case .safe:     return .green
        }
    }
    private var icon: String {
        switch row.riskLevel {
        case .critical: return "xmark.circle.fill"
        case .warning:  return "exclamationmark.circle.fill"
        case .safe:     return row.maxIncrease == .infinity ? "checkmark.shield.fill" : "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.subheadline.bold())
                    // MultiBlend uyarı rozeti
                    if groupCount > 0 {
                        Label("\(groupCount) grup", systemImage: "rectangle.3.group.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.1), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(String(format: "Oran: %.1f%%", row.mixPct))
                        .font(.caption2).foregroundStyle(.secondary)
                    if row.currentPrice > 0 {
                        Text(String(format: "Fiyat: %.0f ₺/ton", row.currentPrice))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                // Pratik metin
                if row.maxIncrease == .infinity {
                    Text("Her fiyat seviyesinde rasyonda kalır — son derece stabil.")
                        .font(.caption2).foregroundStyle(.green)
                } else {
                    let absInc = row.maxIncrease
                    Text(String(format: "Fiyatı +%.0f ₺/ton (→ %.0f ₺) artarsa rasyondan çıkar.",
                                absInc, row.ceilingPrice))
                        .font(.caption2).foregroundStyle(color)
                    // Grup uyarısı
                    if groupCount > 0 {
                        Text(String(format: "⚠️ Bu hammadde %d MultiBlend grubunda da kullanılıyor — fiyat değişimi tüm grubu etkiler.", groupCount))
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if row.maxIncrease != .infinity {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "+%.0f ₺", row.maxIncrease))
                        .font(.subheadline.bold().monospacedDigit()).foregroundStyle(color)
                    Text("tolerans").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Sekme 3: Değişim (Karşılaştırma + Maliyet Etkisi)

private struct ComparisonTab: View {
    let formula: BlendFormula
    @Query private var library: [FeedIngredient]

    private var changedIngredients: [BFIngredient] {
        formula.ingredients.filter { $0.previousMixPct > 0 || $0.mixPct > 0 }
            .sorted { abs($0.mixPct - $0.previousMixPct) > abs($1.mixPct - $1.previousMixPct) }
    }

    private var changedConstraints: [BFConstraint] {
        formula.constraints.filter { $0.isActive && ($0.currentValue != nil || $0.previousValue != nil) }
    }

    // Son ve önceki maliyet
    private var currentCost:  Double { formula.lastSolve?.costPerTon ?? 0 }
    private var previousCost: Double {
        // previousValue olan herhangi bir kısıttan tersine hesap yapmak zor,
        // bunun yerine kaydedilen recordedCostTL kullanılır
        // Ancak biz lastSolve.costPerTon'u "current" olarak kullanıyoruz.
        // "Önceki" = formülün ingredients[].previousMixPct üzerinden hesaplanacak
        // Basit yaklaşım: currentCost'u referans göster, değişim metni yeterli.
        0.0
    }

    // Maliyet etkisi hesabı: Δ% × price/100 × totalKg / 1000 (₺ cinsinden aylık)
    private func costImpact(ing: BFIngredient) -> Double {
        let price = library.first { $0.code == ing.code }?.priceTL
                  ?? ing.overridePriceTLPerTon ?? 0
        guard price > 0 else { return 0 }
        let deltaPct = ing.mixPct - ing.previousMixPct
        return deltaPct / 100.0 * formula.totalKg / 1000.0 * price
    }

    var body: some View {
        List {
            // ── Maliyet Özeti ────────────────────────────────────────────────
            if currentCost > 0 {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Son Çözüm Maliyeti").font(.subheadline.bold())
                            if let s = formula.lastSolve {
                                Text(s.solvedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(String(format: "%.0f ₺/ton", currentCost))
                            .font(.title3.bold().monospacedDigit()).foregroundStyle(.orange)
                    }
                }
                .listRowBackground(Color.orange.opacity(0.05))
            }

            // ── Hammadde Oranları ────────────────────────────────────────────
            Section("Hammadde Oranları — Önceki vs Şimdiki") {
                if changedIngredients.isEmpty {
                    Text("Karşılaştırılacak önceki çözüm verisi yok.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(changedIngredients) { ing in
                        let diff   = ing.mixPct - ing.previousMixPct
                        let isNew  = ing.previousMixPct < 0.01 && ing.mixPct > 0.01
                        let isGone = ing.mixPct < 0.01 && ing.previousMixPct > 0.01
                        let impact = costImpact(ing: ing)
                        HStack(spacing: 10) {
                            if isNew {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            } else if isGone {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            } else if abs(diff) < 0.1 {
                                Image(systemName: "minus").foregroundStyle(.secondary).font(.caption)
                            } else {
                                Image(systemName: diff > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundStyle(diff > 0 ? .green : .red)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ing.name).font(.subheadline)
                                if isNew   { Text("Yeni girdi").font(.caption2).foregroundStyle(.green) }
                                if isGone  { Text("Rasyondan çıktı").font(.caption2).foregroundStyle(.red) }
                                // Maliyet etkisi
                                if abs(impact) > 0.5 {
                                    HStack(spacing: 3) {
                                        Image(systemName: impact > 0 ? "arrow.up" : "arrow.down")
                                            .font(.system(size: 8, weight: .bold))
                                        Text(String(format: "%+.0f ₺ maliyet etkisi (bu parti)", impact))
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(impact > 0 ? .red : .green)
                                }
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                if ing.previousMixPct > 0.01 {
                                    Text(String(format: "%.1f%%", ing.previousMixPct))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                }
                                Text(String(format: "%.1f%%", ing.mixPct))
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(isGone ? .red : isNew ? .green :
                                                     abs(diff) < 0.1 ? .primary : diff > 0 ? .green : .red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // ── Besin Değerleri ──────────────────────────────────────────────
            if !changedConstraints.isEmpty {
                Section("Besin Değerleri — Önceki vs Şimdiki") {
                    ForEach(changedConstraints, id: \.id) { con in
                        ComparisonConstraintRow(con: con)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ComparisonConstraintRow: View {
    let con: BFConstraint

    var body: some View {
        let cur     = con.currentValue ?? 0
        let prev    = con.previousValue
        let inRange = (con.minValue.map { cur >= $0 - 0.001 } ?? true)
                   && (con.maxValue.map { cur <= $0 + 0.001 } ?? true)
        HStack(spacing: 10) {
            Image(systemName: inRange ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(inRange ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(con.resolvedDisplayName).font(.subheadline)
                HStack(spacing: 4) {
                    if let mn = con.minValue {
                        Text(String(format: "Min: %.2f", mn))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let mx = con.maxValue {
                        Text(String(format: "Max: %.2f", mx))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if !inRange {
                        Text("SINIR DIŞI").font(.caption2.bold()).foregroundStyle(.red)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if let p = prev {
                    Text(String(format: "%.3f", p))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(String(format: "%.3f %@", cur, con.unit))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(inRange ? Color.primary : Color.red)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sekme 4: MultiBlend Bağlamı

private struct MultiBlendContextTab: View {
    let formula: BlendFormula

    @Query(sort: \MultiBlendGroup.orderIndex) private var allGroups:   [MultiBlendGroup]
    @Query                                    private var allFormulas: [BlendFormula]
    @Query                                    private var library:     [FeedIngredient]

    /// Bu formülün bulunduğu gruplar
    private var myGroups: [MultiBlendGroup] {
        allGroups.filter { $0.formulaCodes.contains(formula.code) }
    }

    /// Gruptaki tüm formüllerin ingredient kodlarını birleştir (ortak hammadde analizi için)
    private func commonIngredients(in group: MultiBlendGroup) -> [CommonIngEntry] {
        let groupFormulas = group.formulaCodes.compactMap { code in
            allFormulas.first { $0.code == code }
        }
        guard groupFormulas.count > 1 else { return [] }

        // Kaç formülde geçiyor?
        var countMap: [String: Int] = [:]
        var nameMap:  [String: String] = [:]
        for f in groupFormulas {
            var seen = Set<String>()
            for ing in f.ingredients where !seen.contains(ing.code) {
                seen.insert(ing.code)
                countMap[ing.code, default: 0] += 1
                nameMap[ing.code] = ing.name
            }
        }

        // Aylık kullanım
        let tons = group.productionTons
        let result: [CommonIngEntry] = countMap.compactMap { code, cnt in
            guard cnt > 1 else { return nil }   // sadece birden fazla formülde olanlar
            let name     = nameMap[code] ?? library.first { $0.code == code }?.name ?? code
            let monthlyT = groupFormulas.reduce(0.0) { sum, f in
                let pct  = f.ingredients.first { $0.code == code }?.mixPct ?? 0
                let fTon = tons[f.code] ?? 0
                return sum + pct / 100.0 * fTon
            }
            let limit    = group.monthlyIngLimits[code]
            let maxTons  = limit?.maxTons
            let hasStock = library.first { $0.code == code }?.isAvailable ?? true
            // Bu formüldeki sensitivity verisi var mı?
            let sensitivity = formula.lastSolve?.costRangeIncreases[code]
            return CommonIngEntry(code: code, name: name, formulaCount: cnt,
                                  monthlyTons: monthlyT, maxTons: maxTons,
                                  hasStock: hasStock, sensitivity: sensitivity)
        }
        .sorted { ($0.maxTons != nil ? 1 : 0) > ($1.maxTons != nil ? 1 : 0) || $0.monthlyTons > $1.monthlyTons }
        return result
    }

    var body: some View {
        List {
            if myGroups.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Bu formül henüz bir MultiBlend grubuna eklenmemiş.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text("MultiBlend → grup → + butonu ile ekleyebilirsiniz.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(myGroups) { group in
                    groupSection(group)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func groupSection(_ group: MultiBlendGroup) -> some View {
        let groupFormulas = group.formulaCodes.compactMap { code in
            allFormulas.first { $0.code == code }
        }
        let tons     = group.productionTons
        let myTons   = tons[formula.code] ?? 0
        let totalT   = groupFormulas.compactMap { tons[$0.code] }.reduce(0, +)
        let myShare  = totalT > 0 ? myTons / totalT * 100 : 0
        let common   = commonIngredients(in: group)

        Section {
            // ── Grup genel bilgisi ──────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.title3).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name).font(.subheadline.bold())
                    Text("\(groupFormulas.count) formül  •  toplam \(String(format: "%.1f", totalT)) ton/ay")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f ton", myTons))
                        .font(.subheadline.bold().monospacedDigit()).foregroundStyle(.orange)
                    Text(String(format: "%%%.0f pay", myShare))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            // ── Diğer formüller (compact) ──────────────────────────────────
            if groupFormulas.count > 1 {
                DisclosureGroup {
                    ForEach(groupFormulas) { f in
                        let fTons = tons[f.code] ?? 0
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(.caption.bold())
                                    .foregroundStyle(f.code == formula.code ? .blue : .primary)
                                Text(f.code).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f ton", fTons))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(f.code == formula.code ? .orange : .secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    Label("Gruptaki Formüller (\(groupFormulas.count))", systemImage: "list.bullet")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                }
            }

            // ── Ortak Hammaddeler ──────────────────────────────────────────
            if !common.isEmpty {
                DisclosureGroup(content: {
                    ForEach(common) { ing in
                        CommonIngRow(entry: ing, totalTons: totalT)
                    }
                }, label: {
                    HStack {
                        Label("Ortak Hammaddeler (\(common.count))", systemImage: "arrow.triangle.merge")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        // Limit baskısı olanları say
                        let limitCount = common.filter { e in
                            guard let maxT = e.maxTons, e.monthlyTons > 0 else { return false }
                            return e.monthlyTons / maxT > 0.8
                        }.count
                        if limitCount > 0 {
                            Label("\(limitCount)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.bold()).foregroundStyle(.orange)
                        }
                    }
                })
            }

        } header: {
            HStack {
                Image(systemName: "rectangle.3.group.fill").foregroundStyle(.indigo)
                Text(group.name).font(.subheadline.bold()).textCase(nil)
            }
        }
    }
}

// MARK: - Ortak hammadde satırı

private struct CommonIngEntry: Identifiable {
    let id          = UUID()
    let code:        String
    let name:        String
    let formulaCount: Int      // kaç formülde kullanılıyor (bu grupta)
    let monthlyTons: Double
    let maxTons:     Double?
    let hasStock:    Bool
    let sensitivity: Double?   // costRangeIncreases — bu formüldeki fiyat toleransı
    var limitFill: Double? {
        guard let mx = maxTons, mx > 0 else { return nil }
        return monthlyTons / mx
    }
    var limitColor: Color {
        guard let f = limitFill else { return .green }
        if f > 0.9 { return .red }
        if f > 0.7 { return .orange }
        return .green
    }
}

private struct CommonIngRow: View {
    let entry:      CommonIngEntry
    let totalTons:  Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name).font(.caption.bold())
                        if !entry.hasStock {
                            Text("STOK YOK").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.red, in: Capsule())
                        }
                    }
                    Text("\(entry.formulaCount) formülde kullanılıyor")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if entry.monthlyTons > 0 {
                        Text(String(format: "%.2f ton/ay", entry.monthlyTons))
                            .font(.caption.bold().monospacedDigit()).foregroundStyle(.primary)
                    }
                    if let mx = entry.maxTons {
                        Text(String(format: "max %.1f ton", mx))
                            .font(.caption2).foregroundStyle(entry.limitColor)
                    }
                }
            }

            // Limit barı
            if let fill = entry.limitFill {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(String(format: "Aylık limit doluluk: %%%.0f", fill * 100))
                            .font(.caption2).foregroundStyle(entry.limitColor)
                        Spacer()
                        if fill > 0.9 {
                            Label("Limite yakın", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.bold()).foregroundStyle(.orange)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15)).frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(entry.limitColor.opacity(0.75))
                                .frame(width: geo.size.width * CGFloat(min(fill, 1.0)), height: 5)
                        }
                    }
                    .frame(height: 5)
                }
            }

            // Sensitivity uyarısı — bu hammadde bu formülde kritik mi?
            if let sens = entry.sensitivity, sens != .infinity {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2).foregroundStyle(sens < 200 ? .red : .orange)
                    Text(String(format: "Bu formülde fiyat toleransı: +%.0f ₺/ton", sens))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
