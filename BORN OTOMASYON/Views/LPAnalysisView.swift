import SwiftUI
import SwiftData
import Charts

// MARK: - Ana Menü Girişi: Formül Seçici

struct LPAnalysisMenuView: View {
    @Query private var formulas: [BlendFormula]

    @State private var selected: BlendFormula? = nil

    private var solvedFormulas: [BlendFormula] {
        formulas.filter { $0.lastSolve != nil }.sorted { $0.name < $1.name }
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

// MARK: - Formüle Özgü Analiz (4 Sekme)

struct LPAnalysisView: View {
    let formula: BlendFormula

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Analiz", selection: $selectedTab) {
                Text("📉 İnd. Maliyet").tag(0)
                Text("🔍 Gölge Fiyat").tag(1)
                Text("📊 Hassasiyet").tag(2)
                Text("📋 Karşılaştırma").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            Divider().padding(.top, 8)

            switch selectedTab {
            case 0: ReducedCostTab(formula: formula)
            case 1: ConstraintShadowPriceTab(formula: formula)
            case 2: SensitivityTab(formula: formula)
            default: ComparisonTab(formula: formula)
            }
        }
        .navigationTitle(formula.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sekme 0: Maliyet Sınırı Analizi (Rasyona girmeyen hammaddeler — reduced cost)

private struct ReducedCostTab: View {
    let formula: BlendFormula
    @Query private var library: [FeedIngredient]

    struct ShadowRow: Identifiable {
        let id = UUID()
        let name:         String
        let code:         String
        let currentPrice: Double
        let requiredDrop: Double
        var targetPrice:  Double { max(0, currentPrice - requiredDrop) }
        var urgencyPct:   Double { requiredDrop / max(currentPrice, 1) }
        var urgencyColor: Color {
            if urgencyPct < 0.05  { return .green }
            if urgencyPct < 0.15  { return .orange }
            return .red
        }
    }

    // Chart'ta kullanılan veri segmenti
    private struct ChartSegment: Identifiable {
        let id      = UUID()
        let ingName: String   // kısaltılmış isim
        let segment: String   // "Eşik Fiyat" | "Gereken Düşüş"
        let value:   Double
    }

    private var rows: [ShadowRow] {
        guard let solve = formula.lastSolve else { return [] }
        return solve.reducedCosts
            .compactMap { code, drop -> ShadowRow? in
                guard drop > 0.5 else { return nil }
                let name  = formula.ingredients.first { $0.code == code }?.name
                          ?? library.first { $0.code == code }?.name
                          ?? code
                let price = library.first { $0.code == code }?.priceTL ?? 0
                return ShadowRow(name: name, code: code,
                                 currentPrice: price, requiredDrop: drop)
            }
            .sorted { $0.requiredDrop < $1.requiredDrop }
    }

    // Yalnızca ilk 10 satırı chart'a al (okunabilirlik)
    private var chartData: [ChartSegment] {
        rows.prefix(10).flatMap { row -> [ChartSegment] in
            let short = row.name.count > 15
                ? String(row.name.prefix(14)) + "…"
                : row.name
            return [
                ChartSegment(ingName: short, segment: "Eşik Fiyat",
                             value: max(0, row.targetPrice)),
                ChartSegment(ingName: short, segment: "Gereken Düşüş",
                             value: row.requiredDrop)
            ]
        }
    }

    // Özet metrikleri
    private var closestRow: ShadowRow? { rows.first }
    private var avgDropPct: Double {
        guard !rows.isEmpty else { return 0 }
        return rows.map(\.urgencyPct).reduce(0, +) / Double(rows.count) * 100
    }

    var body: some View {
        List {
            if rows.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Tüm aktif hammaddeler rasyonda kullanılıyor veya sensitivity verisi yok.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                // ── Özet Kart ────────────────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Maliyet Sınırı Analizi")
                                    .font(.headline)
                                Text("Rasyona girmeyen \(rows.count) hammadde için eşik fiyat hesabı")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chart.bar.xaxis.ascending")
                                .font(.title2).foregroundStyle(.blue)
                        }

                        Divider()

                        HStack(spacing: 0) {
                            // En yakın hammadde
                            if let best = closestRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("En Yakın").font(.caption2).foregroundStyle(.secondary)
                                    Text(best.name)
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(best.urgencyColor)
                                            .font(.caption2)
                                        Text(String(format: "−%.0f ₺/ton", best.requiredDrop))
                                            .font(.caption.bold().monospacedDigit())
                                            .foregroundStyle(best.urgencyColor)
                                    }
                                }
                            }
                            Spacer()
                            Divider().frame(height: 36)
                            Spacer()
                            // Ortalama düşüş
                            VStack(alignment: .center, spacing: 2) {
                                Text("Ort. Düşüş").font(.caption2).foregroundStyle(.secondary)
                                Text(String(format: "%%%.1f", avgDropPct))
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(avgDropPct < 5 ? .green : avgDropPct < 15 ? .orange : .red)
                                Text("fiyat düşüşü").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Divider().frame(height: 36)
                            Spacer()
                            // Toplam hammadde sayısı
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Aday").font(.caption2).foregroundStyle(.secondary)
                                Text("\(rows.count)")
                                    .font(.title3.bold())
                                Text("hammadde").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.blue.opacity(0.05))

                // ── Swift Charts: Eşik Fiyat Grafiği ────────────────────────
                Section("Eşik Fiyat Grafiği (İlk \(min(rows.count, 10)) Hammadde)") {
                    Chart(chartData) { seg in
                        BarMark(
                            x: .value("₺/ton", seg.value),
                            y: .value("Hammadde", seg.ingName)
                        )
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

                    // Grafik açıklaması
                    Text("🔵 Eşik Fiyat: Bu fiyata düşerse rasyona girer   🔴 Gereken Düşüş: Toplam = Şu anki fiyat")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.subheadline.bold())
                    Text(row.code).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(row.urgencyColor)
                        Text(String(format: "−%.0f ₺/ton", row.requiredDrop))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(row.urgencyColor)
                    }
                    Text(String(format: "%%%.1f düşüş", row.urgencyPct * 100))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            // Eşik fiyat bilgisi
            if row.currentPrice > 0 {
                HStack {
                    Label(String(format: "Eşik: %.0f ₺/ton", row.targetPrice),
                          systemImage: "target")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(String(format: "Şu an: %.0f ₺/ton", row.currentPrice))
                        .font(.caption).foregroundStyle(.secondary)
                }

                // Görsel bar
                GeometryReader { geo in
                    let safeFrac = CGFloat(row.targetPrice / max(row.currentPrice, 1))
                    ZStack(alignment: .leading) {
                        // Tam bar (şu anki fiyat)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.18))
                            .frame(height: 8)
                        // Güvenli kısım (eşik fiyat)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.55))
                            .frame(width: geo.size.width * safeFrac, height: 8)
                        // Eşik çizgisi
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 2, height: 14)
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

// MARK: - Sekme 1: Gerçek Gölge Fiyat (Besin kısıtlarının dual değişkenleri)

private struct ConstraintShadowPriceTab: View {
    let formula: BlendFormula

    struct ShadowEntry: Identifiable {
        let id = UUID()
        let nutrientKey:  String
        let displayName:  String
        let unit:         String
        let isMinBound:   Bool
        let shadowPrice:  Double
        let currentValue: Double?
        let boundValue:   Double
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

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Hiçbir besin kısıtı bağlayıcı değil veya gölge fiyat verisi yok. Önce çözüm çalıştırın.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kısıt Gölge Fiyatı (Dual Değişken)")
                            .font(.caption.bold())
                        Text("Bağlayıcı besin kısıtları. Sınırı 1 birim gevşetmek formül maliyetini gösterilen miktarda düşürür.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Bağlayıcı Kısıtlar (\(entries.count))") {
                    ForEach(entries) { entry in
                        ConstraintShadowRow(entry: entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ConstraintShadowRow: View {
    let entry: ConstraintShadowPriceTab.ShadowEntry

    private var impactColor: Color {
        if entry.shadowPrice > 200 { return .red }
        if entry.shadowPrice > 50  { return .orange }
        return .yellow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.displayName).font(.subheadline.bold())
                        Text(entry.isMinBound ? "Min" : "Max")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(entry.isMinBound
                                ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                            .foregroundStyle(entry.isMinBound ? .blue : .purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if let cur = entry.currentValue {
                        Text(String(format: "Mevcut: %.3f %@ | Sınır: %.3f %@",
                                    cur, entry.unit, entry.boundValue, entry.unit))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f ₺/ton", entry.shadowPrice))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(impactColor)
                    Text("gölge fiyat")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                let frac = min(entry.shadowPrice / 500.0, 1.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(impactColor.opacity(0.75))
                        .frame(width: geo.size.width * CGFloat(frac), height: 5)
                }
            }
            .frame(height: 5)

            let direction = entry.isMinBound ? "azaltılırsa" : "artırılırsa"
            Text(String(format: "1%@ birim %@ → %.1f ₺/ton tasarruf",
                        entry.unit.isEmpty ? "" : " \(entry.unit)",
                        direction, entry.shadowPrice))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Sekme 2: Hassasiyet (Rasyondaki hammaddelerin fiyat aralığı)

private struct SensitivityTab: View {
    let formula: BlendFormula
    @Query private var library: [FeedIngredient]

    struct SensRow: Identifiable {
        let id = UUID()
        let name:         String
        let code:         String
        let currentPrice: Double
        let mixPct:       Double
        let maxIncrease:  Double
        var isStable: Bool { maxIncrease == .infinity || maxIncrease > currentPrice * 0.5 }
    }

    private var rows: [SensRow] {
        guard let solve = formula.lastSolve else { return [] }
        return solve.costRangeIncreases
            .compactMap { code, maxInc -> SensRow? in
                let name = formula.ingredients.first { $0.code == code }?.name
                         ?? library.first { $0.code == code }?.name
                         ?? code
                let price  = library.first { $0.code == code }?.priceTL ?? 0
                let mixPct = formula.ingredients.first { $0.code == code }?.mixPct ?? 0
                guard mixPct > 0.01 else { return nil }
                return SensRow(name: name, code: code, currentPrice: price,
                               mixPct: mixPct, maxIncrease: maxInc)
            }
            .sorted { $0.maxIncrease < $1.maxIncrease }
    }

    var body: some View {
        List {
            if rows.isEmpty {
                Section {
                    Text("Sensitivity verisi bulunamadı. Önce çözüm çalıştırın.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Rasyondaki hammaddelerin fiyatı ne kadar artarsa rasyondan çıkar? En kırılgan (düşük toleranslı) hammaddeler üstte.")
                        .font(.caption).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section("Fiyat Tolerans Analizi (\(rows.count) hammadde)") {
                    ForEach(rows) { row in
                        SensitivityRow(row: row)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct SensitivityRow: View {
    let row: SensitivityTab.SensRow

    private var statusColor: Color {
        if row.maxIncrease == .infinity { return .green }
        let pct = row.maxIncrease / max(row.currentPrice, 1)
        if pct > 0.2 { return .green }
        if pct > 0.05 { return .orange }
        return .red
    }
    private var statusIcon: String {
        if row.maxIncrease == .infinity { return "checkmark.shield.fill" }
        if statusColor == .green  { return "checkmark.circle.fill" }
        if statusColor == .orange { return "exclamationmark.circle.fill" }
        return "xmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon).foregroundStyle(statusColor).font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.subheadline.bold())
                HStack(spacing: 8) {
                    Text(String(format: "%.1f%%", row.mixPct))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.0f ₺/ton", row.currentPrice))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if row.maxIncrease == .infinity {
                    Text("Her fiyatta kalır")
                        .font(.caption.bold()).foregroundStyle(.green)
                } else {
                    Text(String(format: "+%.0f ₺/ton", row.maxIncrease))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(statusColor)
                    Text(String(format: "→ %.0f ₺'ye kadar", row.currentPrice + row.maxIncrease))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Sekme 3: Karşılaştırma (Neydi / Ne Oldu)

private struct ComparisonTab: View {
    let formula: BlendFormula

    private var changedIngredients: [BFIngredient] {
        formula.ingredients.filter { $0.previousMixPct > 0 || $0.mixPct > 0 }
            .sorted { abs($0.mixPct - $0.previousMixPct) > abs($1.mixPct - $1.previousMixPct) }
    }

    private var changedConstraints: [BFConstraint] {
        formula.constraints.filter { $0.isActive && ($0.currentValue != nil || $0.previousValue != nil) }
    }

    var body: some View {
        List {
            Section("Hammadde Oranları — Önceki vs Şimdiki") {
                ForEach(changedIngredients) { ing in
                    let diff = ing.mixPct - ing.previousMixPct
                    let isNew   = ing.previousMixPct < 0.01 && ing.mixPct > 0.01
                    let isGone  = ing.mixPct < 0.01 && ing.previousMixPct > 0.01
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
                            if isNew {
                                Text("Yeni girdi").font(.caption2).foregroundStyle(.green)
                            } else if isGone {
                                Text("Rasyondan çıktı").font(.caption2).foregroundStyle(.red)
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
                                .foregroundStyle(isGone ? .red : isNew ? .green : abs(diff) < 0.1 ? .primary : diff > 0 ? .green : .red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

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
        let cur = con.currentValue ?? 0
        let prev = con.previousValue
        let inRange = (con.minValue.map { cur >= $0 - 0.001 } ?? true)
                   && (con.maxValue.map { cur <= $0 + 0.001 } ?? true)
        HStack(spacing: 10) {
            Image(systemName: inRange ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(inRange ? .green : .orange)

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
                    .foregroundStyle(inRange ? Color.primary : Color.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
