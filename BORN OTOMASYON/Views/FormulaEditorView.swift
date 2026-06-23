import SwiftUI
import SwiftData
import Observation
import UniformTypeIdentifiers

// Σ(maxPct) < 100 durumunda kullanıcıya sunulan seçim bilgisi.
struct Step2Info: Equatable {
    let sumMaxPct:      Double
    let shortfallPct:   Double
}

// MARK: - Observable ViewModel

@Observable
final class FormulaEditorVM {
    var code:      String = ""
    var name:      String = ""
    var totalKgStr:String = "1000"

    var ingredients:   [BFIngredient]  = []
    var constraints:   [BFConstraint]  = []
    var combinations:  [BFCombination] = []
    var lastSolve:         BFSolveResult?  = nil
    var previousCostPerTon: Double?       = nil   // cost from the solve just before the latest one

    var isSolving       = false
    var solveMessage:   String?
    var validationError: String?
    var selectedTab     = 0            // 0 = Hammaddeler, 1 = Besin Maddeleri

    // ── Sınır bütünlüğü / öneri durumu ──────────────────────────────────────
    var step1Warnings:     [String] = []           // max<min tespit edildi (otomatik düzeltme öncesi açık uyarı)
    var pendingStep2Choice: Step2Info? = nil        // Σmax<100 — kullanıcı "Otomatik Çöz" / "Elle Düzenle" seçmeli
    var shortfallReports:  [ConstraintShortfallReport] = []  // kısıt sağlanamadığında sınır gevşetme önerileri

    var showIngredientPicker  = false
    var showConstraintPicker  = false
    var showTxtImport         = false
    var showTemplatePicker    = false
    var showCombinations      = false

    var totalKg: Double { Double(totalKgStr) ?? 1000 }

    // Sum of active ingredient percentages from last solve
    var solveSum: Double {
        guard let s = lastSolve else { return 0 }
        return s.percentagesByCode.values.reduce(0, +)
    }

    func validate() -> Bool {
        if code.trimmingCharacters(in: .whitespaces).isEmpty {
            validationError = "Formül kodu boş olamaz."; return false
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            validationError = "Formül adı boş olamaz."; return false
        }
        validationError = nil
        return true
    }

    func load(from formula: BlendFormula) {
        code         = formula.code
        name         = formula.name
        totalKgStr   = String(format: "%.0f", formula.totalKg)
        ingredients  = formula.ingredients
        constraints  = formula.constraints
        combinations = formula.combinations
        lastSolve    = formula.lastSolve
    }

