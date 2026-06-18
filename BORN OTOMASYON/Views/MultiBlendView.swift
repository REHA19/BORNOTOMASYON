import SwiftUI
import SwiftData
import Charts

// MARK: - List screen

struct MultiBlendListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MultiBlendGroup.orderIndex) private var groups: [MultiBlendGroup]

    @State private var showNewAlert    = false
    @State private var newName         = ""
    @State private var renamingGroup:  MultiBlendGroup? = nil
    @State private var renameText      = ""

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "MultiBlend Grubu Yok",
                        systemImage: "rectangle.3.group.fill",
                        description: Text("+ butonu ile yeni grup oluşturun.")
                    )
                } else {
                    List {
                        ForEach(groups) { group in
                            NavigationLink(destination: MultiBlendDetailView(group: group)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "rectangle.3.group.fill")
                                        .foregroundStyle(.indigo)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name).font(.subheadline.bold())
                                        Text("\(group.formulaCodes.count) formül")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            // Sola kaydır → Yeniden Adlandır
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    renameText    = group.name
                                    renamingGroup = group
                                } label: {
                                    Label("Yeniden Adlandır", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            // Sağa kaydır → Sil
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    context.delete(group)
                                    try? context.save()
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { from, to in
                            var reordered = groups
                            reordered.move(fromOffsets: from, toOffset: to)
                            for (i, g) in reordered.enumerated() { g.orderIndex = i }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("MultiBlend")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                var fixed = false
                for g in groups {
                    if g.deduplicateFormulaCodes() { fixed = true }
                }
                if fixed { try? context.save() }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewAlert = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            // Yeni grup
            .alert("Yeni MultiBlend Grubu", isPresented: $showNewAlert) {
                TextField("Grup Adı", text: $newName)
                Button("Oluştur") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let nextIndex = (groups.map(\.orderIndex).max() ?? -1) + 1
                    let g = MultiBlendGroup(name: trimmed, orderIndex: nextIndex)
                    context.insert(g)
                    try? context.save()
                    newName = ""
                }
                Button("İptal", role: .cancel) { newName = "" }
            }
            // Yeniden adlandır
            .alert("Grubu Yeniden Adlandır", isPresented: Binding(
                get: { renamingGroup != nil },
                set: { if !$0 { renamingGroup = nil } }
            )) {
                TextField("Grup Adı", text: $renameText)
                Button("Kaydet") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty, let g = renamingGroup {
                        g.name = trimmed
                        try? context.save()
                    }
                    renamingGroup = nil
                }
                Button("İptal", role: .cancel) { renamingGroup = nil }
            } message: {
                Text(renamingGroup.map { "\u{201C}\($0.name)\u{201D}" } ?? "")
            }
        }
    }
}

// MARK: - Detail screen

