import SwiftUI
import SwiftData

// MARK: - Gönderim hedefi (BORN sunucusu / Bulut ERP / ikisi de)

enum SendTarget: String, CaseIterable, Identifiable, Sendable {
    case born  = "BORN Sunucu"
    case bulut = "Bulut ERP"
    case both  = "İkisi de"

    var id: String { rawValue }
    var sendsToBorn:  Bool { self != .bulut }
    var sendsToBulut: Bool { self != .born }
}

// MARK: - Single formula send sheet

struct SendFormulaSheet: View {
    let formula: BlendFormula

    @Environment(\.dismiss)       private var dismiss
    @Environment(\.modelContext)  private var modelContext
    @Query private var library: [FeedIngredient]

    @State private var customName:    String = ""
    @State private var customVersion: String = ""
    @State private var validDate:     Date   = Date()
    @State private var comment:       String = ""
    @State private var activate:      Bool   = true
    @State private var target:        SendTarget = .both
    @State private var isSending:     Bool   = false
    @State private var sendResult:    SendOutcome?
    @State private var erpResult:     SendOutcome?

    private var activeIngredients: [BFIngredient] {
        formula.ingredients.filter { $0.isActive && $0.mixPct > 0 }
    }

    private var hasSolve: Bool { formula.lastSolve?.isFeasible == true }