    // Pull current library prices into every ingredient's overridePriceTLPerTon so the
    // displayed price is always up-to-date regardless of when the formula was last saved.
    func loadPricesFromLibrary<T: LibEntry>(_ library: [T]) {
        // O(1) dict lookup yerine O(N×M) IngredientMatcher.find() döngüsü kullanmıyoruz
        let libByCode: [String: T] = Dictionary(library.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        for i in 0..<ingredients.count {
            let code = ingredients[i].code
            guard let lib = libByCode[code] ?? library.first(where: { $0.name == ingredients[i].name }),
                  let price = lib.priceTL, price > 0
            else { continue }
            ingredients[i].overridePriceTLPerTon = price
        }
    }

    // Compute currentValue for every constraint from the existing ingredient mixPct + library,
    // without running the LP. Called on load and whenever constraints are added.
    func computeNutrients(library: [FeedIngredient]) {
        // O(1) dict lookup — her kısıt için tüm kütüphane taranmıyor
        let libByCode: [String: FeedIngredient] = Dictionary(
            library.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let activeIngs = ingredients.filter { $0.isActive && $0.mixPct > 0 }
        for i in 0..<constraints.count {
            let key = constraints[i].nutrientKey
            var total   = 0.0
            var hasData = false
            for ing in activeIngs {
                let lib = libByCode[ing.code]
                if let v = lib?.nutrientValue(forKey: key) {
                    total   += ing.mixPct / 100.0 * v
                    hasData  = true
                }
            }
            if hasData {
                constraints[i].currentValue = total
            }
        }
    }

    func applyToFormula(_ formula: BlendFormula) {
        formula.code         = code.trimmingCharacters(in: .whitespaces)
        formula.name         = name.trimmingCharacters(in: .whitespaces)
        formula.totalKg      = totalKg
        formula.ingredients  = ingredients
        formula.constraints  = constraints
        formula.combinations = combinations
        formula.updatedAt    = Date()
        if let s = lastSolve {
            formula.lastSolve    = s
            formula.recordedCostTL = s.costPerTon
        }
    }

    // Apply a template: merge ingredients and constraints; existing ones are not overwritten.
    // TXT-imported ingredients that match template ingredients are forced to isActive+hasStock.
    func applyTemplate(_ template: FormulaTemplate, library: [FeedIngredient]) {
        // Ingredients from template
        for ti in template.ingredients {
            if let idx = ingredients.firstIndex(where: { $0.code == ti.code || $0.name == ti.name }) {
                // Already exists: force active + in stock, update bounds if default
                ingredients[idx].isActive = true
                ingredients[idx].hasStock = true
                if ingredients[idx].minPct == 0 { ingredients[idx].minPct = ti.minPct }
                if ingredients[idx].maxPct == 100 { ingredients[idx].maxPct = ti.maxPct }
            } else {
                // Add new ingredient (find library entry for nutrient data)
                let lib = IngredientMatcher.find(code: ti.code, name: ti.name, in: library)
                ingredients.append(BFIngredient(
                    id:                    UUID(),
                    code:                  lib?.code ?? ti.code,
                    name:                  lib?.name ?? ti.name,
                    isActive:              true,
                    hasStock:              true,
                    minPct:                ti.minPct,
                    maxPct:                ti.maxPct,
                    mixPct:                0,
                    productionMixPct:      0,
                    previousMixPct:        0,
                    overridePriceTLPerTon: lib?.priceTL.map { $0 > 0 ? $0 : nil } ?? nil
                ))
            }
        }
        // Constraints from template
        for tc in template.constraints {
            if !constraints.contains(where: { $0.nutrientKey == tc.nutrientKey }) {
                constraints.append(tc)
            } else if let idx = constraints.firstIndex(where: { $0.nutrientKey == tc.nutrientKey }) {
                // Update bounds if template has them and current doesn't
                if constraints[idx].minValue == nil, let v = tc.minValue { constraints[idx].minValue = v }
                if constraints[idx].maxValue == nil, let v = tc.maxValue { constraints[idx].maxValue = v }
            }
        }
    }

    // Solve LP — works with any LibEntry (FeedIngredient on main, IngSnap on background)
    // hardMaxByCode: aylık limit nedeniyle uygulanan maxPct kapları — autoRelaxed bunları aşamaz
    // autoRelaxStep2: Σmax<100 durumunda kullanıcı "Otomatik Çöz"ü onaylarsa true geçilir;
    // aksi halde solve durur ve pendingStep2Choice set edilir — hiçbir sınır sessizce değişmez.
    func solve<T: LibEntry>(library: [T], hardMaxByCode: [String: Double] = [:], autoRelaxStep2: Bool = false) {
        isSolving         = true
        solveMessage      = nil
        step1Warnings     = []
        pendingStep2Choice = nil
        shortfallReports  = []

        // Save current solve cost as "previous" before overwriting
        if let current = lastSolve, current.isFeasible {
            previousCostPerTon = current.costPerTon
        }

        // ── Build solver ingredients ──────────────────────────────────────────
        var noPriceIngs: [String] = []
        let solverIngs: [SolverIngredient] = ingredients.compactMap { ing -> SolverIngredient? in
            guard ing.isActive, ing.hasStock else { return nil }
            let lib = IngredientMatcher.find(code: ing.code, name: ing.name, in: library)
            var nutrients: [String: Double] = [:]
            for def in allNutrientDefs {
                if let v = lib?.nutrientValue(forKey: def.key) { nutrients[def.key] = v }
            }
            for def in AlapalaFormulaParser.codeMap.values {
                if nutrients[def.key] == nil, let v = lib?.nutrientValue(forKey: def.key) {
                    nutrients[def.key] = v
                }
            }
            let rawPrice = ing.overridePriceTLPerTon ?? lib?.priceTL ?? 0
            // Use nominal 1 ₺/ton for ingredients without price data so they are not
            // excluded from the LP. The cost result will be flagged as approximate.
            let price: Double
            if rawPrice > 0 {
                price = rawPrice
            } else {
                price = 1.0
                noPriceIngs.append(ing.name)
            }
            return SolverIngredient(code: ing.code, name: ing.name,
                                    priceTLPerTon: price,
                                    minPct: ing.minPct, maxPct: ing.maxPct,
                                    nutrients: nutrients)
        }

        // ── Step 1: detect maxPct < minPct — warn explicitly, then still raise max to min ───
        // (Happens when user sets a min% higher than the TXT-imported max%. The fix still
        // applies so the LP can run, but it is now always surfaced via step1Warnings — never silent.)
        for i in solverIngs where i.maxPct < i.minPct {
            step1Warnings.append("❌ \(i.name): min %\(String(format:"%.2f", i.minPct)) > max %\(String(format:"%.2f", i.maxPct)) — max otomatik olarak min seviyesine yükseltildi, kalıcı çözüm için max'ı elle düzeltin")
        }
        let minMaxFixed: [SolverIngredient] = solverIngs.map { i in
            guard i.maxPct < i.minPct else { return i }
            return SolverIngredient(code: i.code, name: i.name,
                                    priceTLPerTon: i.priceTLPerTon,
                                    minPct: i.minPct,
                                    maxPct: i.minPct,   // raise max to the required min
                                    nutrients: i.nutrients)
        }

        // ── Step 2: Σmax < 100 — ask the user instead of silently scaling ────────
        // (Happens when TXT ingredients are removed and their pct-based maxPct no longer sums to 100)
        // ÖNEMLI: Aylık limit (hardMaxByCode) nedeniyle sum < 100 ise, ölçekleme bu limitleri aşamaz.
        var usedAutoRelaxStep2 = false
        let sumMaxSolver = minMaxFixed.reduce(0.0) { $0 + $1.maxPct }
        var readyIngs: [SolverIngredient]
        if sumMaxSolver < 100 - 1e-6 {
            if autoRelaxStep2 {
                let scale = 100.0 / sumMaxSolver
                readyIngs = minMaxFixed.map { i in
                    SolverIngredient(code: i.code, name: i.name,
                                     priceTLPerTon: i.priceTLPerTon,
                                     minPct: i.minPct,
                                     maxPct: min(i.maxPct * scale, 100),
                                     nutrients: i.nutrients)
                }
                usedAutoRelaxStep2 = true
            } else {
                pendingStep2Choice = Step2Info(sumMaxPct: sumMaxSolver, shortfallPct: 100 - sumMaxSolver)
                let msg = "❌ Hammadde max sınırlarının toplamı %\(String(format:"%.1f", sumMaxSolver)) < %100 — eksik %\(String(format:"%.1f", 100 - sumMaxSolver)) için hammadde max'larını artırın, veya \"Otomatik Çöz\"ü seçin."
                lastSolve = BFSolveResult(percentagesByCode: [:], costPerTon: 0, nutrientValues: [:],
                                          isFeasible: false, message: msg)
                solveMessage = msg
                isSolving    = false
                return
            }
        } else {
            readyIngs = minMaxFixed
        }
        // Aylık limit kaplarını otomatik genişletmenin üzerine yeniden uygula
        // → ölçekleme hiçbir zaman aylık limiti aşamaz
        if !hardMaxByCode.isEmpty {
            readyIngs = readyIngs.map { i in
                guard let cap = hardMaxByCode[i.code] else { return i }
                return SolverIngredient(code: i.code, name: i.name,
                                        priceTLPerTon: i.priceTLPerTon,
                                        minPct: i.minPct,
                                        maxPct: min(i.maxPct, cap),
                                        nutrients: i.nutrients)
            }
        }

        // ── Build nutritional constraints — ALL user-set active constraints go in ─
        // The LP itself determines feasibility; no pre-filtering by data presence.
        let filteredCons: [SolverConstraint] = constraints.compactMap { c -> SolverConstraint? in
            guard c.isActive else { return nil }
            guard c.minValue != nil || c.maxValue != nil else { return nil }
            return SolverConstraint(key: c.nutrientKey, minValue: c.minValue, maxValue: c.maxValue)
        }

        // ── Build combination constraints (kg → % conversion) ──────────────────
        let solverCombinations: [SolverCombination] = combinations.compactMap { combo -> SolverCombination? in
            let activeCodes = combo.ingredientCodes.filter { code in
                ingredients.contains { $0.code == code && $0.isActive && $0.hasStock }
            }
            guard !activeCodes.isEmpty, combo.minKg != nil || combo.maxKg != nil else { return nil }
            return SolverCombination(
                ingredientCodes: activeCodes,
                minPct: combo.minKg.map { $0 / totalKg * 100 },
                maxPct: combo.maxKg.map { $0 / totalKg * 100 }
            )
        }

        // ── Attempt 1: with ALL nutritional constraints ───────────────────────
        var result = RationSolver.solve(ingredients: readyIngs, constraints: filteredCons, combinations: solverCombinations)

        // ── Iterative constraint relaxation (when infeasible) ─────────────────
        // Goal: satisfy as many constraints as possible; NEVER silently drop all.
        // Result is marked ❌ when any constraint is relaxed.
        var relaxedConMsgs: [String] = []

        if !result.isFeasible && !filteredCons.isEmpty {
            var workingCons = filteredCons

            // Phase 1 — remove constraints that are individually infeasible
            // (no ingredient provides this nutrient at all — nothing to maximize toward)
            var soloInfeasible = IndexSet()
            for (i, con) in workingCons.enumerated() {
                let solo = RationSolver.solve(ingredients: readyIngs, constraints: [con], combinations: solverCombinations)
                if !solo.isFeasible {
                    let name    = constraints.first { $0.nutrientKey == con.key }?.resolvedDisplayName ?? con.key
                    let hasData = readyIngs.contains { ($0.nutrients[con.key] ?? 0) > 1e-9 }
                    let reason  = hasData
                        ? "hammadde kısıtlarıyla bu sınır sağlanamıyor — min/max % veya aylık limiti gözden geçirin"
                        : "formüldeki hammaddelerde bu besin maddesi verisi yok — uygun hammadde ekleyin"
                    relaxedConMsgs.append("❌ \(name): \(reason)")
                    soloInfeasible.insert(i)
                }
            }
            workingCons = workingCons.enumerated()
                .filter { !soloInfeasible.contains($0.offset) }
                .map { $0.element }
            result = RationSolver.solve(ingredients: readyIngs, constraints: workingCons, combinations: solverCombinations)

            // Phase 2 — determine which interacting constraints must be sacrificed, one at a
            // time, in the same greedy order as before — but record them instead of just
            // discarding, so their value can be recovered via the lexicographic fallback below.
            var droppedOrder: [SolverConstraint] = []
            while !result.isFeasible && !workingCons.isEmpty {
                var resolved = false
                for i in stride(from: workingCons.count - 1, through: 0, by: -1) {
                    var testCons = workingCons
                    testCons.remove(at: i)
                    let testResult = RationSolver.solve(ingredients: readyIngs, constraints: testCons, combinations: solverCombinations)
                    if testResult.isFeasible || testCons.isEmpty {
                        droppedOrder.append(workingCons[i])
                        workingCons = testCons
                        result      = testResult
                        resolved    = true
                        break
                    }
                }
                if !resolved {
                    droppedOrder.append(contentsOf: workingCons)
                    result = RationSolver.solve(ingredients: readyIngs, constraints: [], combinations: solverCombinations)
                    workingCons = []
                }
            }

            if !droppedOrder.isEmpty {
                let (lexResult, achieved) = RationSolver.solveLexicographic(
                    ingredients: readyIngs, hardConstraints: workingCons,
                    droppedInOrder: droppedOrder, combinations: solverCombinations)
                result = lexResult

                for dropped in droppedOrder {
                    let name = constraints.first { $0.nutrientKey == dropped.key }?.resolvedDisplayName ?? dropped.key
                    if let achievedValue = achieved[dropped.key] {
                        let target = dropped.minValue ?? dropped.maxValue ?? 0
                        relaxedConMsgs.append("⚠️ \(name): hedef %\(String(format:"%.2f", target)), mevcut sınırlarla ulaşılabilen en iyi değer %\(String(format:"%.2f", achievedValue)) ile çözüldü")
                        if let report = RationSolver.buildShortfallReport(
                            ingredients: readyIngs, survivingConstraints: workingCons,
                            combinations: solverCombinations, droppedConstraint: dropped) {
                            shortfallReports.append(report)
                        }
                    } else {
                        relaxedConMsgs.append("⚠️ \(name): çözüm bulunamadı")
                    }
                }
            }
        }

        // Post-verification: relaxation may have been overly conservative (e.g. a solo-infeasible
        // constraint is actually feasible in the full LP). Re-try the original constraint set; if it
        // passes, clear all relaxation flags so we don't report a false "kısmi çözüm".
        if !relaxedConMsgs.isEmpty && result.isFeasible {
            let reCheck = RationSolver.solve(ingredients: readyIngs, constraints: filteredCons, combinations: solverCombinations)
            if reCheck.isFeasible {
                result = reCheck
                relaxedConMsgs = []
                shortfallReports = []
            }
        }

        let anyConstraintRelaxed = !relaxedConMsgs.isEmpty

        // Save original mixPct values BEFORE the LP result overwrites them.
        // This map is used later for nutrient calculation when LP returned no percentages.
        let originalMixPct: [String: Double] = Dictionary(
            ingredients.map { ($0.code, $0.mixPct) }, uniquingKeysWith: { first, _ in first }
        )

        // ── Write results back ────────────────────────────────────────────────
        for i in 0..<ingredients.count {
            let pct = result.percentagesByCode[ingredients[i].code] ?? 0
            ingredients[i].previousMixPct = ingredients[i].mixPct
            ingredients[i].mixPct         = pct
        }

        // Compute nutrient values for ALL constraints.
        // Priority:
        //   1) LP computed this nutrient
        //   2) Weighted-average from library using LP percentages
        //   3) Weighted-average from library using original (TXT) mixPct  ← key fix
        //   4) Keep pre-existing value (e.g. Alapala import)
        let lpPct = result.percentagesByCode
        for i in 0..<constraints.count {
            constraints[i].previousValue = constraints[i].currentValue
            let key = constraints[i].nutrientKey

            // 1. LP solver already computed this nutrient
            if let v = result.nutrientValues[key] {
                constraints[i].currentValue = v
                continue
            }

            // 2. Weighted-average using LP result percentages
            var total    = 0.0
            var hasData  = false
            for ing in ingredients {
                guard ing.isActive else { continue }
                let pct = lpPct[ing.code] ?? 0
                guard pct > 0 else { continue }
                let lib = IngredientMatcher.find(code: ing.code, name: ing.name, in: library)
                if let v = lib?.nutrientValue(forKey: key) {
                    total   += pct / 100.0 * v
                    hasData  = true
                }
            }
            if hasData {
                constraints[i].currentValue = total
                continue
            }

            // 3. Weighted-average using the ORIGINAL (TXT) mixPct saved before LP overwrote them
            var total2   = 0.0
            var hasData2 = false
            for ing in ingredients {
                guard ing.isActive else { continue }
                let pct = originalMixPct[ing.code] ?? 0
                guard pct > 0 else { continue }
                let lib = IngredientMatcher.find(code: ing.code, name: ing.name, in: library)
                if let v = lib?.nutrientValue(forKey: key) {
                    total2   += pct / 100.0 * v
                    hasData2  = true
                }
            }
            if hasData2 {
                constraints[i].currentValue = total2
                continue
            }

            // 4. Keep the value imported from TXT (don't overwrite with nil)
        }

        // ── Build result message ──────────────────────────────────────────────
        var msgs: [String] = []
        if result.isFeasible && !anyConstraintRelaxed {
            msgs.append("✅ Çözüm başarılı — tüm kısıtlar sağlandı")
        } else if anyConstraintRelaxed {
            msgs.append("⚠️ Kısmi çözüm — bazı besin kısıtları sağlanamadı:")
            msgs.append(contentsOf: relaxedConMsgs)
            for report in shortfallReports {
                let name = constraints.first { $0.nutrientKey == report.constraintKey }?.resolvedDisplayName ?? report.constraintKey
                for s in report.suggestions.prefix(3) {
                    let ingName = readyIngs.first { $0.code == s.ingredientCode }?.name ?? s.ingredientCode
                    let boundLabel = s.bound == .maxPct ? "max" : "min"
                    msgs.append("   → \(name) için: \(ingName) \(boundLabel) %\(String(format:"%.2f", s.currentValue))→%\(String(format:"%.2f", s.suggestedValue)) yapılırsa maliyet \(String(format:"%.0f", s.resultingCostPerTon))₺/ton")
                }
            }
        } else {
            msgs.append("❌ \(result.message)")
        }
        if usedAutoRelaxStep2 {
            msgs.append("ℹ️ Hammadde max sınırlarının toplamı %100'ün altındaydı — kullanıcı onayıyla orantılı olarak genişletildi")
        }
        if !step1Warnings.isEmpty {
            msgs.append(contentsOf: step1Warnings)
        }
        if !noPriceIngs.isEmpty {
            msgs.append("ℹ️ \(noPriceIngs.count) hammadde için fiyat yok — nominal 1₺/ton kullanıldı, maliyet tahmini değil: "
                        + noPriceIngs.prefix(3).joined(separator: ", "))
        }
        let finalMsg = msgs.joined(separator: "\n")

        lastSolve = BFSolveResult(
            percentagesByCode:  result.percentagesByCode,
            costPerTon:         result.costPerTon,
            nutrientValues:     result.nutrientValues,
            isFeasible:         result.isFeasible && !anyConstraintRelaxed,
            message:            finalMsg,
            reducedCosts:       result.reducedCosts,
            costRangeIncreases: result.costRangeIncreases,
            shadowPricesMin:    result.shadowPricesMin,
            shadowPricesMax:    result.shadowPricesMax,
            shortfallReports:   shortfallReports
        )
        solveMessage = finalMsg
        isSolving    = false
    }
}

// MARK: - FormulaEditorView

struct FormulaEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Query private var library: [FeedIngredient]

    let formula:          BlendFormula?
    let showCloseButton:  Bool     // true when presented as a sheet (e.g. from MultiBlend)
    let previousCostTL:   Double   // ₺/ton before last MultiBlend solve (0 = no context)
    let productionTons:   Double   // monthly tons from group (0 = no context)

    @State private var vm                    = FormulaEditorVM()
    @State private var showMultiBlendExport  = false
    @State private var showFormulaExport     = false
    @State private var showAssistant         = false
    @State private var breakdownTarget:      BreakdownTarget? = nil
    @State private var nutrientIngredient:   FeedIngredient?  = nil

    init(formula: BlendFormula?, showCloseButton: Bool = false,
         previousCostTL: Double = 0, productionTons: Double = 0) {
        self.formula         = formula
        self.showCloseButton = showCloseButton
        self.previousCostTL  = previousCostTL
        self.productionTons  = productionTons
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerFields
                if previousCostTL > 0 && productionTons > 0 {
                    costComparisonBanner
                }
                tabBar
                tabContent
            }
            .navigationTitle(formula == nil ? "Yeni Formül" : vm.name.isEmpty ? "Formül" : vm.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert(
                "Hammadde max sınırları %100'ün altında",
                isPresented: Binding(
                    get: { vm.pendingStep2Choice != nil },
                    set: { if !$0 { vm.pendingStep2Choice = nil } }
                )
            ) {
                Button("Otomatik Çöz") {
                    Task { await solveAction(autoRelaxStep2: true) }
                }
                Button("Elle Düzenle", role: .cancel) { vm.pendingStep2Choice = nil }
            } message: {
                if let info = vm.pendingStep2Choice {
                    Text("Max sınırların toplamı %\(String(format: "%.1f", info.sumMaxPct)) — eksik %\(String(format: "%.1f", info.shortfallPct)). Otomatik çöz, tüm hammaddelerin max'ını orantılı olarak büyütür. Elle düzenle ise hiçbir sınırı değiştirmez; ilgili hammaddelerin max'ını kendiniz artırmanız gerekir.")
                }
            }
            .sheet(isPresented: $vm.showIngredientPicker, onDismiss: {
                vm.loadPricesFromLibrary(library)
                vm.computeNutrients(library: library)
            }) {
                IngredientPickerSheet(vm: vm, library: library)
            }
            .sheet(isPresented: $vm.showConstraintPicker, onDismiss: {
                vm.computeNutrients(library: library)
            }) {
                ConstraintPickerSheet(vm: vm)
            }
            .fileImporter(
                isPresented: $vm.showTxtImport,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleTxtImport(result)
            }
            .sheet(isPresented: $vm.showTemplatePicker, onDismiss: {
                vm.computeNutrients(library: library)
            }) {
                TemplatePickerSheet { template in
                    vm.applyTemplate(template, library: library)
                }
            }
            .sheet(isPresented: $showMultiBlendExport) {
                MultiBlendExportSheet(formulaCode: vm.code)
            }
            .sheet(isPresented: $showFormulaExport) {
                if let f = formula {
                    FormulaExportSheet(formula: f, library: library)
                }
            }
            .sheet(isPresented: $showAssistant) {
                RationAssistantSheet(vm: vm)
            }
            .sheet(isPresented: $vm.showCombinations) {
                CombinationsView(
                    combinations: $vm.combinations,
                    ingredients:  vm.ingredients,
                    totalKg:      vm.totalKg,
                    lastSolve:    vm.lastSolve
                )
            }
            .sheet(item: $breakdownTarget) { target in
                NutrientBreakdownSheet(target: target)
            }
            .sheet(item: $nutrientIngredient) { ing in
                EditIngredientView(ingredient: ing)
            }
        }
        .onAppear {
            if let f = formula { vm.load(from: f) }
            vm.loadPricesFromLibrary(library)    // always show current library prices
            vm.computeNutrients(library: library)
        }
        .onChange(of: vm.constraints.count) { _, _ in
            vm.computeNutrients(library: library)
        }
    }

