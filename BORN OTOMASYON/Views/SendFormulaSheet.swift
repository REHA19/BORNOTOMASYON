import SwiftUI
import SwiftData

// MARK: - Single formula send sheet

struct SendFormulaSheet: View {
    let formula: BlendFormula

    @Environment(\.dismiss)       private var dismiss
    @Environment(\.modelContext)  private var modelContext

    @State private var customName:    String = ""
    @State private var customVersion: String = ""
    @State private var validDate:     Date   = Date()
    @State private var comment:       String = ""
    @State private var activate:      Bool   = true
    @State private var isSending:     Bool   = false
    @State private var sendResult:    SendOutcome?

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
                if let r = sendResult { resultSection(r) }
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
                                      || activeIngredients.isEmpty)
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
    private func resultSection(_ r: SendOutcome) -> some View {
        Section {
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

        let model = buildModel()

        do {
            let resp    = try await CreateFormulaService().create(model: model)
            let message = resp.message ?? "Formül başarıyla gönderildi."
            sendResult  = .success(message)
            saveRecord(success: true, message: message)
        } catch {
            let message = error.localizedDescription
            sendResult  = .failure(message)
            saveRecord(success: false, message: message)
        }

        isSending = false
    }

    private func saveRecord(success: Bool, message: String) {
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
            isSuccess:            success,
            serverMessage:        message,
            ingredientCount:      activeIngredients.count,
            totalKg:              formula.totalKg,
            ingredientsSnapshot:  snapJSON
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func buildModel() -> FormulaCreateAppModel {
        let details: [FormulaCreateDetailAppModel] = activeIngredients
            .sorted { $0.mixPct > $1.mixPct }   // en yüksek miktar → RowNo 1
            .enumerated()
            .map { i, ing in
                FormulaCreateDetailAppModel(
                    materialCode: ing.code,
                    materialName: ing.name,
                    rowNo:        i + 1,
                    amount:       ing.mixPct / 100.0 * formula.totalKg,
                    isAdditive:   false
                )
            }

        return FormulaCreateAppModel(
            productCode:   formula.code,
            productName:   formula.name,
            customName:    customName.trimmingCharacters(in: .whitespaces),
            customVersion: customVersion.trimmingCharacters(in: .whitespaces),
            validDate:     validDate,
            totalAmount:   formula.totalKg,
            comment:       comment.trimmingCharacters(in: .whitespaces),
            details:       details,
            activate:      activate
        )
    }
}

// MARK: - Multi-formula (MultiBlend) batch send sheet

struct MultiBlendSendSheet: View {
    let group:       MultiBlendGroup
    let allFormulas: [BlendFormula]

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Per-formula
    @State private var customNames: [String: String] = [:]
    @State private var selected:    Set<String>      = []

    // Shared
    @State private var validDate:      Date   = Date()
    @State private var customVersion:  String = ""
    @State private var comment:        String = ""
    @State private var activate:       Bool   = true

    // Send state
    @State private var isSending:        Bool                   = false
    @State private var sendProgress:     Double                 = 0
    @State private var sendResults:      [String: SendOutcome]  = [:]
    @State private var currentlySending: String?                = nil

    private var groupFormulas: [BlendFormula] {
        group.formulaCodes.compactMap { code in allFormulas.first { $0.code == code } }
    }

    private var selectedFormulas: [BlendFormula] {
        groupFormulas.filter { selected.contains($0.code) }
    }

    var body: some View {
        NavigationStack {
            List {
                sharedParamsSection
                selectionHeaderSection
                formulaRowsSection
            }
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
                        .disabled(selected.isEmpty)
                    }
                }
            }
            .onAppear {
                selected = Set(groupFormulas.map(\.code))
                for f in groupFormulas { customNames[f.code] = f.name }
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
        }
    }

    private var selectionHeaderSection: some View {
        Section {
            HStack {
                Button("Tümünü Seç") {
                    selected = Set(groupFormulas.map(\.code))
                }
                .disabled(selected.count == groupFormulas.count)
                Spacer()
                Button("Seçimi Temizle") { selected = [] }
                    .disabled(selected.isEmpty)
            }
            .font(.caption)
        } header: {
            Text("Formüller (\(selected.count)/\(groupFormulas.count) seçili)")
        }
    }

    @ViewBuilder
    private var formulaRowsSection: some View {
        ForEach(groupFormulas) { formula in
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
                            Image(systemName: res.isSuccess
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(res.isSuccess ? .green : .red)
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
                    Text(res.message)
                        .font(.caption)
                        .foregroundStyle(res.isSuccess ? .green : .red)
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

        // Snapshot all send data on @MainActor before background work
        struct FormSnap: @unchecked Sendable {
            let code: String; let name: String; let totalKg: Double; let customName: String
            let ings: [(code: String, name: String, mixPct: Double)]
        }
        let snaps: [FormSnap] = selectedFormulas.map { f in
            let cName = (customNames[f.code] ?? f.name).trimmingCharacters(in: .whitespaces)
            let active = f.ingredients.filter { $0.isActive && $0.mixPct > 0 }
            return FormSnap(
                code: f.code, name: f.name, totalKg: f.totalKg, customName: cName,
                ings: active.map { (code: $0.code, name: $0.name, mixPct: $0.mixPct) }
            )
        }
        let total = snaps.count
        guard total > 0 else { isSending = false; return }

        currentlySending = "0/\(total)"

        var completed = 0
        await withTaskGroup(of: (code: String, outcome: SendOutcome, customName: String).self) { grp in
            for snap in snaps {
                grp.addTask {
                    let details = snap.ings
                        .sorted { $0.mixPct > $1.mixPct }
                        .enumerated()
                        .map { i, ing in
                            FormulaCreateDetailAppModel(
                                materialCode: ing.code,
                                materialName: ing.name,
                                rowNo:        i + 1,
                                amount:       ing.mixPct / 100.0 * snap.totalKg,
                                isAdditive:   false
                            )
                        }
                    let model = FormulaCreateAppModel(
                        productCode:   snap.code,
                        productName:   snap.name,
                        customName:    snap.customName,
                        customVersion: trimVersion,
                        validDate:     vDate,
                        totalAmount:   snap.totalKg,
                        comment:       trimComment,
                        details:       details,
                        activate:      act
                    )
                    do {
                        let resp    = try await svc.create(model: model)
                        let message = resp.message ?? "✓ Gönderildi"
                        return (snap.code, .success(message), snap.customName)
                    } catch {
                        let message = "✗ \(String(error.localizedDescription.prefix(80)))"
                        return (snap.code, .failure(message), snap.customName)
                    }
                }
            }

            for await result in grp {
                completed += 1
                sendProgress     = Double(completed) / Double(total)
                currentlySending = "\(completed)/\(total)"
                sendResults[result.code] = result.outcome
                // Save record (needs SwiftData / @MainActor — already on main because sendAll is @MainActor via Task)
                if let formula = selectedFormulas.first(where: { $0.code == result.code }) {
                    let success: Bool; let message: String
                    switch result.outcome {
                    case .success(let m): success = true;  message = m
                    case .failure(let m): success = false; message = m
                    }
                    saveRecord(formula: formula, customName: result.customName,
                               customVersion: trimVersion, success: success, message: message)
                }
            }
        }

        currentlySending = nil
        isSending        = false
        sendProgress     = 1.0
    }

    private func saveRecord(formula: BlendFormula, customName: String,
                            customVersion: String, success: Bool, message: String) {
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
            source:               "MultiBlend",
            isSuccess:            success,
            serverMessage:        message,
            ingredientCount:      active.count,
            totalKg:              formula.totalKg,
            ingredientsSnapshot:  snapJSON
        )
        modelContext.insert(record)
        try? modelContext.save()
    }
}

// MARK: - Shared result type

enum SendOutcome {
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