    var body: some View {
        NavigationStack {
            Form {
                formulaInfoSection
                sendParamsSection
                ingredientPreviewSection
                if let r = sendResult { resultSection(r, title: "BORN Sunucu") }
                if let e = erpResult  { resultSection(e, title: "Bulut ERP") }
            }
            .navigationTitle("Sunucuya Gönder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Gönder") { Task { await send() } }
                            .fontWeight(.semibold)
                            .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty
                                      || activeIngredients.isEmpty
                                      || (target.sendsToBulut
                                          && customVersion.trimmingCharacters(in: .whitespaces).isEmpty))
                    }
                }
            }
            .onAppear { customName = formula.name }
        }
    }

    // MARK: - Sections

    private var formulaInfoSection: some View {
        Section("Formül Bilgisi") {
            LabeledContent("Ürün Kodu", value: formula.code)
            LabeledContent("Ürün Adı",  value: formula.name)
            LabeledContent("Parti",      value: String(format: "%.0f kg", formula.totalKg))
            if !hasSolve {
                Label("Formül henüz çözülmemiş — önce Hesapla'yı çalıştırın.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sendParamsSection: some View {
        Section("Gönderim Parametreleri") {
            HStack {
                Text("Rasyon Adı")
                Spacer()
                TextField("Örn: rasyon07052026", text: $customName)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Versiyon")
                Spacer()
                TextField("Dosya adı (Opsiyonel)", text: $customVersion)
                    .multilineTextAlignment(.trailing)
            }
            DatePicker("Geçerlilik Tarihi",
                       selection: $validDate,
                       displayedComponents: .date)
            HStack {
                Text("Not")
                Spacer()
                TextField("Opsiyonel", text: $comment)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Aktif Olarak Gönder", isOn: $activate)
            Picker("Gönderim Hedefi", selection: $target) {
                ForEach(SendTarget.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var ingredientPreviewSection: some View {
        Section("İçerik (\(activeIngredients.count) hammadde)") {
            if activeIngredients.isEmpty {
                Text("Gönderilebilecek aktif hammadde yok.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(activeIngredients.enumerated()), id: \.offset) { _, ing in
                    let kg = ing.mixPct / 100.0 * formula.totalKg
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ing.name).font(.subheadline)
                            Text("[\(ing.code)]").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.2f kg", kg))
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ r: SendOutcome, title: String) -> some View {
        Section(title) {
            switch r {
            case .success(let msg):
                Label(msg, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Send

    private func send() async {
        isSending  = true
        sendResult = nil
        erpResult  = nil

        let model      = buildModel()
        let erpPayload = target.sendsToBulut ? buildErpPayload(details: model.details) : nil

        async let bornOutcome: SendOutcome? = attemptBorn(model: model)
        async let erpOutcome:  SendOutcome? = attemptErp(payload: erpPayload)
        let (born, erp) = await (bornOutcome, erpOutcome)

        sendResult = born
        erpResult  = erp
        saveRecord(bornSuccess: born?.isSuccess ?? true, bornMessage: born?.message ?? "",
                   erpSuccess:  erp?.isSuccess  ?? true, erpMessage:  erp?.message  ?? "")

        isSending = false
    }

    private func attemptBorn(model: FormulaCreateAppModel) async -> SendOutcome? {
        guard target.sendsToBorn else { return nil }
        do {
            let resp = try await CreateFormulaService().create(model: model)
            return .success(resp.message ?? "Formül başarıyla gönderildi.")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func attemptErp(payload: BulutErpRasyonPayload?) async -> SendOutcome? {
        guard let payload else { return nil }
        do {
            let resp = try await BulutErpService().send(payload: payload)
            return .success(resp.message.isEmpty ? "Bulut ERP'ye gönderildi." : resp.message)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func buildErpPayload(details: [FormulaCreateDetailAppModel]) -> BulutErpRasyonPayload {
        let costByCode: [String: Double] = Dictionary(
            activeIngredients.map { ing -> (String, Double) in
                let lib      = IngredientMatcher.find(code: ing.code, name: ing.name, in: library)
                let rawPrice = ing.overridePriceTLPerTon ?? lib?.priceTL ?? 0
                return (ing.code, rawPrice / 1000.0)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let items = details.map {
            BulutErpRasyonPayload.Item(code: $0.materialCode, name: $0.materialName,
                                        costPerKg: costByCode[$0.materialCode] ?? 0,
                                        amountKg: $0.amount)
        }
        let costPerTon = formula.lastSolve?.costPerTon ?? formula.currentCostTL

        return BulutErpRasyonPayload(
            rasyonNo:         customVersion.trimmingCharacters(in: .whitespaces),
            rasyonTarih:      Date(),
            productCode:      formula.code,
            productName:      formula.name,
            productCostPerKg: costPerTon / 1000.0,
            items:            items
        )
    }

    private func saveRecord(bornSuccess: Bool, bornMessage: String,
                            erpSuccess: Bool, erpMessage: String) {
        let snaps = activeIngredients.map {
            SentIngredientSnap(code: $0.code, name: $0.name,
                               amountKg: $0.mixPct / 100.0 * formula.totalKg,
                               mixPct: $0.mixPct)
        }
        let snapJSON = (try? String(data: JSONEncoder().encode(snaps), encoding: .utf8)) ?? "[]"
        let record = SendRecord(
            formulaCode:          formula.code,
            formulaName:          formula.name,
            customName:           customName.trimmingCharacters(in: .whitespaces),
            customVersion:        customVersion.trimmingCharacters(in: .whitespaces),
            source:               "SingleBlend",
            isSuccess:            bornSuccess,
            serverMessage:        bornMessage,
            ingredientCount:      activeIngredients.count,
            totalKg:              formula.totalKg,
            ingredientsSnapshot:  snapJSON,
            costPerTon:           formula.lastSolve?.costPerTon ?? formula.currentCostTL,
            nutrientsSnapshot:    SendRecord.buildNutrientSnaps(from: formula),
            erpRasyonNo:          target.sendsToBulut ? customVersion.trimmingCharacters(in: .whitespaces) : "",
            erpIsSuccess:         erpSuccess,
            erpMessage:           erpMessage
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func buildModel() -> FormulaCreateAppModel {
        let totalPct   = activeIngredients.reduce(0) { $0 + $1.mixPct }
        let normFactor = totalPct > 0 ? 100.0 / totalPct : 1.0
        let details: [FormulaCreateDetailAppModel] = activeIngredients
            .sorted { $0.mixPct > $1.mixPct }
            .enumerated()
            .map { i, ing in
                FormulaCreateDetailAppModel(
                    materialCode: ing.code,
                    materialName: ing.name,
                    rowNo:        i + 1,
                    amount:       (ing.mixPct * normFactor) / 100.0 * 1000.0,
                    isAdditive:   false
                )
            }

        return FormulaCreateAppModel(
            productCode:   formula.code,
            productName:   formula.name,
            customName:    customName.trimmingCharacters(in: .whitespaces),
            customVersion: customVersion.trimmingCharacters(in: .whitespaces),
            validDate:     validDate,
            totalAmount:   1000.0,
            comment:       comment.trimmingCharacters(in: .whitespaces),
            details:       details,
            activate:      activate
        )
    }
}

// MARK: - Multi-formula (MultiBlend) batch send sheet

struct MultiBlendSendSheet: View {
    let formulas: [BlendFormula]
    var source:   String = "MultiBlend"   // kayıt için: "MultiBlend" veya "SingleBlend"

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var library: [FeedIngredient]

    // Per-formula
    @State private var customNames: [String: String] = [:]
    @State private var selected:    Set<String>      = []
    @State private var searchText:  String           = ""

    // Shared
    @State private var validDate:      Date   = Date()
    @State private var customVersion:  String = ""
    @State private var comment:        String = ""
    @State private var activate:       Bool   = true
    @State private var target:         SendTarget = .both

    // Send state
    @State private var isSending:        Bool                   = false
    @State private var sendProgress:     Double                 = 0
    @State private var sendResults:      [String: DualOutcome]  = [:]
    @State private var currentlySending: String?                = nil

    private var selectedFormulas: [BlendFormula] {
        formulas.filter { selected.contains($0.code) }
    }

    private var filteredFormulas: [BlendFormula] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return formulas }
        return formulas.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                sharedParamsSection
                selectionHeaderSection
                formulaRowsSection
            }
            .searchable(text: $searchText, prompt: "Formül adı veya kodu ara")
            .navigationTitle("Toplu Gönderim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                            Text("\(Int(sendProgress * 100))%")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } else {
                        Button("Gönder (\(selected.count))") {
                            Task { await sendAll() }
                        }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty
                                  || (target.sendsToBulut
                                      && customVersion.trimmingCharacters(in: .whitespaces).isEmpty))
                    }
                }
            }
            .onAppear {
                selected = Set(formulas.map(\.code))
                for f in formulas { customNames[f.code] = f.name }
            }
        }
    }

    // MARK: - Sections

    private var sharedParamsSection: some View {
        Section("Ortak Parametreler") {
            DatePicker("Geçerlilik Tarihi",
                       selection: $validDate,
                       displayedComponents: .date)
            HStack {
                Text("Versiyon")
                Spacer()
                TextField("Dosya adı (Opsiyonel)", text: $customVersion)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Not")
                Spacer()
                TextField("Opsiyonel", text: $comment)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Aktif Olarak Gönder", isOn: $activate)
            Picker("Gönderim Hedefi", selection: $target) {
                ForEach(SendTarget.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var selectionHeaderSection: some View {
        Section {
            HStack {
                Button("Tümünü Seç") {
                    selected = Set(formulas.map(\.code))
                }
                .disabled(selected.count == formulas.count)
                Spacer()
                Button("Seçimi Temizle") { selected = [] }
                    .disabled(selected.isEmpty)
            }
            .font(.caption)
        } header: {
            Text("Formüller (\(selected.count)/\(formulas.count) seçili)")
        }
    }

    @ViewBuilder
    private var formulaRowsSection: some View {
        ForEach(filteredFormulas) { formula in
            let isSelected = selected.contains(formula.code)
            let result     = sendResults[formula.code]
            let isCurrent  = currentlySending == formula.code
            let hasSolve   = formula.lastSolve?.isFeasible == true

            Section {
                // Checkbox row
                Button {
                    if isSelected { selected.remove(formula.code) }
                    else          { selected.insert(formula.code) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .blue : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formula.name).font(.subheadline.bold()).foregroundStyle(.primary)
                            Text(formula.code).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isCurrent {
                            ProgressView().scaleEffect(0.85)
                        } else if let res = result {
                            Image(systemName: res.isOverallSuccess
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(res.isOverallSuccess ? .green : .red)
                        } else if !hasSolve {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending)

                // CustomName field (only when selected)
                if isSelected {
                    HStack {
                        Text("Rasyon Adı")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("Rasyon Adı", text: Binding(
                            get: { customNames[formula.code] ?? formula.name },
                            set: { customNames[formula.code] = $0 }
                        ))
                        .multilineTextAlignment(.trailing)
                        .font(.caption)
                    }
                }

                // Result feedback
                if let res = result {
                    if let born = res.born {
                        Text(born.message)
                            .font(.caption)
                            .foregroundStyle(born.isSuccess ? .green : .red)
                    }
                    if let erp = res.erp {
                        Text("Bulut ERP: \(erp.message)")
                            .font(.caption2)
                            .foregroundStyle(erp.isSuccess ? .green : .red)
                    }
                }
            }
        }
    }

    // MARK: - Send all

    private func sendAll() async {
        isSending     = true
        sendProgress  = 0
        sendResults   = [:]

        let svc         = CreateFormulaService()
        let trimComment = comment.trimmingCharacters(in: .whitespaces)
        let trimVersion = customVersion.trimmingCharacters(in: .whitespaces)
        let vDate       = validDate
        let act         = activate
        let tgt         = target

        // Snapshot all send data on @MainActor before background work
        // (FeedIngredient/library lookups must happen here — SwiftData @Model isn't Sendable)
        struct FormSnap: @unchecked Sendable {
            let code: String; let name: String; let totalKg: Double; let customName: String
            let costPerTon: Double
            let ings: [(code: String, name: String, mixPct: Double, costPerKg: Double)]
        }
        let snaps: [FormSnap] = selectedFormulas.map { f in
            let cName  = (customNames[f.code] ?? f.name).trimmingCharacters(in: .whitespaces)
            let active = f.ingredients.filter { $0.isActive && $0.mixPct > 0 }
            let ings = active.map { ing -> (code: String, name: String, mixPct: Double, costPerKg: Double) in
                let lib      = IngredientMatcher.find(code: ing.code, name: ing.name, in: library)
                let rawPrice = ing.overridePriceTLPerTon ?? lib?.priceTL ?? 0
                return (code: ing.code, name: ing.name, mixPct: ing.mixPct, costPerKg: rawPrice / 1000.0)
            }
            return FormSnap(
                code: f.code, name: f.name, totalKg: f.totalKg, customName: cName,
                costPerTon: f.lastSolve?.costPerTon ?? f.currentCostTL,
                ings: ings
            )
        }
        let total = snaps.count
        guard total > 0 else { isSending = false; return }

        currentlySending = "0/\(total)"

        var completed = 0
        await withTaskGroup(of: (code: String, outcome: DualOutcome, customName: String).self) { grp in
            for snap in snaps {
                grp.addTask {
                    let totalPct   = snap.ings.reduce(0) { $0 + $1.mixPct }
                    let normFactor = totalPct > 0 ? 100.0 / totalPct : 1.0
                    let details = snap.ings
                        .sorted { $0.mixPct > $1.mixPct }
                        .enumerated()
                        .map { i, ing in
                            FormulaCreateDetailAppModel(
                                materialCode: ing.code,
                                materialName: ing.name,
                                rowNo:        i + 1,
                                amount:       (ing.mixPct * normFactor) / 100.0 * 1000.0,
                                isAdditive:   false
                            )
                        }

                    var bornOutcome: SendOutcome?
                    if tgt.sendsToBorn {
                        let model = FormulaCreateAppModel(
                            productCode:   snap.code,
                            productName:   snap.name,
                            customName:    snap.customName,
                            customVersion: trimVersion,
                            validDate:     vDate,
                            totalAmount:   1000.0,
                            comment:       trimComment,
                            details:       details,
                            activate:      act
                        )
                        do {
                            let resp = try await svc.create(model: model)
                            bornOutcome = .success(resp.message ?? "✓ Gönderildi")
                        } catch {
                            bornOutcome = .failure("✗ \(String(error.localizedDescription.prefix(80)))")
                        }
                    }

                    var erpOutcome: SendOutcome?
                    if tgt.sendsToBulut {
                        let costByCode: [String: Double] = Dictionary(
                            snap.ings.map { ($0.code, $0.costPerKg) },
                            uniquingKeysWith: { first, _ in first }
                        )
                        let items = details.map {
                            BulutErpRasyonPayload.Item(code: $0.materialCode, name: $0.materialName,
                                                        costPerKg: costByCode[$0.materialCode] ?? 0,
                                                        amountKg: $0.amount)
                        }
                        let payload = BulutErpRasyonPayload(
                            rasyonNo:         trimVersion,
                            rasyonTarih:      Date(),
                            productCode:      snap.code,
                            productName:      snap.name,
                            productCostPerKg: snap.costPerTon / 1000.0,
                            items:            items
                        )
                        do {
                            let resp = try await BulutErpService().send(payload: payload)
                            erpOutcome = .success(resp.message.isEmpty ? "✓ ERP" : "✓ \(resp.message.prefix(80))")
                        } catch {
                            erpOutcome = .failure("✗ ERP: \(String(error.localizedDescription.prefix(80)))")
                        }
                    }

                    return (snap.code, DualOutcome(born: bornOutcome, erp: erpOutcome), snap.customName)
                }
            }

            for await result in grp {
                completed += 1
                sendProgress     = Double(completed) / Double(total)
                currentlySending = "\(completed)/\(total)"
                sendResults[result.code] = result.outcome
                // Save record (needs SwiftData / @MainActor — already on main because sendAll is @MainActor via Task)
                if let formula = selectedFormulas.first(where: { $0.code == result.code }) {
                    saveRecord(formula: formula, customName: result.customName,
                               customVersion: trimVersion,
                               bornSuccess: result.outcome.born?.isSuccess ?? true,
                               bornMessage: result.outcome.born?.message ?? "",
                               erpSuccess:  result.outcome.erp?.isSuccess ?? true,
                               erpMessage:  result.outcome.erp?.message ?? "",
                               erpAttempted: tgt.sendsToBulut)
                }
            }
        }

        currentlySending = nil
        isSending        = false
        sendProgress     = 1.0
    }

    private func saveRecord(formula: BlendFormula, customName: String,
                            customVersion: String,
                            bornSuccess: Bool, bornMessage: String,
                            erpSuccess: Bool, erpMessage: String,
                            erpAttempted: Bool) {
        let active = formula.ingredients.filter { $0.isActive && $0.mixPct > 0 }
        let snaps  = active.map {
            SentIngredientSnap(code: $0.code, name: $0.name,
                               amountKg: $0.mixPct / 100.0 * formula.totalKg,
                               mixPct: $0.mixPct)
        }
        let snapJSON = (try? String(data: JSONEncoder().encode(snaps), encoding: .utf8)) ?? "[]"
        let record = SendRecord(
            formulaCode:          formula.code,
            formulaName:          formula.name,
            customName:           customName,
            customVersion:        customVersion,
            source:               source,
            isSuccess:            bornSuccess,
            serverMessage:        bornMessage,
            ingredientCount:      active.count,
            totalKg:              formula.totalKg,
            ingredientsSnapshot:  snapJSON,
            costPerTon:           formula.lastSolve?.costPerTon ?? formula.currentCostTL,
            nutrientsSnapshot:    SendRecord.buildNutrientSnaps(from: formula),
            erpRasyonNo:          erpAttempted ? customVersion : "",
            erpIsSuccess:         erpSuccess,
            erpMessage:           erpMessage
        )
        modelContext.insert(record)
        try? modelContext.save()
    }
}

// MARK: - Shared result type

enum SendOutcome: Sendable {
    case success(String)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .success(let m): return m
        case .failure(let m): return m
        }
    }
}

// MARK: - Combined BORN + Bulut ERP outcome (MultiBlendSendSheet)

struct DualOutcome: Sendable {
    let born: SendOutcome?
    let erp:  SendOutcome?

    var isOverallSuccess: Bool {
        (born?.isSuccess ?? true) && (erp?.isSuccess ?? true)
    }
}