    // MARK: - Maliyet Karşılaştırma Banner (sadece MultiBlend'den açıldığında)

    @ViewBuilder
    private var costComparisonBanner: some View {
        let currentCost  = formula?.currentCostTL ?? 0
        let prevTotal    = previousCostTL * productionTons
        let currTotal    = currentCost    * productionTons
        let diff         = currTotal - prevTotal
        let pct          = prevTotal > 0 ? diff / prevTotal * 100 : 0
        let diffColor: Color = diff < -0.5 ? .green : diff > 0.5 ? .red : .secondary

        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Önceki Üretim").font(.caption2).foregroundStyle(.secondary)
                Text(prevTotal > 0 ? String(format: "%.0f ₺", prevTotal) : "—")
                    .font(.subheadline.bold()).foregroundStyle(.secondary)
                Text(String(format: "%.0f ₺/ton", previousCostTL))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Image(systemName: diff < -0.5 ? "arrow.down.circle.fill"
                               : diff > 0.5  ? "arrow.up.circle.fill"
                                             : "minus.circle")
                    .font(.title3).foregroundStyle(diffColor)
                if abs(diff) > 0.5 {
                    Text(String(format: "%+.1f%%", pct))
                        .font(.caption2.bold()).foregroundStyle(diffColor)
                }
            }
            .frame(minWidth: 44, maxWidth: 72)