struct MultiBlendDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MultiBlendGroup.orderIndex) private var allGroups:   [MultiBlendGroup]
    @Query                                   private var allFormulas:  [BlendFormula]
    @Query                                   private var library:      [FeedIngredient]
    @Query                                   private var costEntries:  [FormulaCostEntry]

    @StateObject private var productionVM = ProductionViewModel()

    let group: MultiBlendGroup

    @State private var isCalculating           = false
    @State private var currentlySolvingName:  String?               = nil
    @State private var solveResults:          [String: SolveResult] = [:]
    @State private var previousCosts:         [String: Double]      = [:]
    @State private var editContext:           FormulaEditContext?   = nil
    @State private var editingIngredient:     FeedIngredient?       = nil
    @State private var showAdder              = false
    @State private var showReport             = false
    @State private var showSend               = false
    @State private var showProductionConfirm  = false
    @State private var formulaSort:           FormulaSort = .tonDesc
    @State private var pickedProductionMonth: Date?                 = nil
    @State private var costHistoryFormula:    BlendFormula?         = nil
    @State private var nutrientCompFormula:   BlendFormula?         = nil
    @State private var priceHistoryIngredient: FeedIngredient?      = nil
    @State private var showGroupLP              = false

    enum FormulaSort: String, CaseIterable {
        case tonDesc  = "Tonaj ↓"
        case tonAsc   = "Tonaj ↑"
        case nameAsc  = "Ad A→Z"
        case nameDesc = "Ad Z→A"
    }
    @State private var solverPulse       = false   // yanıp-sönme animasyonu
    @State private var selectedIngUsage: CombinedIng?         = nil
    @State private var showIngAdder      = false
    @State private var showRenameAlert   = false
    @State private var renameText        = ""
    /// Hesaplama öncesi her hammaddenin aylık ton değeri — delta gösterimi için
    @State private var prevIngTons:      [String: Double]      = [:]
    /// combinedIngredients cache — her render'da yeniden hesaplanmaz
    @State private var cachedCombinedIngs: [CombinedIng]      = []

    struct SolveResult {
        let ok:      Bool
        let cost:    Double   // ₺/ton after solve
        let message: String
    }

    struct FormulaEditContext: Identifiable {
        let id            = UUID()
        let formula:      BlendFormula
        let previousCostTL: Double   // ₺/ton before last solve (0 = no history)
        let productionTons: Double
    }

    // Formulas in this group — user-defined order, then sorted by formulaSort
    private var groupFormulas: [BlendFormula] {
        let base = group.formulaCodes.compactMap { code in
            allFormulas.first { $0.code == code }
        }
        let tons = group.productionTons
        switch formulaSort {
        case .tonDesc:  return base.sorted { (tons[$0.code] ?? 0) > (tons[$1.code] ?? 0) }
        case .tonAsc:   return base.sorted { (tons[$0.code] ?? 0) < (tons[$1.code] ?? 0) }
        case .nameAsc:  return base.sorted { $0.name < $1.name }
        case .nameDesc: return base.sorted { $0.name > $1.name }
        }
    }

    // ── combinedIngredients — sadece gerektiğinde hesaplanır, cachedCombinedIngs'e yazılır ──

    /// Her render'da çalışmaz — sadece explicit trigger'larda çağrılır.
    /// O(1) dictionary lookup ile lineer IngredientMatcher.find() yerine geçer.
    private func refreshCombinedIngs() {
        let formulas = groupFormulas
        // Sadece formüllerde kullanılan + stokYok kodlarını yükle — tüm kütüphane yerine
        let neededCodes: Set<String> = Set(
            formulas.flatMap { $0.ingredients.map { $0.code } } + group.stokYokCodes
        )
        let fullLibByCode: [String: FeedIngredient] = Dictionary(
            library.filter { neededCodes.contains($0.code) }.map { ($0.code, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var seen     = Set<String>()
        var result   = [CombinedIng]()
        var countMap = [String: Int]()
        for formula in formulas {
            var seenInFormula = Set<String>()
            for ing in formula.ingredients where !seenInFormula.contains(ing.code) {
                seenInFormula.insert(ing.code)
                countMap[ing.code, default: 0] += 1
            }
        }
        for formula in formulas {
            for ing in formula.ingredients {
                guard !seen.contains(ing.code) else { continue }
                seen.insert(ing.code)
                let lib = fullLibByCode[ing.code]
                result.append(CombinedIng(code: ing.code, name: ing.name,
                                          formulaCount: countMap[ing.code] ?? 1, libEntry: lib))
            }
        }
        // STOK YOK olarak işaretlenmiş ancak formülden çıkmış hammaddeleri de göster
        for code in group.stokYokCodes where !seen.contains(code) {
            if let lib = fullLibByCode[code] {
                seen.insert(code)
                result.append(CombinedIng(code: code, name: lib.name,
                                          formulaCount: 0, libEntry: lib))
            }
        }
        // monthlyTons — tek nested loop, dict lookup
        let tons = group.productionTons
        let ingsByFormula: [[String: Double]] = formulas.map { f in
            Dictionary(f.ingredients.map { ($0.code, $0.mixPct) }, uniquingKeysWith: { first, _ in first })
        }
        let formTons = formulas.map { tons[$0.code] ?? 0.0 }
        for i in result.indices {
            var usage = 0.0
            for fi in ingsByFormula.indices {
                usage += (ingsByFormula[fi][result[i].code] ?? 0) / 100.0 * formTons[fi]
            }
            result[i].monthlyTons = usage
        }
        let usageCache = Dictionary(result.map { ($0.code, $0.monthlyTons) }, uniquingKeysWith: { first, _ in first })
        cachedCombinedIngs = result.sorted {
            let av0 = $0.libEntry?.isAvailable ?? true
            let av1 = $1.libEntry?.isAvailable ?? true
            if av0 != av1 { return av0 }
            let u0 = usageCache[$0.code] ?? 0; let u1 = usageCache[$1.code] ?? 0
            if abs(u0 - u1) > 0.0001 { return u0 > u1 }
            return $0.name < $1.name
        }
    }

    // Monthly usage (tons) for a given ingredient across all group formulas
    private func monthlyUsage(ingCode: String) -> Double {
        let tons = group.productionTons
        return groupFormulas.reduce(0.0) { sum, formula in
            let pct   = formula.ingredients.first { $0.code == ingCode }?.mixPct ?? 0
            let fTons = tons[formula.code] ?? 0
            return sum + (pct / 100.0 * fTons)
        }
    }

    // Total production tons across all formulas in this group
    private var totalProductionTons: Double {
        groupFormulas.compactMap { group.productionTons[$0.code] }.reduce(0, +)
    }

    // Toplam üretim maliyeti (son çözüm ya da lastSolve)
    private var currentTotalTL: Double {
        groupFormulas.reduce(0.0) { sum, f in
            let cost = solveResults[f.code]?.cost ?? f.currentCostTL
            let tons = group.productionTons[f.code] ?? 0
            return sum + cost * tons
        }
    }

    // Çözüm öncesi toplam maliyet (previousCosts doluysa)
    private var previousTotalTL: Double? {
        guard !previousCosts.isEmpty else { return nil }
        let total = groupFormulas.reduce(0.0) { sum, f in
            let prev = previousCosts[f.code] ?? 0
            let tons = group.productionTons[f.code] ?? 0
            return sum + prev * tons
        }
        return total > 0 ? total : nil
    }

    // Previous calendar month (start of month)
    private var previousMonth: Date {
        let cal   = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: -1, to: start) ?? start
    }

    // Son 24 ay listesi (en yeni → en eski)
    private var availableProductionMonths: [Date] {
        let cal     = Calendar.current
        let current = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        var months: [Date] = []
        var cursor  = current
        for _ in 0..<24 {
            months.append(cursor)
            guard let prev = cal.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return months
    }

    private func monthLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date).capitalized
    }

    // MARK: - Body

    var body: some View {
        List {
            costSummarySection
            formulasSection
            ingredientsSection
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                // ── Hesapla ──────────────────────────────────────────────────
                Button { Task { await calculateAll() } } label: {
                    HStack(spacing: 6) {
                        if isCalculating {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.8).tint(.white)
                        } else {
                            Image(systemName: "cpu").font(.subheadline.bold())
                        }
                        Text(isCalculating ? "Hesaplanıyor…" : "Hesapla").font(.subheadline.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background((isCalculating || groupFormulas.isEmpty) ? Color.gray.opacity(0.6) : Color.green, in: Capsule())
                    .shadow(color: .green.opacity(isCalculating ? 0 : 0.5), radius: 8)
                }
                .disabled(isCalculating || groupFormulas.isEmpty)
                .animation(.easeInOut(duration: 0.2), value: isCalculating)
                // ── Üretime Kaydet ───────────────────────────────────────────
                Button { showProductionConfirm = true } label: {
                    Text("Üretime\nKaydet")
                        .font(.caption.bold()).multilineTextAlignment(.center).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background((groupFormulas.isEmpty || isCalculating) ? Color.gray.opacity(0.5) : Color.indigo, in: Capsule())
                        .shadow(color: .indigo.opacity(groupFormulas.isEmpty || isCalculating ? 0 : 0.4), radius: 8)
                }
                .disabled(groupFormulas.isEmpty || isCalculating)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Navigasyon animasyonu bittikten SONRA çalıştır — ekranın donmaması için
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                refreshCombinedIngs()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Grup adını değiştir
                    Button {
                        renameText      = group.name
                        showRenameAlert = true
                    } label: {
                        Image(systemName: "pencil").foregroundStyle(.blue)
                    }
                    Button { showSend = true } label: {
                        Image(systemName: "paperplane.fill").foregroundStyle(.orange)
                    }
                    .disabled(groupFormulas.isEmpty || isCalculating)
                    Button { showReport = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(groupFormulas.isEmpty)
                }
            }
        }
        .alert("Grubu Yeniden Adlandır", isPresented: $showRenameAlert) {
            TextField("Grup Adı", text: $renameText)
            Button("Kaydet") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    group.name = trimmed
                    try? context.save()
                }
            }
            Button("İptal", role: .cancel) { }
        } message: {
            Text("\u{201C}\(group.name)\u{201D} için yeni bir isim girin.")
        }
        .sheet(item: $editContext) { ctx in
            FormulaEditorView(
                formula:        ctx.formula,
                showCloseButton: true,
                previousCostTL: ctx.previousCostTL,
                productionTons: ctx.productionTons
            )
        }
        .sheet(isPresented: $showReport) {
            MultiBlendReportSheet(group: group, allFormulas: allFormulas, library: library)
        }
        .sheet(isPresented: $showSend) {
            MultiBlendSendSheet(group: group, allFormulas: allFormulas)
        }
        .sheet(isPresented: $showAdder) {
            MultiBlendFormulaPickerSheet(
                group:     group,
                available: allFormulas.filter { !group.formulaCodes.contains($0.code) }
            )
        }
        .sheet(item: $selectedIngUsage) { ing in
            IngredientUsageDetailSheet(
                ingredient:     ing,
                groupFormulas:  groupFormulas,
                productionTons: group.productionTons
            )
        }
        .sheet(isPresented: $showIngAdder, onDismiss: refreshCombinedIngs) {
            MultiBlendIngAddSheet(groupFormulas: groupFormulas, library: library)
        }
        .sheet(isPresented: $showGroupLP) {
            MultiBlendGroupLPSheet(group: group, groupFormulas: groupFormulas, library: library)
        }
        .sheet(item: $editingIngredient) { ing in
            EditIngredientView(ingredient: ing)
        }
        .sheet(item: $costHistoryFormula) { formula in
            CostHistorySheet(
                formula:  formula,
                entries:  costEntries.filter { $0.formulaCode == formula.code }
                                     .sorted { $0.recordedAt < $1.recordedAt }
            )
        }
        .sheet(item: $nutrientCompFormula) { formula in
            NutrientComparisonSheet(formula: formula)
        }
        .sheet(item: $priceHistoryIngredient) { ing in
            PriceHistoryColoredSheet(ingredient: ing)
        }
        .onChange(of: productionVM.isLoading) { _, isLoading in
            if !isLoading {
                autoMatchProduction(from: productionVM.summary?.entries ?? [])
            }
        }
        .task {
            // Navigasyon animasyonu bittikten SONRA ağ çağrısını başlat
            try? await Task.sleep(for: .milliseconds(650))
            productionVM.selectedMonth = previousMonth
            await productionVM.load()
        }
        .onDisappear {
            try? context.save()
        }
        .confirmationDialog(
            "Üretime Kaydet",
            isPresented: $showProductionConfirm,
            titleVisibility: .visible
        ) {
            Button("Evet, Üretime Kaydet") { saveToProduction() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Mevcut çözüm maliyetleri üretim kaydı olarak kilitlenecek. Bir sonraki 'Üretime Kaydet'e kadar bu maliyetler üretim bölümünde görünür.")
        }
    }

    // MARK: - Formüller section

    private var formulasSection: some View {
        Section {
            if groupFormulas.isEmpty {
                Text("Henüz formül eklenmedi.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(groupFormulas) { formula in
                    Button {
                        editContext = FormulaEditContext(
                            formula:        formula,
                            previousCostTL: previousCosts[formula.code] ?? 0,
                            productionTons: group.productionTons[formula.code] ?? 0
                        )
                    } label: {
                        formulaRow(formula)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            group.removeFormula(code: formula.code)
                            try? context.save()
                        } label: {
                            Label("Gruptan Çıkar", systemImage: "minus.circle")
                        }
                    }
                }
                .onMove { from, to in
                    var codes = group.formulaCodes
                    codes.move(fromOffsets: from, toOffset: to)
                    group.formulaCodes = codes
                    try? context.save()
                }
            }
        } header: {
            HStack(spacing: 10) {
                Text("Formüller (\(groupFormulas.count))")
                Spacer()
                // Sıralama menüsü
                Menu {
                    ForEach(FormulaSort.allCases, id: \.self) { opt in
                        Button {
                            formulaSort = opt
                        } label: {
                            HStack {
                                Text(opt.rawValue)
                                if formulaSort == opt {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(formulaSort.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }
                if productionVM.isLoading {
                    ProgressView().scaleEffect(0.75)
                } else {
                    HStack(spacing: 8) {
                        // Üretim cetveli ikonu — yazısız, sadece sembol
                        Button {
                            let month = pickedProductionMonth ?? previousMonth
                            productionVM.selectedMonth = month
                            Task { await productionVM.load() }
                        } label: {
                            Image(systemName: "tablecells.fill")
                                .font(.callout)
                                .foregroundStyle(.blue)
                        }
                        // Ay seçici takvim
                        Menu {
                            ForEach(availableProductionMonths, id: \.self) { month in
                                Button {
                                    pickedProductionMonth = month
                                    productionVM.selectedMonth = month
                                    Task { await productionVM.load() }
                                } label: {
                                    HStack {
                                        Text(monthLabel(month))
                                        if let picked = pickedProductionMonth,
                                           Calendar.current.isDate(picked, equalTo: month, toGranularity: .month) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "calendar")
                                .font(.callout)
                                .foregroundStyle(pickedProductionMonth != nil ? .blue : .secondary)
                        }
                    }
                }
                Button { showAdder = true } label: {
                    Image(systemName: "plus.circle").font(.callout)
                }
            }
        } footer: {
            formulasTotalFooter
        }
    }

    private var formulasTotalFooter: some View {
        let tons       = group.productionTons
        let matched    = groupFormulas.filter { (tons[$0.code] ?? 0) > 0 }
        let total      = matched.reduce(0.0) { $0 + (tons[$1.code] ?? 0) }
        let totalCost  = matched.reduce(0.0) { sum, f in
            let cost = solveResults[f.code]?.cost ?? f.currentCostTL
            let t    = tons[f.code] ?? 0
            return sum + cost * t
        }

        return Group {
            if total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack(spacing: 0) {
                        Label("Toplam Üretim", systemImage: "sum")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(String(format: "%.2f ton", total))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 0) {
                        Text("\(matched.count)/\(groupFormulas.count) formülde tonaj girildi")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if totalCost > 0 {
                            Text(formatTL(totalCost) + " toplam")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func formulaRow(_ formula: BlendFormula) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(formula.name).font(.subheadline.bold())
                    Text(formula.code).font(.caption).foregroundStyle(.secondary)
                    Text("\(formula.ingredients.count) hammadde · \(formula.constraints.count) kısıt")
                        .font(.caption2).foregroundStyle(.tertiary)
                    // Aksiyon butonları — maliyet geçmişi + besin karşılaştırma
                    HStack(spacing: 10) {
                        Button {
                            costHistoryFormula = formula
                        } label: {
                            Label("Geçmiş", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        if let res = solveResults[formula.code], res.ok {
                            Button {
                                nutrientCompFormula = formula
                            } label: {
                                Label("Besinler", systemImage: "chart.bar.doc.horizontal")
                                    .font(.caption2).foregroundStyle(.indigo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    ProductionTonsField(
                        formulaCode: formula.code,
                        productionTons: Binding(
                            get: { group.productionTons },
                            set: { group.productionTons = $0 }
                        )
                    )
                    if let res = solveResults[formula.code] {
                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: res.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(res.ok ? .green : .red)
                                .font(.title3)
                            if res.ok, let prev = previousCosts[formula.code], prev > 0, res.cost > 0 {
                                let diff = res.cost - prev
                                if abs(diff) > 1 {
                                    HStack(spacing: 2) {
                                        Image(systemName: diff < 0 ? "arrow.down.fill" : "arrow.up.fill")
                                            .font(.system(size: 8, weight: .bold))
                                        Text(String(format: "%+.0f ₺/t", diff))
                                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    }
                                    .foregroundStyle(diff < 0 ? .green : .red)
                                }
                            }
                        }
                    } else if formula.lastSolve != nil {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            // Hammadde değişimi — giren/çıkan/değişen TÜM hammaddeler (previousMixPct > 0 koşulu kaldırıldı)
            if solveResults[formula.code] != nil {
                let changes = formula.ingredients
                    .filter { abs($0.mixPct - $0.previousMixPct) >= 0.5 }
                    .sorted { lhs, rhs in
                        let ld = lhs.mixPct - lhs.previousMixPct
                        let rd = rhs.mixPct - rhs.previousMixPct
                        if (ld > 0) != (rd > 0) { return ld > 0 }  // artanlar önce
                        return abs(ld) > abs(rd)
                    }
                if !changes.isEmpty {
                    // Denge: artan kg toplamı = azalan kg toplamı (LP garantisi)
                    let inKg  = changes.filter { $0.mixPct > $0.previousMixPct }
                                       .reduce(0.0) { $0 + ($1.mixPct - $1.previousMixPct) / 100.0 * formula.totalKg }
                    let outKg = changes.filter { $0.mixPct < $0.previousMixPct }
                                       .reduce(0.0) { $0 + ($1.previousMixPct - $1.mixPct) / 100.0 * formula.totalKg }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(changes), id: \.id) { ing in
                            let diffPct = ing.mixPct - ing.previousMixPct
                            let diffKg  = diffPct / 100.0 * formula.totalKg
                            HStack(spacing: 3) {
                                Image(systemName: diffPct > 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 8, weight: .bold))
                                Text("\(String(ing.name.prefix(12))): \(String(format: "%+.0f kg", diffKg)) (\(String(format: "%+.1f%%", diffPct)))")
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(diffPct > 0 ? .green : .red)
                        }
                        // Denge özeti — giren ve çıkan kg'lar eşit olmalı
                        if inKg > 0.5 || outKg > 0.5 {
                            HStack(spacing: 4) {
                                Image(systemName: abs(inKg - outKg) < 1.0
                                      ? "checkmark.circle" : "exclamationmark.circle")
                                    .font(.system(size: 8))
                                Text(String(format: "↑%.0f kg  ↓%.0f kg", inKg, outKg))
                                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                            }
                            .foregroundStyle(abs(inKg - outKg) < 1.0 ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
            // Hata mesajı (çözüm başarısız) veya uyarı mesajı (limit önerisi)
            if let res = solveResults[formula.code], !res.message.isEmpty {
                Text(res.message)
                    .font(.caption2)
                    .foregroundStyle(res.ok ? .orange : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Ortak Hammaddeler section

    private var ingredientsSection: some View {
        let items = cachedCombinedIngs   // cache'ten oku — her render'da hesaplanmaz
        return Section {
            if items.isEmpty {
                Text("Formül eklendikçe hammaddeler burada listelenir.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        selectedIngUsage = item
                    } label: {
                        ingredientRow(item)
                    }
                    .buttonStyle(.plain)
                    // Sağa kaydır → Stokta Yok (sadece stokta olan hammadde için)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if item.libEntry?.isAvailable ?? true {
                            Button {
                                toggleIngredientAvailability(item)
                            } label: {
                                Label("Stokta Yok", systemImage: "xmark.circle.fill")
                            }
                            .tint(.red)
                        }
                    }
                    // Sola kaydır → Fiyat Geçmişi + Besin Değerleri + Stokta Var
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let lib = item.libEntry {
                            Button {
                                priceHistoryIngredient = lib
                            } label: {
                                Label("Fiyat Geçmişi", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            .tint(.orange)
                        }
                        if let lib = item.libEntry {
                            Button {
                                editingIngredient = lib
                            } label: {
                                Label("Besin Değerleri", systemImage: "slider.horizontal.3")
                            }
                            .tint(.indigo)
                        }
                        if !(item.libEntry?.isAvailable ?? true) {
                            Button {
                                toggleIngredientAvailability(item)
                            } label: {
                                Label("Stokta Var", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        } header: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ortak Hammadde Listesi (\(items.count))")
                    if totalProductionTons > 0 {
                        Text(String(format: "Toplam üretim: %.1f ton/ay", totalProductionTons))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    showGroupLP = true
                } label: {
                    Image(systemName: "function").font(.callout)
                }
                .buttonStyle(.borderless)
                Button { showIngAdder = true } label: {
                    Image(systemName: "plus.circle").font(.callout)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func ingredientRow(_ item: CombinedIng) -> some View {
        let usage        = item.monthlyTons
        let limit        = group.monthlyIngLimits[item.code]
        let hasViolation = (limit?.maxTons).map { usage > 0 && usage > $0 } ?? false
        let isAvailable  = item.libEntry?.isAvailable ?? true

        VStack(alignment: .leading, spacing: 6) {
            // Top row: name + monthly usage / stok durumu
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline)
                            .strikethrough(!isAvailable, pattern: .solid, color: .red)
                            .foregroundStyle(isAvailable ? .primary : .secondary)
                        if !isAvailable {
                            Text("STOK YOK")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.red, in: Capsule())
                        }
                    }
                    Text(item.code).font(.caption).foregroundStyle(.secondary)
                    Text("\(item.formulaCount) formülde kullanılıyor")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if isAvailable && totalProductionTons > 0 && usage > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: hasViolation ? "exclamationmark.triangle.fill" : "scalemass")
                                .font(.caption2)
                                .foregroundStyle(hasViolation ? .red : .secondary)
                            Text(String(format: "%.2f ton/ay", usage))
                                .font(.caption.bold())
                                .foregroundStyle(hasViolation ? .red : .primary)
                        }
                        // Delta: hesaplama sonrası değişim (yeşil artış / kırmızı azalış)
                        if let prev = prevIngTons[item.code], abs(usage - prev) > 0.001 {
                            let delta = usage - prev
                            HStack(spacing: 2) {
                                Image(systemName: delta > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(String(format: "%+.2f ton", delta))
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                            }
                            .foregroundStyle(delta > 0 ? .green : .red)
                        }
                        if let mx = limit?.maxTons {
                            Text(String(format: "max %.1f ton", mx))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Bottom row: MIN ton | MAX ton | ₺/ton
            HStack(spacing: 10) {
                IngredientLimitFields(
                    ingCode:  item.code,
                    limits:   Binding(
                        get: { group.monthlyIngLimits },
                        set: { group.monthlyIngLimits = $0 }
                    )
                )
                Spacer()
                priceField(for: item)
            }
        }
        .padding(.vertical, 2)
        .opacity(isAvailable ? 1.0 : 0.5)
    }

    // MARK: - Maliyet Özeti Section

    private func formatTL(_ value: Double, sign: Bool = false) -> String {
        let n = NSNumber(value: abs(value))
        let fmt = NumberFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        let str = fmt.string(from: n) ?? String(format: "%.0f", abs(value))
        let prefix = sign ? (value < -0.5 ? "-" : value > 0.5 ? "+" : "") : ""
        return "\(prefix)\(str) ₺"
    }

    private var costSummarySection: some View {
        Section {
            VStack(spacing: 8) {
                // ── Son Çözüm Maliyeti ────────────────────────────────────────
                HStack {
                    Label("Son Çözüm Maliyeti", systemImage: "cpu")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    let curr = currentTotalTL
                    Text(curr > 0 ? formatTL(curr) : "—")
                        .font(.title3.bold())
                        .foregroundStyle(curr > 0 ? .orange : .secondary)
                }

                if let prev = previousTotalTL, prev > 0 {
                    let curr = currentTotalTL
                    let diff = curr - prev
                    Divider()
                    HStack {
                        Text("Önceki çözüm")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTL(prev))
                            .font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: diff < -0.5 ? "arrow.down.circle.fill"
                                           : diff > 0.5  ? "arrow.up.circle.fill"
                                                         : "minus.circle")
                                .foregroundStyle(diff < -0.5 ? .green : diff > 0.5 ? .red : .secondary)
                                .font(.caption)
                            Text("Fark")
                                .font(.caption.bold())
                                .foregroundStyle(diff < -0.5 ? .green : diff > 0.5 ? .red : .secondary)
                        }
                        Spacer()
                        let pct = prev > 0 ? diff / prev * 100 : 0
                        Text("\(formatTL(diff, sign: true))  (%\(String(format: "%+.1f", pct)))")
                            .font(.caption.bold())
                            .foregroundStyle(diff < -0.5 ? .green : diff > 0.5 ? .red : .secondary)
                    }
                }

                // ── Üretim Kayıt Maliyeti ─────────────────────────────────────
                if group.hasProductionSnapshot {
                    let snap     = group.productionSnapshot
                    let lockedTons = group.productionSnapshotTons
                    let prodTL   = groupFormulas.reduce(0.0) { sum, f in
                        let cost = snap[f.code] ?? 0
                        let tons = lockedTons[f.code] ?? 0
                        return sum + cost * tons
                    }
                    Divider()
                    HStack {
                        Label("Üretim Kaydı", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.indigo)
                        Spacer()
                        Text(prodTL > 0 ? formatTL(prodTL) : "—")
                            .font(.title3.bold())
                            .foregroundStyle(.indigo)
                    }
                    let snapDateStr: String = {
                        let fmt = DateFormatter()
                        fmt.locale = Locale(identifier: "tr_TR")
                        fmt.dateFormat = "d MMM yyyy HH:mm"
                        return fmt.string(from: group.productionSnapshotAt)
                    }()
                    HStack {
                        Text("Kilitlenme: \(snapDateStr)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        let diff2 = currentTotalTL - prodTL
                        if abs(diff2) > 0.5 {
                            Text(formatTL(diff2, sign: true))
                                .font(.caption2.bold())
                                .foregroundStyle(diff2 < 0 ? .green : .red)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Üretim Kaydı

    private func saveToProduction() {
        var snap:     [String: Double] = [:]
        var snapTons: [String: Double] = [:]
        for formula in groupFormulas {
            let cost = solveResults[formula.code]?.cost ?? formula.currentCostTL
            let tons = group.productionTons[formula.code] ?? 0
            snap[formula.code]     = cost
            snapTons[formula.code] = tons
            // Maliyet geçmişine kaydet (sadece gerçek maliyet varsa)
            if cost > 0 {
                let entry = FormulaCostEntry(
                    formulaCode: formula.code,
                    formulaName: formula.name,
                    groupName:   group.name,
                    costPerTon:  cost,
                    tons:        tons
                )
                context.insert(entry)
            }
        }
        group.productionSnapshot     = snap
        group.productionSnapshotTons = snapTons
        group.productionSnapshotAt   = Date()
        // Sonraki hesaplamalar bu anı baseline olarak kullanır
        for formula in groupFormulas {
            var ings = formula.ingredients
            for i in ings.indices { ings[i].productionMixPct = ings[i].mixPct }
            formula.ingredients = ings
        }
        try? context.save()
    }

    // MARK: - Stok Yönetimi

    private var hasUnavailableIngredients: Bool {
        cachedCombinedIngs.contains { !($0.libEntry?.isAvailable ?? true) }
    }

    private func toggleIngredientAvailability(_ item: CombinedIng) {
        guard let lib = item.libEntry else { return }
        let newValue = !lib.isAvailable
        lib.isAvailable = newValue
        // Grup'un stokYokCodes listesini güncelle (restart sonrası da görünür kalsın)
        if newValue {
            group.clearStokYok(item.code)
        } else {
            group.markStokYok(item.code)
        }
        // Tüm BlendFormula'larda hasStock güncelle (sadece grup formülleri değil, tümü)
        for formula in allFormulas {
            var ings    = formula.ingredients
            var changed = false
            for i in ings.indices where ings[i].code == item.code {
                ings[i].hasStock = newValue
                changed = true
            }
            if changed { formula.ingredients = ings }
        }
        try? context.save()
        refreshCombinedIngs()
    }

    private func activateAllIngredients() {
        for item in cachedCombinedIngs {
            guard let lib = item.libEntry, !lib.isAvailable else { continue }
            lib.isAvailable = true
            group.clearStokYok(item.code)
            for formula in allFormulas {
                var ings    = formula.ingredients
                var changed = false
                for i in ings.indices where ings[i].code == item.code {
                    ings[i].hasStock = true
                    changed = true
                }
                if changed { formula.ingredients = ings }
            }
        }
        try? context.save()
        refreshCombinedIngs()
    }

    private func priceField(for item: CombinedIng) -> some View {
        IngredientPriceField(item: item, groupFormulas: groupFormulas)
    }

    // MARK: - Auto-match from production schedule

    private func autoMatchProduction(from entries: [ProductionEntry]) {
        guard !entries.isEmpty else { return }
        var tons = group.productionTons
        for formula in groupFormulas {
            // 1. Ürün kodu ile tam eşleşme — en güvenilir yöntem
            var match = entries.first { $0.productCode == formula.code }

            // 2. Kod eşleşmezse isme göre dene (büyük/küçük harf duyarsız, birebir eşleşme)
            if match == nil {
                let fName = formula.name.trimmingCharacters(in: .whitespaces).lowercased()
                match = entries.first {
                    $0.productName.trimmingCharacters(in: .whitespaces).lowercased() == fName
                }
            }

            if let match {
                let matched = match.totalKg / 1000.0
                tons[formula.code] = matched > 0 ? matched : 1.0
            } else if (tons[formula.code] ?? 0) == 0 {
                // Eşleşme yok ve mevcut tonaj 0/boş → 1 ton varsayılan
                tons[formula.code] = 1.0
            }
            // Eşleşme yok ama tonaj zaten girilmişse koru
        }
        group.productionTons = tons
        try? context.save()
        refreshCombinedIngs()
    }

    // MARK: - Batch calculate — tüm formüller paralel arka planda çözülür

    @MainActor
    private func calculateAll() async {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        await Task.yield()

        isCalculating        = true
        currentlySolvingName = nil
        try? await Task.sleep(for: .milliseconds(60))

        // Hesaplama öncesi ortak hammadde tonlarını kaydet (delta gösterimi için)
        // cachedCombinedIngs kullanılır — combinedIngredients pahalı re-compute tetiklenmez
        prevIngTons = Dictionary(
            cachedCombinedIngs.map { ($0.code, $0.monthlyTons) }, uniquingKeysWith: { first, _ in first }
        )

        for formula in groupFormulas { previousCosts[formula.code] = formula.currentCostTL }
        solveResults = [:]

        // Kütüphanede isAvailable=false olan hammaddeleri formüllerde hasStock=false yap
        let unavailCodes = Set(library.filter { !$0.isAvailable }.map { $0.code })
        if !unavailCodes.isEmpty {
            for formula in groupFormulas {
                var ings = formula.ingredients
                var didChange = false
                for i in ings.indices where unavailCodes.contains(ings[i].code) && ings[i].hasStock {
                    ings[i].hasStock = false
                    didChange = true
                }
                if didChange { formula.ingredients = ings }
            }
        }

        let limitsMap     = group.monthlyIngLimits
        let productionMap = group.productionTons
        let totalTons     = groupFormulas.compactMap { productionMap[$0.code] }.reduce(0, +)
        let libSnap       = library.map { IngSnap.from($0) }

        // ── Per-formül MAX/MIN tavanları hesapla (limit varsa) ────────────────
        var perFormulaMaxPct: [String: [String: Double]] = [:]
        var proRataMinPct:    [String: Double]           = [:]

        if !limitsMap.isEmpty, totalTons > 0 {
            for (ingCode, limit) in limitsMap {
                if let maxT = limit.maxTons {
                    var usageMap:   [String: Double] = [:]
                    let totalUsage  = monthlyUsage(ingCode: ingCode)
                    for formula in groupFormulas {
                        let fTons = productionMap[formula.code] ?? 0
                        guard fTons > 0 else { continue }
                        let pct = formula.ingredients.first { $0.code == ingCode }?.mixPct ?? 0
                        usageMap[formula.code] = pct / 100.0 * fTons
                    }
                    for formula in groupFormulas {
                        let fTons   = productionMap[formula.code] ?? 0
                        guard fTons > 0 else { continue }
                        let fMinPct = formula.ingredients.first { $0.code == ingCode }?.minPct ?? 0
                        let fMaxPct = formula.ingredients.first { $0.code == ingCode }?.maxPct ?? 0
                        // totalUsage = 0 → ilk hesaplamada eşit pay yerine üretim tonajına orantılı pay
                        let fTonsForShare = productionMap[formula.code] ?? 0
                        let share   = totalUsage > 0.001
                            ? (usageMap[formula.code] ?? 0) / totalUsage
                            : (totalTons > 0 ? fTonsForShare / totalTons
                                             : 1.0 / Double(max(groupFormulas.count, 1)))
                        var allocTons = max(maxT * share, fMinPct / 100.0 * fTons)
                        var cappedPct = allocTons / fTons * 100.0
                        if fMaxPct > 0 { cappedPct = min(cappedPct, fMaxPct) }
                        if perFormulaMaxPct[formula.code] == nil { perFormulaMaxPct[formula.code] = [:] }
                        perFormulaMaxPct[formula.code]![ingCode] = cappedPct
                    }
                }
                if let minT = limit.minTons, minT > 0 {
                    proRataMinPct[ingCode] = minT / totalTons * 100.0
                }
            }
        }

        // ── Her formül için çalışma paketi hazırla (main thread) ─────────────
        struct SolveWork: @unchecked Sendable {
            let code:         String
            let origIngs:     [BFIngredient]
            let workIngs:     [BFIngredient]
            let workCons:     [BFConstraint]
            let combos:       [BFCombination]
            let totalKg:      Double
            let conflicts:    [String]
            let snap:         [IngSnap]   // kütüphane snapshot — Task.detached'a güvenle geçer
            let hardMaxByCode: [String: Double]  // aylık limit kapları — autoRelaxed bunları aşamaz
        }
        struct SolveOut: @unchecked Sendable {
            let code:       String
            let origIngs:   [BFIngredient]
            let resultIngs: [BFIngredient]
            let resultCons: [BFConstraint]
            let lastSolve:  BFSolveResult?
            let message:    String?
            let conflicts:  [String]
        }

        var workItems: [SolveWork] = []
        for formula in groupFormulas {
            let hardMax  = perFormulaMaxPct[formula.code] ?? [:]
            let hardMin  = proRataMinPct
            var wIngs    = formula.ingredients
            var conflicts: [String] = []
            var hardMaxByCode: [String: Double] = [:]   // aylık limit kapları

            for i in wIngs.indices {
                let code    = wIngs[i].code
                let ingName = wIngs[i].name
                let fMin    = wIngs[i].minPct
                let fMax    = wIngs[i].maxPct
                let eMax    = fMax > 0 ? fMax : 100.0
                if let cap = hardMax[code] {
                    let eCap = min(cap, eMax)
                    if eCap < fMin - 0.001 {
                        conflicts.append("⚠️ \(ingName): formül min %\(String(format:"%.2f",fMin)) > aylık MAX tavan %\(String(format:"%.2f",eCap)) — aylık limiti artırın")
                    } else {
                        wIngs[i].maxPct  = eCap
                        hardMaxByCode[code] = eCap   // autoRelaxed bu limiti aşamaz
                    }
                }
                if let floor = hardMin[code], floor > 0 {
                    let eMax2 = wIngs[i].maxPct > 0 ? wIngs[i].maxPct : 100.0
                    if floor > eMax2 + 0.001 {
                        conflicts.append("⚠️ \(ingName): aylık MIN taban %\(String(format:"%.2f",floor)) > formül max %\(String(format:"%.2f",eMax2)) — aylık limiti düşürün veya formülün max'ını artırın")
                    } else { wIngs[i].minPct = max(fMin, floor) }
                }
            }

            // Bug 3 — aylık min floor'lar sum(minPct) > 100 yapıyorsa önceden haber ver
            let activeMins = wIngs.filter { $0.isActive && $0.hasStock }.reduce(0.0) { $0 + $1.minPct }
            if activeMins > 100 + 1e-4 {
                conflicts.append("❌ Aylık minimum limitler bu formülde toplam min %\(String(format:"%.1f", activeMins)) > %100 — aylık min tonajlarını azaltın")
            }

            workItems.append(SolveWork(
                code:         formula.code,
                origIngs:     formula.ingredients,
                workIngs:     wIngs,
                workCons:     formula.constraints,
                combos:       formula.combinations,
                totalKg:      formula.totalKg,
                conflicts:    conflicts,
                snap:         libSnap,
                hardMaxByCode: hardMaxByCode
            ))
        }

        currentlySolvingName = "\(workItems.count) formül"

        // ── Tüm formülleri paralel olarak arka planda çöz ────────────────────
        var outputs: [SolveOut] = []
        outputs.reserveCapacity(workItems.count)

        await withTaskGroup(of: SolveOut.self) { grp in
            for item in workItems {
                // Task.detached — @MainActor bağımsız, tüm formüller PARALEL çalışır
                grp.addTask {
                    await Task.detached(priority: .userInitiated) {
                        let vm         = FormulaEditorVM()
                        vm.ingredients = item.workIngs
                        vm.constraints = item.workCons
                        vm.combinations = item.combos
                        vm.totalKgStr  = String(format: "%.0f", item.totalKg)
                        vm.loadPricesFromLibrary(item.snap)
                        vm.solve(library: item.snap, hardMaxByCode: item.hardMaxByCode)
                        return SolveOut(
                            code:       item.code,
                            origIngs:   item.origIngs,
                            resultIngs: vm.ingredients,
                            resultCons: vm.constraints,
                            lastSolve:  vm.lastSolve,
                            message:    vm.solveMessage,
                            conflicts:  item.conflicts
                        )
                    }.value
                }
            }
            for await out in grp { outputs.append(out) }
        }

        currentlySolvingName = nil

        // ── Sonuçları ana akışta yaz — ayrı Task YOK (kullanıcı arayüzüyle çakışma olmaz) ──
        // Her formül arasında Task.yield() → RunLoop UI'yı işleyebilir → donma yok
        let formulaByCode: [String: BlendFormula] = Dictionary(
            groupFormulas.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var newSolveResults = solveResults
        for out in outputs {
            guard let formula = formulaByCode[out.code] else { continue }
            let origByCode = Dictionary(out.origIngs.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
            var finalIngs  = out.resultIngs
            for i in finalIngs.indices {
                if let orig = origByCode[finalIngs[i].code] {
                    finalIngs[i].minPct         = orig.minPct
                    finalIngs[i].maxPct         = orig.maxPct
                    // Delta her zaman son "Üretime Kaydet" anındaki değere göre gösterilir
                    finalIngs[i].previousMixPct = orig.productionMixPct
                }
            }
            formula.ingredients  = finalIngs
            formula.constraints  = out.resultCons
            formula.updatedAt    = Date()
            if let s = out.lastSolve {
                formula.lastSolve      = s
                formula.recordedCostTL = s.costPerTon
            }
            let feasible = formula.lastSolve?.isFeasible ?? false
            let base     = out.message ?? ""
            let msg      = out.conflicts.isEmpty ? base
                : out.conflicts.joined(separator: "\n") + (base.isEmpty ? "" : "\n" + base)
            newSolveResults[out.code] = SolveResult(ok: feasible,
                                                    cost: formula.lastSolve?.costPerTon ?? 0,
                                                    message: msg)
            await Task.yield()   // her formülden sonra RunLoop'a bir tur
        }
        solveResults = newSolveResults

        // ── Post-solve: aylık MIN/MAX doğrulaması (limit varsa) ───────────────
        if !limitsMap.isEmpty, totalTons > 0 {
            let ingsByFormula: [String: [String: BFIngredient]] = Dictionary(
                groupFormulas.map { f in
                    (f.code, Dictionary(f.ingredients.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first }))
                }, uniquingKeysWith: { first, _ in first }
            )
            let libNameByCode = Dictionary(library.map { ($0.code, $0.name) }, uniquingKeysWith: { first, _ in first })
            for (ingCode, limit) in limitsMap {
                let ingName = libNameByCode[ingCode] ?? ingCode
                var actualTons: Double = 0
                for formula in groupFormulas {
                    let pct = ingsByFormula[formula.code]?[ingCode]?.mixPct ?? 0
                    actualTons += pct / 100.0 * (productionMap[formula.code] ?? 0)
                }
                if let minT = limit.minTons, minT > 0, actualTons < minT - 0.5 {
                    let shortage = minT - actualTons
                    let floor    = proRataMinPct[ingCode] ?? (minT / max(totalTons, 1) * 100.0)
                    for formula in groupFormulas {
                        let fTons  = productionMap[formula.code] ?? 0
                        guard fTons > 0 else { continue }
                        let ingInF = ingsByFormula[formula.code]?[ingCode]
                        let mixPct = ingInF?.mixPct ?? 0
                        guard mixPct / 100.0 * fTons < floor / 100.0 * fTons - 0.1 else { continue }
                        let reason: String
                        if ingInF == nil { reason = "hammadde formülde tanımlı değil" }
                        else if let fMax = ingInF?.maxPct, fMax > 0, fMax < floor - 0.001 {
                            reason = "max %\(String(format:"%.1f",fMax)) < gerekli %\(String(format:"%.1f",floor))"
                        } else { reason = "besin kısıtları bu formülde kullanımı engelliyor" }
                        let warn = "⚠️ MIN \(ingName): hedef \(String(format:"%.1f",minT))t → gerçek \(String(format:"%.1f",actualTons))t (\(String(format:"%.1f",shortage))t eksik) ← \(reason)"
                        let prev = solveResults[formula.code]
                        solveResults[formula.code] = SolveResult(
                            ok: prev?.ok ?? (formula.lastSolve?.isFeasible ?? false),
                            cost: prev?.cost ?? formula.lastSolve?.costPerTon ?? 0,
                            message: (prev?.message ?? "").isEmpty ? warn : (prev?.message ?? "") + "\n" + warn)
                    }
                }
                if let maxT = limit.maxTons, actualTons > maxT + 0.5 {
                    let excess = actualTons - maxT
                    let warn   = "⚠️ MAX \(ingName): hedef ≤\(String(format:"%.1f",maxT))t → gerçek \(String(format:"%.1f",actualTons))t (\(String(format:"%.1f",excess))t fazla)"
                    for formula in groupFormulas {
                        let pct = ingsByFormula[formula.code]?[ingCode]?.mixPct ?? 0
                        guard (productionMap[formula.code] ?? 0) > 0, pct > 0.001 else { continue }
                        let prev = solveResults[formula.code]
                        solveResults[formula.code] = SolveResult(
                            ok: prev?.ok ?? (formula.lastSolve?.isFeasible ?? false),
                            cost: prev?.cost ?? formula.lastSolve?.costPerTon ?? 0,
                            message: (prev?.message ?? "").isEmpty ? warn : (prev?.message ?? "") + "\n" + warn)
                    }
                }
            }
        }

        // context.save() kasıtlı yok — CloudKit WAL checkpoint'ini önler.
        isCalculating = false
        await Task.yield()
        refreshCombinedIngs()
    }
}

// MARK: - MIN / MAX ton fields (local @State so model only updates on commit)

private struct IngredientLimitFields: View {
    let ingCode: String
    @Binding var limits: [String: MonthlyIngLimit]

    @State private var minText: String = ""
    @State private var maxText: String = ""
    @FocusState private var focused: Field?

    enum Field { case min, max }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // MIN
            HStack(spacing: 3) {
                Text("MIN")
                    .font(.caption2.bold()).foregroundStyle(.blue)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 30, alignment: .leading)
                TextField("—", text: $minText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44, maxWidth: 72)
                    .font(.caption)
                    .focused($focused, equals: .min)
                    .onSubmit { commitMin() }
                    .onChange(of: focused) { old, new in
                        if old == .min && new != .min { commitMin() }
                    }
                Text("ton").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))

            // MAX
            HStack(spacing: 3) {
                Text("MAX")
                    .font(.caption2.bold()).foregroundStyle(.orange)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 30, alignment: .leading)
                TextField("—", text: $maxText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44, maxWidth: 72)
                    .font(.caption)
                    .focused($focused, equals: .max)
                    .onSubmit { commitMax() }
                    .onChange(of: focused) { old, new in
                        if old == .max && new != .max { commitMax() }
                    }
                Text("ton").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
        }
        .onAppear { loadFromModel() }
        .onChange(of: limits) { _, _ in
            // Sadece bu alan aktif değilken dışarıdan gelen değişikliği yansıt
            // (aktifken: kullanıcı yazıyor, döngüyü kır)
            if focused == nil { loadFromModel() }
        }
    }

    private func loadFromModel() {
        let lim = limits[ingCode]
        minText = lim?.minTons.map { String(format: "%.1f", $0) } ?? ""
        maxText = lim?.maxTons.map { String(format: "%.1f", $0) } ?? ""
    }

    private func commitMin() {
        let clean = minText.replacingOccurrences(of: ",", with: ".")
        var l = limits
        if clean.isEmpty {
            l[ingCode]?.minTons = nil
            if l[ingCode]?.maxTons == nil { l.removeValue(forKey: ingCode) }
        } else if let v = Double(clean) {
            var lim = l[ingCode] ?? MonthlyIngLimit()
            lim.minTons = v
            l[ingCode] = lim
        }
        limits = l
    }

    private func commitMax() {
        let clean = maxText.replacingOccurrences(of: ",", with: ".")
        var l = limits
        if clean.isEmpty {
            l[ingCode]?.maxTons = nil
            if l[ingCode]?.minTons == nil { l.removeValue(forKey: ingCode) }
        } else if let v = Double(clean) {
            var lim = l[ingCode] ?? MonthlyIngLimit()
            lim.maxTons = v
            l[ingCode] = lim
        }
        limits = l
    }
}

// MARK: - Production tons field (kendi state'i ile yazarken kayma olmaz)

private struct ProductionTonsField: View {
    let formulaCode: String
    @Binding var productionTons: [String: Double]

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 3) {
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 44, maxWidth: 72)
                .font(.caption.bold())
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
            Text("ton").font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { loadText() }
        .onChange(of: productionTons) { _, _ in
            if !isFocused { loadText() }
        }
    }

    private func loadText() {
        if let v = productionTons[formulaCode], v > 0 {
            text = String(format: "%.1f", v)
        } else {
            text = ""
        }
    }

    private func commit() {
        let clean = text.replacingOccurrences(of: ",", with: ".")
        var map = productionTons
        if clean.isEmpty {
            map.removeValue(forKey: formulaCode)
        } else if let v = Double(clean) {
            map[formulaCode] = v
        }
        productionTons = map
    }
}

// MARK: - Hammadde fiyat alanı (local state — her tuşta model güncellenmez)

private struct IngredientPriceField: View {
    let item:          CombinedIng
    let groupFormulas: [BlendFormula]

    @Environment(\.modelContext) private var context

    @State  private var text:      String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text("₺/ton").font(.caption2).foregroundStyle(.secondary)
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 50, maxWidth: 80)
                .font(.caption.bold())
                .focused($focused)
                .onSubmit    { commit() }
                .onChange(of: focused) { _, nowFocused in
                    if !nowFocused { commit() }
                }
        }
        .onAppear { load() }
        .onChange(of: item.libEntry?.priceTL) { _, _ in
            // Dışarıdan değer değişirse (örn. fiyat geçmişi sayfasından) — sadece odak dışındayken yansıt
            if !focused { load() }
        }
    }

    private func load() {
        guard let p = item.libEntry?.priceTL, p > 0 else { text = ""; return }
        text = String(format: "%.0f", p)
    }

    private func commit() {
        let clean = text.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: ",", with: ".")
        guard let v = Double(clean), v > 0,
              let lib = item.libEntry else { load(); return }
        lib.priceTL = v
        // Fiyat geçmişine otomatik kaydet
        context.insert(PriceHistoryEntry(ingredientName: lib.name, priceTL: v))
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            try? context.save()
        }
        load()
    }
}

// MARK: - Combined ingredient helper

private struct CombinedIng: Identifiable {
    let id           = UUID()
    let code:        String
    let name:        String
    let formulaCount: Int
    let libEntry:    FeedIngredient?
    var monthlyTons: Double = 0   // önceden hesaplanmış kullanım — ingredientRow'da re-compute yok
}

// MARK: - Hammadde Formül Kullanım Detayı

private struct IngredientUsageDetailSheet: View {
    let ingredient:     CombinedIng
    let groupFormulas:  [BlendFormula]
    let productionTons: [String: Double]

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    private var locale: Locale { Locale(identifier: "tr_TR") }

    // Her formülü temsil eder — formülde var mı yok mu dahil
    private struct FormulaUsage: Identifiable {
        let id:       String        // formula.code
        let formula:  BlendFormula
        let name:     String
        let code:     String
        let isActive: Bool          // hammadde bu formülde var mı
        let mixPct:   Double
        let minPct:   Double
        let maxPct:   Double
        let tons:     Double
    }

    private var usages: [FormulaUsage] {
        groupFormulas.map { formula in
            if let ing = formula.ingredients.first(where: { $0.code == ingredient.code }) {
                let fTons = productionTons[formula.code] ?? 0
                return FormulaUsage(
                    id:       formula.code,
                    formula:  formula,
                    name:     formula.name,
                    code:     formula.code,
                    isActive: true,
                    mixPct:   ing.mixPct,
                    minPct:   ing.minPct,
                    maxPct:   ing.maxPct,
                    tons:     ing.mixPct / 100.0 * fTons
                )
            } else {
                return FormulaUsage(
                    id:       formula.code,
                    formula:  formula,
                    name:     formula.name,
                    code:     formula.code,
                    isActive: false,
                    mixPct:   0, minPct: 0, maxPct: 100, tons: 0
                )
            }
        }
        // Aktifler önce, kendi içinde ton miktarına göre azalan
        .sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return $0.tons > $1.tons
        }
    }

    private var totalTons: Double {
        usages.filter(\.isActive).reduce(0) { $0 + $1.tons }
    }
    private var activeCount: Int { usages.filter(\.isActive).count }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = locale; n.numberStyle = .decimal
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    // Hammaddeyi formüle ekle (varsayılan min=0, max=100)
    private func activate(_ item: FormulaUsage) {
        var ings = item.formula.ingredients
        guard !ings.contains(where: { $0.code == ingredient.code }) else { return }
        let newIng = BFIngredient(
            id:                    UUID(),
            code:                  ingredient.code,
            name:                  ingredient.name,
            isActive:              true,
            hasStock:              ingredient.libEntry?.isAvailable ?? true,
            minPct:                0,
            maxPct:                100,
            mixPct:                0,
            productionMixPct:      0,
            previousMixPct:        0,
            overridePriceTLPerTon: ingredient.libEntry?.priceTL
        )
        ings.append(newIng)
        item.formula.ingredients = ings
        item.formula.updatedAt   = Date()
        try? context.save()
    }

    // Hammaddeyi formülden çıkar
    private func deactivate(_ item: FormulaUsage) {
        var ings = item.formula.ingredients
        ings.removeAll { $0.code == ingredient.code }
        item.formula.ingredients = ings
        item.formula.updatedAt   = Date()
        try? context.save()
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Özet ──────────────────────────────────────────────────────
                Section {
                    HStack {
                        Label("Kod", systemImage: "number").foregroundStyle(.secondary)
                        Spacer()
                        Text(ingredient.code.isEmpty ? "—" : "[\(ingredient.code)]")
                            .bold().foregroundStyle(.orange)
                    }
                    HStack {
                        Label("Toplam Kullanım", systemImage: "scalemass.fill").foregroundStyle(.secondary)
                        Spacer()
                        Text(totalTons > 0 ? "\(fmt(totalTons)) ton/ay" : "—")
                            .bold().foregroundStyle(.orange)
                    }
                    HStack {
                        Label("Aktif / Toplam", systemImage: "doc.on.doc").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(activeCount) / \(usages.count) formül").bold()
                    }
                }

                // ── Formüller (tümü) ───────────────────────────────────────
                Section {
                    ForEach(usages) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            // Başlık satırı
                            HStack(alignment: .top, spacing: 10) {
                                // Aktif/Pasif toggle
                                Button {
                                    item.isActive ? deactivate(item) : activate(item)
                                } label: {
                                    Image(systemName: item.isActive
                                          ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.title3)
                                        .foregroundStyle(item.isActive ? .green : .blue)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.subheadline.bold())
                                    Text(item.code).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.isActive {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(String(format: "%.2f%%", item.mixPct))
                                            .font(.callout.bold().monospacedDigit())
                                            .foregroundStyle(.indigo)
                                        if item.tons > 0 {
                                            Text("\(fmt(item.tons)) ton/ay")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                } else {
                                    Text("Formülde yok")
                                        .font(.caption).foregroundStyle(.tertiary)
                                        .padding(.top, 2)
                                }
                            }

                            // Aktifse: düzenlenebilir MIN / MAX + pay çubuğu
                            if item.isActive {
                                FormulaIngConstraintRow(
                                    formula: item.formula,
                                    ingCode: ingredient.code
                                )
                                .id(item.id)   // aktif/pasif geçişinde state'i sıfırla

                                if totalTons > 0 && item.tons > 0 {
                                    // scaleEffect kullanılır — GeometryReader layout pass yok
                                    let ratio = min(item.tons / totalTons, 1.0)
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.systemFill))
                                        Capsule()
                                            .fill(Color.indigo.opacity(0.7))
                                            .scaleEffect(x: ratio, anchor: .leading)
                                    }
                                    .frame(height: 5)
                                }
                            }

                            // Gölge Fiyat / Hassasiyet (Sensitivity) — son çözümden
                            IngSensitivityRow(formula: item.formula,
                                              ingCode: ingredient.code,
                                              isUsed: item.isActive && item.mixPct > 0.001)
                        }
                        .padding(.vertical, 4)
                        .opacity(item.isActive ? 1.0 : 0.45)
                    }
                } header: {
                    Text("Formüllerde Kullanım")
                } footer: {
                    Text("✓ = formülde aktif   +  = eklemek için dokun   MIN/MAX formüle özgü kısıtlardır.\n🛡 yeşil = fiyat artış toleransı (gölge fiyat)   ↓ turuncu = rasyona girmesi için gereken fiyat düşüşü (hassasiyet).")
                        .font(.caption2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(ingredient.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Hammadde Gölge Fiyat / Hassasiyet (Sensitivity) satırı
// Son LP çözümünden:
//   • Rasyonda olan hammadde → costRangeIncrease: fiyatı ne kadar artarsa rasyonda kalır
//   • Rasyonda olmayan hammadde → reducedCost: rasyona girmesi için fiyatı ne kadar düşmeli

private struct IngSensitivityRow: View {
    let formula: BlendFormula
    let ingCode: String
    let isUsed:  Bool

    var body: some View {
        if let solve = formula.lastSolve {
            content(solve)
        }
    }

    @ViewBuilder
    private func content(_ solve: BFSolveResult) -> some View {
        if isUsed {
            if let inc = solve.costRangeIncreases[ingCode] {
                if inc.isFinite, inc > 0 {
                    label(icon: "shield.lefthalf.filled", color: .green,
                          text: String(format: "Fiyatı +%.0f ₺/ton artana dek rasyonda kalır", inc))
                } else if !inc.isFinite {
                    label(icon: "shield.fill", color: .green,
                          text: "Fiyat artışından etkilenmez (geniş tolerans)")
                }
            }
        } else {
            if let drop = solve.reducedCosts[ingCode], drop.isFinite, drop > 0 {
                label(icon: "arrow.down.circle.fill", color: .orange,
                      text: String(format: "Rasyona girmesi için fiyatı −%.0f ₺/ton düşmeli", drop))
            }
        }
    }

    private func label(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
            Text(text).font(.caption).foregroundStyle(color)
            Spacer()
        }
        .padding(.top, 2)
    }
}

// MARK: - Formül içi hammadde MIN/MAX kısıt düzenleyici

private struct FormulaIngConstraintRow: View {
    let formula: BlendFormula
    let ingCode: String

    @Environment(\.modelContext) private var context

    @State private var minText = ""
    @State private var maxText = ""
    @FocusState private var focused: Field?

    enum Field { case min, max }

    var body: some View {
        HStack(spacing: 10) {
            // MIN %
            HStack(spacing: 4) {
                Text("MİN")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue)
                    .frame(width: 28, alignment: .leading)
                TextField("—", text: $minText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44, maxWidth: 65)
                    .font(.caption)
                    .focused($focused, equals: .min)
                    .onChange(of: focused) { old, new in
                        if old == .min && new != .min { commitMin() }
                    }
                Text("%").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 6))

            // MAX %
            HStack(spacing: 4) {
                Text("MAX")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                    .frame(width: 28, alignment: .leading)
                TextField("—", text: $maxText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44, maxWidth: 65)
                    .font(.caption)
                    .focused($focused, equals: .max)
                    .onChange(of: focused) { old, new in
                        if old == .max && new != .max { commitMax() }
                    }
                Text("%").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .onAppear { load() }
    }

    private func load() {
        guard let ing = formula.ingredients.first(where: { $0.code == ingCode }) else { return }
        minText = ing.minPct > 0      ? String(format: "%.2f", ing.minPct) : ""
        maxText = ing.maxPct < 100    ? String(format: "%.2f", ing.maxPct) : ""
    }

    private func commitMin() {
        let v = Double(minText.replacingOccurrences(of: ",", with: ".")) ?? 0
        var ings = formula.ingredients
        guard let i = ings.firstIndex(where: { $0.code == ingCode }) else { return }
        ings[i].minPct = max(0, v)
        formula.ingredients = ings
        formula.updatedAt   = Date()
        try? context.save()
    }

    private func commitMax() {
        let raw = maxText.replacingOccurrences(of: ",", with: ".")
        let v   = raw.isEmpty ? 100.0 : (Double(raw) ?? 100.0)
        var ings = formula.ingredients
        guard let i = ings.firstIndex(where: { $0.code == ingCode }) else { return }
        ings[i].maxPct = min(100, max(0, v))
        formula.ingredients = ings
        formula.updatedAt   = Date()
        try? context.save()
    }
}

// MARK: - Formula picker sheet

// MARK: - Kütüphaneden hammadde seç + formül bazlı yapılandır

private struct MultiBlendIngAddSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    let groupFormulas: [BlendFormula]
    let library: [FeedIngredient]

    // Hammadde seçimi
    @State private var search: String = ""
    @State private var selectedFeed: FeedIngredient? = nil

    // Her formül kodu için: aktif mi, min%, max%
    @State private var perFormula: [String: (active: Bool, min: String, max: String)] = [:]

    private var filtered: [FeedIngredient] {
        if search.isEmpty { return library.sorted { $0.name < $1.name } }
        let q = search.lowercased()
        return library.filter {
            $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Bölüm 1: Kütüphane Seçici ────────────────────────
                Section {
                    // Arama kutusu
                    TextField("Hammadde ara (ad veya kod)…", text: $search)
                        .textInputAutocapitalization(.never)

                    if let sel = selectedFeed {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sel.name).font(.subheadline.bold()).foregroundStyle(.orange)
                                Text(sel.code).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Değiştir") { selectedFeed = nil; perFormula = [:] }
                                .font(.caption).buttonStyle(.borderless).foregroundStyle(.blue)
                        }
                    } else {
                        ForEach(filtered) { feed in
                            Button {
                                selectedFeed = feed
                                buildPerFormula(for: feed)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(feed.name).font(.subheadline)
                                        Text(feed.code).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let p = feed.priceTL, p > 0 {
                                        Text(String(format: "%.0f ₺/ton", p))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Hammadde Seç")
                }

                // ── Bölüm 2: Formül Bazlı Yapılandırma ────────────────
                if selectedFeed != nil {
                    Section {
                        ForEach(groupFormulas) { formula in
                            formulaRow(formula)
                        }
                    } header: {
                        Text("Formüllerde Kullanım")
                    } footer: {
                        Text("Toggle açıkken LP çözümünde bu hammadde o formüle dahil edilir. Min%/Max% formüle özgü kısıtlardır.")
                            .font(.caption2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hammadde Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(selectedFeed == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func formulaRow(_ formula: BlendFormula) -> some View {
        let code = formula.code
        let cfg  = Binding<(active: Bool, min: String, max: String)>(
            get: { perFormula[code] ?? (false, "0", "100") },
            set: { perFormula[code] = $0 }
        )

        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { cfg.wrappedValue.active },
                                 set: { cfg.wrappedValue.active = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formula.name).font(.subheadline.bold()).lineLimit(1)
                    Text(formula.code).font(.caption2).foregroundStyle(.secondary)
                }
            }

            if cfg.wrappedValue.active {
                HStack(spacing: 16) {
                    // Min%
                    HStack(spacing: 4) {
                        Text("Min%").font(.caption).foregroundStyle(.secondary)
                        TextField("0", text: Binding(
                            get: { cfg.wrappedValue.min },
                            set: { cfg.wrappedValue.min = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .frame(width: 64)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline.monospacedDigit())
                    }
                    // Max%
                    HStack(spacing: 4) {
                        Text("Max%").font(.caption).foregroundStyle(.secondary)
                        TextField("100", text: Binding(
                            get: { cfg.wrappedValue.max },
                            set: { cfg.wrappedValue.max = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .frame(width: 64)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline.monospacedDigit())
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 2)
    }

    /// Hammadde seçilince her formül için mevcut değerleri ya da varsayılanları yükle
    private func buildPerFormula(for feed: FeedIngredient) {
        perFormula = [:]
        for formula in groupFormulas {
            if let existing = formula.ingredients.first(where: { $0.code == feed.code }) {
                perFormula[formula.code] = (
                    active: true,
                    min: String(format: "%g", existing.minPct),
                    max: String(format: "%g", existing.maxPct)
                )
            } else {
                perFormula[formula.code] = (active: false, min: "0", max: "100")
            }
        }
    }

    private func save() {
        guard let feed = selectedFeed else { return }
        for formula in groupFormulas {
            guard let cfg = perFormula[formula.code] else { continue }
            let minVal = Double(cfg.min.replacingOccurrences(of: ",", with: ".")) ?? 0
            let maxVal = Double(cfg.max.replacingOccurrences(of: ",", with: ".")) ?? 100
            var ings = formula.ingredients
            if let idx = ings.firstIndex(where: { $0.code == feed.code }) {
                if cfg.active {
                    // Mevcut → min/max güncelle
                    ings[idx].minPct = minVal
                    ings[idx].maxPct = max(minVal, maxVal)
                    ings[idx].isActive  = true
                    ings[idx].hasStock  = true
                } else {
                    // Toggle kapatıldıysa formülden çıkar
                    ings.remove(at: idx)
                }
            } else if cfg.active {
                // Yeni → BFIngredient oluştur
                ings.append(BFIngredient(
                    id:                    UUID(),
                    code:                  feed.code,
                    name:                  feed.name,
                    isActive:              true,
                    hasStock:              feed.isAvailable,
                    minPct:                minVal,
                    maxPct:                max(minVal, maxVal),
                    mixPct:                0,
                    productionMixPct:      0,
                    previousMixPct:        0,
                    overridePriceTLPerTon: (feed.priceTL ?? 0) > 0 ? feed.priceTL : nil
                ))
            }
            formula.ingredients = ings
            formula.updatedAt   = Date()
        }
        try? context.save()
    }
}

// MARK: - Formüle formül seçici

private struct MultiBlendFormulaPickerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    let group:     MultiBlendGroup
    let available: [BlendFormula]

    @State private var search = ""

    private var filtered: [BlendFormula] {
        guard !search.isEmpty else { return available }
        return available.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { formula in
                Button {
                    group.addFormula(code: formula.code)
                    try? context.save()
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formula.name).font(.subheadline.bold())
                            Text(formula.code).font(.caption).foregroundStyle(.secondary)
                            Text("\(formula.ingredients.count) hammadde")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(.indigo)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Formül ara…")
            .navigationTitle("Formül Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Export sheet (used inside FormulaEditorView)

struct MultiBlendExportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \MultiBlendGroup.createdAt, order: .reverse) private var groups: [MultiBlendGroup]

    let formulaCode: String

    @State private var showNewField = false
    @State private var newName      = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if showNewField {
                        HStack {
                            TextField("Grup Adı", text: $newName)
                            Button("Oluştur") {
                                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty else { return }
                                let g = MultiBlendGroup(name: trimmed)
                                g.addFormula(code: formulaCode)
                                context.insert(g)
                                try? context.save()
                                dismiss()
                            }
                            .fontWeight(.semibold)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            showNewField = true
                        } label: {
                            Label("Yeni Grup Oluştur", systemImage: "plus.circle")
                                .foregroundStyle(.indigo)
                        }
                    }
                }

                if !groups.isEmpty {
                    Section("Mevcut Gruplar") {
                        ForEach(groups) { group in
                            let already = group.formulaCodes.contains(formulaCode)
                            Button {
                                guard !already else { return }
                                group.addFormula(code: formulaCode)
                                try? context.save()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name).font(.subheadline)
                                        Text("\(group.formulaCodes.count) formül")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: already
                                          ? "checkmark.circle.fill"
                                          : "plus.circle")
                                        .foregroundStyle(already ? .green : .indigo)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(already)
                        }
                    }
                }
            }
            .navigationTitle("MultiBlend'e Aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Solve animation ring

private struct SolveProgressRing: View {
    @State private var rotation: Double = 0
    @State private var trimEnd:  Double = 0.25

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 5)
                .frame(width: 52, height: 52)
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                trimEnd = 0.75
            }
        }
    }
}

// MARK: - Maliyet Geçmişi Sheet

private struct CostHistorySheet: View {
    let formula: BlendFormula
    let entries: [FormulaCostEntry]

    private var dateLabel: (Date) -> String {
        { date in
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "tr_TR")
            fmt.dateFormat = "d MMM"
            return fmt.string(from: date)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Geçmiş Yok",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("\"Üretime Kaydet\" her basışta maliyet geçmişe eklenir.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // ── Grafik ────────────────────────────────────────
                            Chart(entries) { entry in
                                LineMark(
                                    x: .value("Tarih", entry.recordedAt),
                                    y: .value("₺/ton", entry.costPerTon)
                                )
                                .foregroundStyle(.orange)
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Tarih", entry.recordedAt),
                                    y: .value("₺/ton", entry.costPerTon)
                                )
                                .foregroundStyle(.orange)
                                .symbolSize(40)
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic) { val in
                                    AxisValueLabel {
                                        if let d = val.as(Date.self) {
                                            Text(dateLabel(d)).font(.caption2)
                                        }
                                    }
                                }
                            }
                            .chartYAxis {
                                AxisMarks { val in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let v = val.as(Double.self) {
                                            Text(String(format: "%.0f ₺", v)).font(.caption2)
                                        }
                                    }
                                }
                            }
                            .frame(height: 220)
                            .padding(.horizontal)

                            // ── Kayıt Listesi ─────────────────────────────────
                            VStack(spacing: 0) {
                                ForEach(entries.reversed()) { entry in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.recordedAt, style: .date)
                                                .font(.subheadline)
                                            if entry.tons > 0 {
                                                Text(String(format: "%.1f ton", entry.tons))
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text(String(format: "%.0f ₺/ton", entry.costPerTon))
                                            .font(.subheadline.bold().monospacedDigit())
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    Divider().padding(.leading, 16)
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                        .padding(.top)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("\(formula.name) — Maliyet")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Besin Karşılaştırma Sheet

private struct NutrientComparisonSheet: View {
    let formula: BlendFormula

    private var activeConstraints: [BFConstraint] {
        formula.constraints.filter { $0.isActive && ($0.currentValue != nil || $0.previousValue != nil) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeConstraints.isEmpty {
                    ContentUnavailableView(
                        "Veri Yok",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Aktif kısıt ve hesaplanmış değer bulunamadı.")
                    )
                } else {
                    List(activeConstraints) { con in
                        NutrientCompRow(constraint: con)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Besin Karşılaştırma")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(formula.name).font(.caption.bold())
                        Text(formula.code).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - MultiBlend LP Analizi Sheet

private struct MultiBlendGroupLPSheet: View {
    let group:         MultiBlendGroup
    let groupFormulas: [BlendFormula]
    let library:       [FeedIngredient]

    @Environment(\.dismiss) private var dismiss

    // IngLPEntry — her ortak hammadde için LP analiz özeti
    private struct IngLPEntry: Identifiable {
        let id:                UUID = UUID()
        let code:              String
        let name:              String
        let currentPrice:      Double
        let monthlyTons:       Double
        // Rasyonda olan formüllerde: fiyat artış toleransı tavanı
        let maxPriceCeiling:   Double?
        let bindingFormula:    String?
        // Rasyona girmeyen formüllerde: gerekli fiyat düşüşü
        let requiredDrops:     [(formulaName: String, drop: Double)]
    }

    // Formüller üretim tonajına göre azalan sırada
    private var sortedFormulas: [BlendFormula] {
        let tons = group.productionTons
        return groupFormulas.sorted { (tons[$0.code] ?? 0) > (tons[$1.code] ?? 0) }
    }

    private func formatTL(_ value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return (fmt.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)) + " ₺"
    }

    // Her hammadde için LP analiz hesapla
    private var lpEntries: [IngLPEntry] {
        let tons    = group.productionTons
        let libByCode = Dictionary(library.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })

        // Tüm grubun ortak hammaddelerini bul (en az 2 formülde olanlar + tüm kullanılanlar)
        var ingCodes = Set<String>()
        for f in groupFormulas { f.ingredients.forEach { ingCodes.insert($0.code) } }

        var entries: [IngLPEntry] = []
        for code in ingCodes {
            let libEntry   = libByCode[code]
            let price      = libEntry?.priceTL ?? 0
            let name       = libEntry?.name ?? groupFormulas.compactMap { f in
                f.ingredients.first { $0.code == code }?.name
            }.first ?? code

            // Aylık kullanım hesapla
            let monthlyT = groupFormulas.reduce(0.0) { sum, f in
                let pct  = f.ingredients.first { $0.code == code }?.mixPct ?? 0
                let fTon = tons[f.code] ?? 0
                return sum + pct / 100.0 * fTon
            }

            // Rasyonda olan formüllerde costRangeIncreases — en küçüğü bağlayan formül
            var minIncrease: Double? = nil
            var bindingName: String? = nil
            var requiredDrops: [(formulaName: String, drop: Double)] = []

            for f in groupFormulas {
                guard (tons[f.code] ?? 0) > 0, let solve = f.lastSolve else { continue }
                let isUsed = (f.ingredients.first { $0.code == code }?.mixPct ?? 0) > 0.001

                if isUsed {
                    if let inc = solve.costRangeIncreases[code], inc.isFinite {
                        if minIncrease == nil || inc < minIncrease! {
                            minIncrease = inc
                            bindingName = f.name
                        }
                    }
                } else {
                    if let drop = solve.reducedCosts[code], drop.isFinite, drop > 0.5 {
                        requiredDrops.append((formulaName: f.name, drop: drop))
                    }
                }
            }

            let ceiling: Double? = minIncrease.map { price + $0 }

            entries.append(IngLPEntry(
                code:             code,
                name:             name,
                currentPrice:     price,
                monthlyTons:      monthlyT,
                maxPriceCeiling:  ceiling,
                bindingFormula:   bindingName,
                requiredDrops:    requiredDrops.sorted { $0.drop < $1.drop }
            ))
        }

        // Aylık maliyet = fiyat × kullanım (azalan sıra)
        return entries.sorted { ($0.currentPrice * $0.monthlyTons) > ($1.currentPrice * $1.monthlyTons) }
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Formüller (üretim sırası) ─────────────────────────────────
                Section {
                    ForEach(sortedFormulas) { formula in
                        let tons    = group.productionTons[formula.code] ?? 0
                        let cost    = formula.lastSolve?.costPerTon ?? formula.currentCostTL
                        let totalTL = cost * tons
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formula.name).font(.subheadline.bold())
                                Text(formula.code).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if tons > 0 {
                                    Text(String(format: "%.1f ton/ay", tons))
                                        .font(.caption.bold()).foregroundStyle(.orange)
                                }
                                if cost > 0 {
                                    Text(String(format: "%.0f ₺/ton", cost))
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                if totalTL > 0 {
                                    Text(formatTL(totalTL))
                                        .font(.caption2.bold().monospacedDigit()).foregroundStyle(.primary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Formüller (Üretim Sırası)")
                }

                // ── Hammadde Hedef Fiyat Analizi ──────────────────────────────
                Section {
                    if lpEntries.isEmpty {
                        Text("Çözüm sonucu bulunamadı. Önce \"Hesapla\" çalıştırın.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(lpEntries) { entry in
                            ingLPRow(entry)
                        }
                    }
                } header: {
                    Text("Hammadde Hedef Fiyat Analizi")
                } footer: {
                    Text("Tavan fiyat: herhangi bir formülden düşmeden önce ödeyebileceğiniz maksimum alım fiyatı.\nGerekli düşüş: o hammaddenin belirtilen formüle girmesi için gereken fiyat indirimi.")
                        .font(.caption2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("LP Analizi — \(group.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func ingLPRow(_ entry: IngLPEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Başlık satırı
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.subheadline.bold())
                    Text(entry.code).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if entry.monthlyTons > 0 {
                        Text(String(format: "%.2f ton/ay", entry.monthlyTons))
                            .font(.caption.bold().monospacedDigit()).foregroundStyle(.orange)
                    }
                    if entry.currentPrice > 0 && entry.monthlyTons > 0 {
                        Text(formatTL(entry.currentPrice * entry.monthlyTons) + "/ay")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if entry.currentPrice > 0 {
                        Text(String(format: "%.0f ₺/ton", entry.currentPrice))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            // Tavan fiyat (yeşil)
            if let ceiling = entry.maxPriceCeiling, let binding = entry.bindingFormula {
                HStack(spacing: 5) {
                    Image(systemName: "shield.lefthalf.filled").font(.caption2).foregroundStyle(.green)
                    Text(String(format: "Tavan: %.0f ₺/ton", ceiling))
                        .font(.caption.bold()).foregroundStyle(.green)
                    Text("← \(binding)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Gerekli düşüşler (turuncu)
            ForEach(Array(entry.requiredDrops.prefix(3)), id: \.formulaName) { item in
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill").font(.caption2).foregroundStyle(.orange)
                    Text(String(format: "−%.0f ₺ → %@ rasyonuna girer", item.drop, item.formulaName))
                        .font(.caption).foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            // LP verisi yoksa
            if entry.maxPriceCeiling == nil && entry.requiredDrops.isEmpty && entry.monthlyTons > 0 {
                Text("LP verisi yok — formülü hesaplayın")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct NutrientCompRow: View {
    let constraint: BFConstraint

    private var current:  Double { constraint.currentValue  ?? 0 }
    private var previous: Double { constraint.previousValue ?? 0 }
    private var diff:     Double { current - previous }

    private var status: (icon: String, color: Color) {
        let cur = constraint.currentValue ?? 0
        let mn  = constraint.minValue
        let mx  = constraint.maxValue
        let ok  = (mn == nil || cur >= mn! - 0.001) && (mx == nil || cur <= mx! + 0.001)
        if ok       { return ("checkmark.circle.fill", .green) }
        if cur < (mn ?? 0) { return ("arrow.down.circle.fill", .red) }
        return ("arrow.up.circle.fill", .red)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(constraint.resolvedDisplayName)
                    .font(.subheadline.bold())
                // Hedef sınırlar
                HStack(spacing: 6) {
                    if let mn = constraint.minValue {
                        Text("Min: \(String(format: "%.2f", mn))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let mx = constraint.maxValue {
                        Text("Max: \(String(format: "%.2f", mx))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                // Şimdiki değer
                if let cur = constraint.currentValue {
                    Text(String(format: "%.3f %@", cur, constraint.unit))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(status.color)
                }
                // Önceki değer ve fark
                if constraint.previousValue != nil && constraint.currentValue != nil && previous > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: diff > 0.0001 ? "arrow.up" : diff < -0.0001 ? "arrow.down" : "minus")
                            .font(.system(size: 8, weight: .bold))
                        Text(String(format: "%+.3f", diff))
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(abs(diff) < 0.0001 ? Color.secondary : diff > 0 ? Color.green : Color.red)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