            VStack(spacing: 2) {
                Text("Güncel Üretim").font(.caption2).foregroundStyle(.secondary)
                Text(currTotal > 0 ? String(format: "%.0f ₺", currTotal) : "—")
                    .font(.subheadline.bold()).foregroundStyle(.orange)
                if currentCost > 0 {
                    Text(String(format: "%.0f ₺/ton", currentCost))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground))
        Divider()
    }

    // MARK: - Header

    private var headerFields: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kod").font(.caption2).foregroundStyle(.secondary)
                    TextField("Formül Kodu", text: $vm.code)
                        .textInputAutocapitalization(.characters)
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: 120)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Adı").font(.caption2).foregroundStyle(.secondary)
                    TextField("Formül Adı", text: $vm.name)
                        .font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Parti (kg)").font(.caption2).foregroundStyle(.secondary)
                    TextField("1000", text: $vm.totalKgStr)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline)
                        .frame(minWidth: 60, maxWidth: 90)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))

            if let err = vm.validationError {
                Text(err).font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
            }

            Divider()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        Picker("", selection: $vm.selectedTab) {
            Text("Hammaddeler").tag(0)
            Text("Besin Maddeleri").tag(1)
            if vm.lastSolve != nil { Text("Sonuç").tag(2) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch vm.selectedTab {
        case 0: ingredientsTab
        case 1: constraintsTab
        case 2: resultTab
        default: EmptyView()
        }
    }

    // MARK: - Hammaddeler tab

    private var ingredientsTab: some View {
        List {
            // Solve result summary strip
            if let s = vm.lastSolve, let formula = formula {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: s.isFeasible ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundStyle(s.isFeasible ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.isFeasible
                                 ? String(format: "%.0f ₺/ton · %@ çözüldü", s.costPerTon, s.solvedAt.trClock)
                                 : s.message)
                                .font(.subheadline)
                                .foregroundColor(s.isFeasible ? .primary : .red)
                            if let prev = vm.previousCostPerTon, s.isFeasible {
                                let diff = s.costPerTon - prev
                                let sign = diff >= 0 ? "+" : ""
                                Text(String(format: "Önceki: %.0f ₺/ton  (%@%.0f ₺)", prev, sign, diff))
                                    .font(.caption)
                                    .foregroundStyle(diff > 0 ? .red : diff < 0 ? .green : .secondary)
                            }
                        }
                        Spacer()
                        NavigationLink(destination: LPAnalysisView(formula: formula)) {
                            Label("LP", systemImage: "waveform.path.ecg.rectangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.purple.opacity(0.12),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let s = vm.lastSolve {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: s.isFeasible ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundStyle(s.isFeasible ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.isFeasible
                                 ? String(format: "%.0f ₺/ton · %@ çözüldü", s.costPerTon, s.solvedAt.trClock)
                                 : s.message)
                                .font(.subheadline)
                                .foregroundColor(s.isFeasible ? .primary : .red)
                            if let prev = vm.previousCostPerTon, s.isFeasible {
                                let diff = s.costPerTon - prev
                                let sign = diff >= 0 ? "+" : ""
                                Text(String(format: "Önceki: %.0f ₺/ton  (%@%.0f ₺)", prev, sign, diff))
                                    .font(.caption)
                                    .foregroundStyle(diff > 0 ? .red : diff < 0 ? .green : .secondary)
                            }
                        }
                    }
                }
            }

            // Ingredient rows — sorted by mixPct desc when solved
            let usedIngs    = vm.ingredients.filter { $0.mixPct > 0.001 }.sorted { $0.mixPct > $1.mixPct }
            let unusedIngs  = vm.ingredients.filter { $0.mixPct <= 0.001 }

            if vm.lastSolve != nil && !usedIngs.isEmpty {
                Section {
                    ForEach(usedIngs.map { ing in
                        Binding(
                            get: { vm.ingredients.first { $0.id == ing.id } ?? ing },
                            set: { updated in
                                if let i = vm.ingredients.firstIndex(where: { $0.id == updated.id }) {
                                    vm.ingredients[i] = updated
                                }
                            }
                        )
                    }, id: \.id) { $ing in
                        IngredientEditorRow(ing: $ing, totalKg: vm.totalKg, solved: true)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    nutrientIngredient = library.first { $0.code == ing.code }
                                } label: {
                                    Label("Besin Değerleri", systemImage: "chart.bar.doc.horizontal")
                                }
                                .tint(.indigo)
                            }
                    }
                } header: {
                    HStack {
                        Text("Kullanılan Hammaddeler (\(usedIngs.count))")
                        Spacer()
                        Button { vm.showTemplatePicker = true } label: {
                            Label("Şablon", systemImage: "doc.badge.gearshape")
                                .font(.caption)
                        }
                        .foregroundStyle(.purple)
                        Button { vm.showIngredientPicker = true } label: {
                            Label("Ekle", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        Button { vm.showTxtImport = true } label: {
                            Label("TXT", systemImage: "doc.badge.plus")
                                .font(.caption)
                        }
                    }
                }

                if !unusedIngs.isEmpty {
                    Section {
                        ForEach(unusedIngs.map { ing in
                            Binding(
                                get: { vm.ingredients.first { $0.id == ing.id } ?? ing },
                                set: { updated in
                                    if let i = vm.ingredients.firstIndex(where: { $0.id == updated.id }) {
                                        vm.ingredients[i] = updated
                                    }
                                }
                            )
                        }, id: \.id) { $ing in
                            IngredientEditorRow(ing: $ing, totalKg: vm.totalKg, solved: true)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        nutrientIngredient = library.first { $0.code == ing.code }
                                    } label: {
                                        Label("Besin Değerleri", systemImage: "chart.bar.doc.horizontal")
                                    }
                                    .tint(.indigo)
                                }
                        }
                        .onDelete { indexSet in
                            let ids = unusedIngs.map { $0.id }
                            let toRemove = indexSet.map { ids[$0] }
                            vm.ingredients.removeAll { toRemove.contains($0.id) }
                        }
                    } header: {
                        Text("Kullanılmayanlar (\(unusedIngs.count))")
                    }
                }
            } else {
                Section {
                    ForEach($vm.ingredients) { $ing in
                        IngredientEditorRow(ing: $ing, totalKg: vm.totalKg,
                                            solved: vm.lastSolve != nil)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    nutrientIngredient = library.first { $0.code == ing.code }
                                } label: {
                                    Label("Besin Değerleri", systemImage: "chart.bar.doc.horizontal")
                                }
                                .tint(.indigo)
                            }
                    }
                    .onDelete { indexSet in
                        vm.ingredients.remove(atOffsets: indexSet)
                    }
                } header: {
                    HStack {
                        Text("Hammaddeler (\(vm.ingredients.count))")
                        Spacer()
                        Button { vm.showTemplatePicker = true } label: {
                            Label("Şablon", systemImage: "doc.badge.gearshape")
                                .font(.caption)
                        }
                        .foregroundStyle(.purple)
                        Button { vm.showIngredientPicker = true } label: {
                            Label("Ekle", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        Button { vm.showTxtImport = true } label: {
                            Label("TXT", systemImage: "doc.badge.plus")
                                .font(.caption)
                        }
                    }
                }
            }   // end else
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Besin Maddeleri tab

    private var constraintsTab: some View {
        List {
            Section {
                ForEach($vm.constraints) { $con in
                    ConstraintEditorRow(con: $con, onBreakdown: con.currentValue != nil ? {
                        breakdownTarget = BreakdownTarget(
                            nutrientKey:  con.nutrientKey,
                            displayName:  con.resolvedDisplayName,
                            unit:         con.unit,
                            ingredients:  vm.ingredients,
                            library:      library
                        )
                    } : nil)
                }
                .onDelete { indexSet in
                    vm.constraints.remove(atOffsets: indexSet)
                }
            } header: {
                HStack {
                    Text("Besin Kısıtları (\(vm.constraints.count))")
                    Spacer()
                    Button { vm.showConstraintPicker = true } label: {
                        Label("Ekle", systemImage: "plus.circle").font(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Sonuç tab

    private var resultTab: some View {
        List {
            if let s = vm.lastSolve {

                // ── Özet ──────────────────────────────────────────────────────
                Section {
                    resultRow("Durum",
                              value: s.isFeasible ? "Uygun Çözüm" : "Çözüm Yok",
                              color: s.isFeasible ? .green : .red)
                    resultRow("Maliyet",
                              value: String(format: "%.0f ₺/ton", s.costPerTon),
                              color: .orange)
                    if let prev = vm.previousCostPerTon, s.isFeasible {
                        let diff = s.costPerTon - prev
                        let sign = diff >= 0 ? "+" : ""
                        HStack {
                            Text("Önceki Maliyet").foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.0f ₺/ton", prev))
                                    .fontWeight(.semibold).foregroundStyle(.secondary)
                                Text(String(format: "%@%.0f ₺/ton", sign, diff))
                                    .font(.caption)
                                    .foregroundStyle(diff > 0 ? .red : diff < 0 ? .green : .secondary)
                            }
                        }
                    }
                    resultRow("Parti",
                              value: String(format: "%.2f kg", vm.totalKg),
                              color: .primary)
                    resultRow("Çözüm Tarihi", value: s.solvedAt.trClock, color: .secondary)
                    // Show every line of the solver message
                    ForEach(s.message.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Özet") }

                // ── Karışım Oranları ──────────────────────────────────────────
                let mixed = vm.ingredients.filter { $0.mixPct > 0.01 }.sorted { $0.mixPct > $1.mixPct }
                if !mixed.isEmpty {
                    Section {
                        ForEach(mixed) { ing in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ing.name).font(.subheadline).fontWeight(.medium)
                                    Text(ing.code).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "%.2f%%", ing.mixPct))
                                        .font(.subheadline.bold()).foregroundColor(.accentColor)
                                    Text((ing.mixPct / 100 * vm.totalKg).kgString)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text("Karışım Oranları") }
                }

                // ── Besin Değerleri ───────────────────────────────────────────
                // showInResult=true → visible rows; false → shown collapsed at bottom
                let visible  = vm.constraints.filter { $0.currentValue != nil && $0.showInResult }
                let hidden   = vm.constraints.filter { $0.currentValue != nil && !$0.showInResult }
                let noData   = vm.constraints.filter { $0.currentValue == nil }

                if !visible.isEmpty || !hidden.isEmpty {
                    Section {
                        ForEach(visible) { con in
                            NutrientResultRow(con: con, onBreakdown: {
                                breakdownTarget = BreakdownTarget(
                                    nutrientKey:  con.nutrientKey,
                                    displayName:  con.resolvedDisplayName,
                                    unit:         con.unit,
                                    ingredients:  vm.ingredients,
                                    library:      library
                                )
                            })
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        if let i = vm.constraints.firstIndex(where: { $0.id == con.id }) {
                                            vm.constraints[i].showInResult = false
                                        }
                                    } label: { Label("Gizle", systemImage: "eye.slash") }
                                    .tint(.gray)
                                }
                        }
                        // Collapsed hidden rows — tap to re-show
                        if !hidden.isEmpty {
                            HStack {
                                Image(systemName: "eye.slash").foregroundStyle(.secondary).font(.caption)
                                Text("\(hidden.count) kriter gizlendi")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Tümünü Göster") {
                                    for i in 0..<vm.constraints.count {
                                        vm.constraints[i].showInResult = true
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Besin Değerleri (\(visible.count))")
                            Spacer()
                            let violated = visible.filter { !isConstraintMet($0) }.count
                            if violated > 0 {
                                Text("\(violated) kısıt dışı").font(.caption).foregroundStyle(.red)
                            } else if !visible.isEmpty {
                                Text("Tümü ✓").font(.caption).foregroundStyle(.green)
                            }
                        }
                    }
                }

                if !noData.isEmpty {
                    Section {
                        ForEach(noData) { con in
                            HStack {
                                Text(con.resolvedDisplayName).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("— veri yok").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    } header: { Text("Kütüphane Verisi Olmayan Kriterler") }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func isConstraintMet(_ con: BFConstraint) -> Bool {
        guard let cur = con.currentValue else { return true }
        if let mn = con.minValue, cur < mn - 1e-4 { return false }
        if let mx = con.maxValue, cur > mx + 1e-4 { return false }
        return true
    }

    private func resultRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if formula == nil {
                Button("Vazgeç") { dismiss() }
            } else if showCloseButton {
                Button("Kapat") { dismiss() }
            }
        }

        // İkincil aksiyonlar — gerçek bir Menu (her zaman açılır, taşma sorunu olmaz)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                // PDF / TXT / Excel export — only for saved formulas
                if formula != nil, !vm.code.isEmpty {
                    Button {
                        saveAction()
                        showFormulaExport = true
                    } label: {
                        Label("Rapor / Dışa Aktar", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        saveAction()           // ensure latest changes are saved first
                        showMultiBlendExport = true
                    } label: {
                        Label("MultiBlend'e Aktar", systemImage: "rectangle.3.group.fill")
                    }
                }

                Button { vm.showCombinations = true } label: {
                    Label("Kombinasyonlar", systemImage: "square.grid.3x3.topleft.filled")
                }
                .disabled(vm.ingredients.isEmpty)

                Button { showAssistant = true } label: {
                    Label("AI Rasyon Asistanı", systemImage: "sparkles")
                }
                .disabled(vm.ingredients.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        // Çöz — birincil aksiyon
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await solveAction() }
            } label: {
                if vm.isSolving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Label("Çöz", systemImage: "cpu")
                        .labelStyle(.titleAndIcon)
                }
            }
            .disabled(vm.isSolving || vm.ingredients.filter(\.isActive).isEmpty)
            .tint(.green)
        }

        // Kaydet — birincil aksiyon
        ToolbarItem(placement: .primaryAction) {
            Button("Kaydet") { saveAction() }
                .fontWeight(.semibold)
        }
    }

    // MARK: - Actions

    private func saveAction() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        guard vm.validate() else { return }
        if let f = formula {
            vm.applyToFormula(f)
        } else {
            let f = BlendFormula(code: vm.code, name: vm.name, totalKg: vm.totalKg)
            vm.applyToFormula(f)
            modelContext.insert(f)
        }
        // Formülde fiyat girilmişse kütüphaneye de yansıt
        syncOverridePricesToLibrary()
        try? modelContext.save()
        if formula == nil { dismiss() }
    }

    // Formüldeki override fiyatları → library FeedIngredient.priceTL
    private func syncOverridePricesToLibrary() {
        for ing in vm.ingredients {
            guard let overridePrice = ing.overridePriceTLPerTon, overridePrice > 0 else { continue }
            guard let lib = IngredientMatcher.find(code: ing.code, name: ing.name, in: library) else { continue }
            if lib.priceTL != overridePrice {
                lib.priceTL = overridePrice
                modelContext.insert(PriceHistoryEntry(ingredientName: lib.name, priceTL: overridePrice))
            }
        }
    }

    @MainActor
    private func solveAction(autoRelaxStep2: Bool = false) async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        await Task.yield()   // let UI update (dismiss keyboard) before starting

        // ── Value-type snapshots (Sendable across actor boundaries) ─────────
        struct SolveIn: @unchecked Sendable {
            let ings:       [BFIngredient]
            let cons:       [BFConstraint]
            let combos:     [BFCombination]
            let totalKgStr: String
            let lastSolve:  BFSolveResult?   // needed to preserve previousCostPerTon
        }
        struct SolveOut: @unchecked Sendable {
            let ings:               [BFIngredient]
            let cons:               [BFConstraint]
            let lastSolve:          BFSolveResult?
            let message:            String?
            let prevCost:           Double?
            let step1Warnings:      [String]
            let pendingStep2Choice: Step2Info?
            let shortfallReports:   [ConstraintShortfallReport]
        }

        // Kullanıcının yazdığı fiyatları kütüphaneye aktar — libSnap'ten ÖNCE
        syncOverridePricesToLibrary()

        let input = SolveIn(
            ings:       vm.ingredients,
            cons:       vm.constraints,
            combos:     vm.combinations,
            totalKgStr: vm.totalKgStr,
            lastSolve:  vm.lastSolve
        )
        let libSnap = library.map { IngSnap.from($0) }

        vm.isSolving = true

        // ── LP hesabı arka planda ────────────────────────────────────────────
        let out: SolveOut = await Task.detached(priority: .userInitiated) {
            let solver          = FormulaEditorVM()
            solver.ingredients  = input.ings
            solver.constraints  = input.cons
            solver.combinations = input.combos
            solver.totalKgStr   = input.totalKgStr
            solver.lastSolve    = input.lastSolve   // lets solve() compute previousCostPerTon
            solver.loadPricesFromLibrary(libSnap)
            solver.solve(library: libSnap, autoRelaxStep2: autoRelaxStep2)
            return SolveOut(
                ings:               solver.ingredients,
                cons:               solver.constraints,
                lastSolve:          solver.lastSolve,
                message:            solver.solveMessage,
                prevCost:           solver.previousCostPerTon,
                step1Warnings:      solver.step1Warnings,
                pendingStep2Choice: solver.pendingStep2Choice,
                shortfallReports:   solver.shortfallReports
            )
        }.value

        // ── Sonuçları main thread'de VM'ye yaz ──────────────────────────────
        vm.ingredients         = out.ings
        vm.constraints         = out.cons
        vm.lastSolve           = out.lastSolve
        vm.solveMessage        = out.message
        vm.previousCostPerTon  = out.prevCost
        vm.step1Warnings       = out.step1Warnings
        vm.pendingStep2Choice  = out.pendingStep2Choice
        vm.shortfallReports    = out.shortfallReports
        vm.isSolving           = false
        if out.pendingStep2Choice == nil { vm.selectedTab = 2 }

        // ── LP sonuçlarını hemen SwiftData'ya kaydet ─────────────────────
        // Kullanıcı "Kaydet" basmadan gönderim yapsa bile sunucu çözüm
        // değerlerini (mixPct toplamı = %100) görsün. Step2 bekliyorsa kaydetme —
        // henüz geçerli bir çözüm yok.
        if out.pendingStep2Choice == nil, let f = formula {
            vm.applyToFormula(f)
            try? modelContext.save()
        }
    }

    // MARK: - TXT import

    private func handleTxtImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        // Try Alapala YEM format first
        if AlapalaFormulaParser.isAlapalaFormat(url: url) {
            do {
                let parsed = try AlapalaFormulaParser.parse(url: url)
                applyAlapalaResult(parsed)
            } catch {
                vm.solveMessage = "Hata: \(error.localizedDescription)"
            }
            return
        }

        // Fallback: simple CSV  CODE;NAME;MIN%;MAX%
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        parseSimpleCsv(text)
    }

    private func applyAlapalaResult(_ parsed: AlapalaFormulaParser.ParseResult) {
        // Always take code/name from file — user explicitly chose this file
        if !parsed.formulaCode.isEmpty { vm.code = parsed.formulaCode }
        if !parsed.formulaName.isEmpty { vm.name = parsed.formulaName }
        if parsed.totalKg > 0 { vm.totalKgStr = String(format: "%.0f", parsed.totalKg) }

        var addedIngs = 0
        for ing in parsed.ingredients {
            guard !vm.ingredients.contains(where: { $0.code == ing.code && $0.name == ing.name }) else { continue }
            vm.ingredients.append(ing)
            addedIngs += 1
        }

        var addedCons = 0
        var updatedCons = 0
        for con in parsed.constraints {
            if let i = vm.constraints.firstIndex(where: { $0.nutrientKey == con.nutrientKey }) {
                // Kısıt zaten var: TXT'deki currentValue ile güncelle (min/max'a dokunma)
                if let v = con.currentValue {
                    vm.constraints[i].currentValue = v
                    updatedCons += 1
                }
            } else {
                vm.constraints.append(con)
                addedCons += 1
            }
        }

        vm.solveMessage = "\(addedIngs) hammadde, \(addedCons) kısıt eklendi\(updatedCons > 0 ? ", \(updatedCons) kısıt güncellendi" : "")."
    }

    private func parseSimpleCsv(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        var added = 0
        for line in lines {
            let parts = line.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, !parts[1].isEmpty else { continue }
            let code   = parts[0]
            let name   = parts[1]
            let minPct = parts.count > 2 ? Double(parts[2]) ?? 0   : 0
            let maxPct = parts.count > 3 ? Double(parts[3]) ?? 100 : 100
            guard !vm.ingredients.contains(where: { $0.code == code && $0.name == name }) else { continue }
            vm.ingredients.append(BFIngredient(code: code, name: name, minPct: minPct, maxPct: maxPct))
            added += 1
        }
        vm.solveMessage = "\(added) hammadde eklendi."
    }
}

// MARK: - Nutrient result row

private struct NutrientResultRow: View {
    let con: BFConstraint
    var onBreakdown: (() -> Void)? = nil
    private var cur: Double { con.currentValue ?? 0 }

    private enum Status { case ok, belowMin(Double), aboveMax(Double) }
    private var status: Status {
        if let mn = con.minValue, cur < mn - 1e-4 { return .belowMin(mn) }
        if let mx = con.maxValue, cur > mx + 1e-4 { return .aboveMax(mx) }
        return .ok
    }
    private var fmt: String { "%.2f" }
    private var isOk: Bool { if case .ok = status { return true }; return false }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOk ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(isOk ? Color.green : Color.red)

            Text(con.resolvedDisplayName)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 3) {
                    Text(String(format: fmt, cur))
                        .font(.subheadline.bold())
                        .foregroundColor(isOk ? .primary : .red)
                    if !con.unit.isEmpty {
                        Text(con.unit).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                switch status {
                case .belowMin(let mn):
                    Text(String(format: "min: \(fmt)", mn)).font(.caption2).foregroundStyle(.orange)
                case .aboveMax(let mx):
                    Text(String(format: "max: \(fmt)", mx)).font(.caption2).foregroundStyle(.orange)
                case .ok:
                    let parts = [
                        con.minValue.map { String(format: "≥\(fmt)", $0) },
                        con.maxValue.map { String(format: "≤\(fmt)", $0) }
                    ].compactMap { $0 }
                    if !parts.isEmpty {
                        Text(parts.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            if let action = onBreakdown {
                Button(action: action) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.blue.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Ingredient editor row

private struct IngredientEditorRow: View {
    @Binding var ing:     BFIngredient
    let totalKg:          Double
    let solved:           Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Active toggle
                Toggle("", isOn: $ing.isActive)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ing.name).font(.subheadline).fontWeight(.medium)
                        .strikethrough(!ing.isActive, color: .secondary)
                    Text(ing.code).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                // Solved percentage + delta gösterimi
                if solved {
                    if ing.mixPct > 0.001 {
                        // ── Şu an rasyonda ──────────────────────────────────
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.2f%%", ing.mixPct))
                                .font(.subheadline.bold()).foregroundColor(.accentColor)
                            let kg = ing.mixPct / 100.0 * totalKg
                            Text(kg.kgString)
                                .font(.caption2).foregroundStyle(.secondary)
                            // Delta: önceki çözümle karşılaştır
                            if ing.previousMixPct > 0.001 {
                                // Önceden de rasyondaydı — değişim göster
                                let diff   = ing.mixPct - ing.previousMixPct
                                let diffKg = diff / 100.0 * totalKg
                                if abs(diff) > 0.01 {
                                    HStack(spacing: 2) {
                                        Image(systemName: diff > 0
                                              ? "arrow.up.circle.fill"
                                              : "arrow.down.circle.fill")
                                            .font(.system(size: 9, weight: .bold))
                                        VStack(alignment: .trailing, spacing: 0) {
                                            Text(String(format: "%+.0f kg", diffKg))
                                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                            Text(String(format: "%+.2f%%", diff))
                                                .font(.system(size: 9).monospacedDigit())
                                        }
                                    }
                                    .foregroundStyle(diff > 0 ? .green : .red)
                                }
                            } else {
                                // Önceki çözümde yoktu — yeni giriyor
                                HStack(spacing: 2) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text(String(format: "+%.0f kg", kg))
                                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                                        Text("Yeni")
                                            .font(.system(size: 9))
                                    }
                                }
                                .foregroundStyle(.green)
                            }
                        }
                    } else if ing.previousMixPct > 0.001 {
                        // ── Rasyondan çıktı ─────────────────────────────────
                        let prevKg = ing.previousMixPct / 100.0 * totalKg
                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: "minus.circle.fill")
                                .font(.caption).foregroundStyle(.red)
                            Text(String(format: "−%.0f kg", prevKg))
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(.red)
                            Text(String(format: "(−%.2f%%)", ing.previousMixPct))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.red.opacity(0.8))
                            Text("çıktı").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                // Stock toggle
                VStack(spacing: 1) {
                    Image(systemName: ing.hasStock ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(ing.hasStock ? .green : .red)
                        .onTapGesture { ing.hasStock.toggle() }
                    Text("Stok").font(.caption2).foregroundStyle(.secondary)
                }
            }

            // Min / Max / Price row
            HStack(spacing: 12) {
                CompactDoubleField(label: "Min%", value: $ing.minPct)
                CompactDoubleField(label: "Max%", value: $ing.maxPct)
                Spacer()
                overridePriceField
            }
        }
        .padding(.vertical, 2)
        .opacity(ing.isActive ? 1 : 0.5)
    }


    private var overridePriceField: some View {
        HStack(spacing: 3) {
            Text("₺/ton").font(.caption2).foregroundStyle(.secondary)
            let binding = Binding<String>(
                get: { ing.overridePriceTLPerTon.map { String(format: "%.0f", $0) } ?? "" },
                set: { ing.overridePriceTLPerTon = Double($0) }
            )
            TextField("Kütüph.", text: binding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 50, maxWidth: 80)
                .font(.caption.bold())
        }
    }
}

// MARK: - Compact double field (local @State avoids per-render Binding churn)

private struct CompactDoubleField: View {
    let label: String
    @Binding var value: Double

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    private var isMin: Bool { label.lowercased().contains("min") }
    private var accentColor: Color { isMin ? .blue : .orange }

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(accentColor)
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(minWidth: 44, maxWidth: 68)
                .font(.caption.bold().monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(accentColor.opacity(0.45), lineWidth: 1)
                )
                .focused($isFocused)
                .onChange(of: isFocused) { _, nowFocused in
                    if !nowFocused { commit() }
                }
        }
        .onAppear { load() }
        .onChange(of: value) { _, _ in
            if !isFocused { load() }
        }
    }

    private func load() {
        text = String(format: "%.2f", value)
    }

    private func commit() {
        let clean = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(clean) { value = v }
        else { load() }
    }
}

// MARK: - Constraint editor row

private struct ConstraintEditorRow: View {
    @Binding var con: BFConstraint
    var onBreakdown: (() -> Void)? = nil

    private var statusColor: Color {
        guard let cur = con.currentValue else { return .secondary }
        if let mn = con.minValue, cur < mn - 1e-4 { return .red }
        if let mx = con.maxValue, cur > mx + 1e-4 { return .red }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: $con.isActive).labelsHidden().toggleStyle(.switch).scaleEffect(0.8)
                Text(con.resolvedDisplayName).font(.subheadline).fontWeight(.medium)
                Text("(\(con.unit))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let cur = con.currentValue {
                    HStack(spacing: 6) {
                        Text(String(format: "%.2f", cur))
                            .font(.subheadline.bold()).foregroundStyle(statusColor)
                        if let action = onBreakdown {
                            Button(action: action) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                ConstraintOptionalField(label: "Min", value: $con.minValue)
                ConstraintOptionalField(label: "Max", value: $con.maxValue)
                Spacer()
            }
        }
        .padding(.vertical, 2)
        .opacity(con.isActive ? 1 : 0.5)
    }
}

// MARK: - Constraint optional field (kutu stilinde, nil destekli)

private struct ConstraintOptionalField: View {
    let label:       String
    @Binding var value: Double?

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    private var isMin: Bool { label.lowercased() == "min" }
    private var accentColor: Color { isMin ? .blue : .orange }

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(accentColor)
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(minWidth: 48, maxWidth: 72)
                .font(.caption.bold().monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(accentColor.opacity(0.45), lineWidth: 1)
                )
                .focused($isFocused)
                .onChange(of: isFocused) { _, nowFocused in
                    if !nowFocused { commit() }
                }
        }
        .onAppear { load() }
        .onChange(of: value) { _, _ in
            if !isFocused { load() }
        }
    }

    private func load() {
        guard let v = value else { text = ""; return }
        text = v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.4g", v)
    }

    private func commit() {
        let clean = text.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: ",", with: ".")
        if clean.isEmpty {
            value = nil
        } else if let v = Double(clean) {
            value = v
        } else {
            load()
        }
    }
}

// MARK: - Ingredient picker sheet

private struct IngredientPickerSheet: View {
    @Bindable var vm:     FormulaEditorVM
    let library:          [FeedIngredient]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [FeedIngredient] {
        guard !search.isEmpty else { return library }
        return library.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { ing in
                let already = vm.ingredients.contains { $0.code == ing.code && $0.name == ing.name }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ing.name).font(.subheadline)
                        Text(ing.code).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if already {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Ekle") {
                            var newIng = BFIngredient(code: ing.code, name: ing.name)
                            if let p = ing.priceTL, p > 0 { newIng.overridePriceTLPerTon = p }
                            vm.ingredients.append(newIng)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: "Hammadde ara…")
            .navigationTitle("Hammadde Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Constraint picker sheet

private struct ConstraintPickerSheet: View {
    @Bindable var vm: FormulaEditorVM
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [NutrientDef] {
        guard !search.isEmpty else { return allNutrientDefs }
        return allNutrientDefs.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) ||
            $0.key.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { def in
                let already = vm.constraints.contains { $0.nutrientKey == def.key }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.displayName).font(.subheadline)
                        Text(def.unit).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if already {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Ekle") {
                            vm.constraints.append(BFConstraint(
                                nutrientKey:  def.key,
                                displayName:  def.displayName,
                                unit:         def.unit
                            ))
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: "Besin maddesi ara…")
            .navigationTitle("Kısıt Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Besin katkı analizi — veri taşıyıcı

struct BreakdownTarget: Identifiable {
    var id: String { nutrientKey }
    let nutrientKey:  String
    let displayName:  String
    let unit:         String
    let ingredients:  [BFIngredient]
    let library:      [FeedIngredient]
}

// MARK: - Besin katkı analizi — sayfa

struct NutrientBreakdownSheet: View {
    let target: BreakdownTarget
    @Environment(\.dismiss) private var dismiss

    private struct ContribItem: Identifiable {
        let id   = UUID()
        let name:           String
        let code:           String
        let mixPct:         Double
        let nutrientPer100: Double
        let contribution:   Double
    }

    private var items: [ContribItem] {
        target.ingredients
            .filter { $0.isActive && $0.mixPct > 0.001 }
            .compactMap { ing -> ContribItem? in
                let lib = IngredientMatcher.find(code: ing.code, name: ing.name, in: target.library)
                guard let v = lib?.nutrientValue(forKey: target.nutrientKey), v > 0 else { return nil }
                return ContribItem(
                    name:           ing.name,
                    code:           ing.code,
                    mixPct:         ing.mixPct,
                    nutrientPer100: v,
                    contribution:   ing.mixPct / 100.0 * v
                )
            }
            .sorted { $0.contribution > $1.contribution }
    }

    private var totalContrib: Double { items.reduce(0) { $0 + $1.contribution } }

    private let barColors: [Color] = [.orange, .blue, .green, .purple, .red, .teal, .indigo, .mint]

    var body: some View {
        NavigationStack {
            List {
                // Özet
                Section {
                    HStack {
                        Label("Toplam \(target.displayName)", systemImage: "sum")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f %@", totalContrib, target.unit))
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                    Text("Her hammaddenin karışımdaki payı × kütüphanedeki besin değeri")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                // Hammadde katkıları
                Section {
                    if items.isEmpty {
                        Text("Kütüphanede bu besin için veri bulunamadı.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            let share = totalContrib > 0 ? item.contribution / totalContrib : 0
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Text("\(idx + 1)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 18, alignment: .trailing)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.name).font(.subheadline)
                                            Text("[\(item.code)]")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(String(format: "%.2f %@", item.contribution, target.unit))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.orange)
                                        Text(String(format: "%%%.1f", share * 100))
                                            .font(.caption2.bold())
                                            .foregroundStyle(.blue)
                                    }
                                }
                                // Formül açıklaması
                                Text(String(format: "%.2f%% × %.3f = %.2f %@",
                                            item.mixPct, item.nutrientPer100,
                                            item.contribution, target.unit))
                                    .font(.caption2).foregroundStyle(.tertiary)
                                // İlerleme çubuğu — scaleEffect ile GeometryReader layout pass yok
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(.systemFill))
                                    Capsule()
                                        .fill(barColors[idx % barColors.count])
                                        .scaleEffect(x: max(share, 0.005), anchor: .leading)
                                }
                                .frame(height: 5)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text("Hammadde Katkıları (\(items.count) kalem)")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(target.displayName) Analizi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}
