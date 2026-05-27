import SwiftUI
import SwiftData

// MARK: - Template list (main screen)

struct FormulaTemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FormulaTemplate.createdAt, order: .reverse) private var templates: [FormulaTemplate]

    @State private var showNew    = false
    @State private var editTarget: FormulaTemplate?

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "Şablon Yok",
                        systemImage: "doc.badge.gearshape",
                        description: Text("+ butonu ile yeni şablon oluşturun.")
                    )
                } else {
                    List {
                        ForEach(templates) { tpl in
                            Button { editTarget = tpl } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.badge.gearshape")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tpl.name).font(.subheadline.bold())
                                        Text("\(tpl.ingredients.count) hammadde · \(tpl.constraints.count) kısıt")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    context.delete(tpl)
                                    try? context.save()
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Formül Şablonları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                NewTemplateSheet()
            }
            .sheet(item: $editTarget) { tpl in
                FormulaTemplateEditorView(template: tpl)
            }
        }
    }
}

// MARK: - New template creator (inserts into context first)

private struct NewTemplateSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @State private var created: FormulaTemplate?

    var body: some View {
        Group {
            if let tpl = created {
                FormulaTemplateEditorView(template: tpl)
            } else {
                ProgressView()
                    .onAppear {
                        let tpl = FormulaTemplate(name: "")
                        context.insert(tpl)
                        created = tpl
                    }
            }
        }
    }
}

// MARK: - Template editor

struct FormulaTemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query private var library: [FeedIngredient]

    let template: FormulaTemplate

    // Local editable copies
    @State private var name:        String = ""
    @State private var ingredients: [TemplateIngredient] = []
    @State private var constraints: [BFConstraint]       = []

    @State private var showIngPicker = false
    @State private var showConPicker = false
    @State private var search        = ""

    var body: some View {
        NavigationStack {
            List {
                // Name
                Section("Şablon Adı") {
                    TextField("Şablon adını girin", text: $name)
                }

                // Ingredients
                Section {
                    ForEach($ingredients) { $ti in
                        TemplateIngredientRow(ti: $ti)
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                } header: {
                    HStack {
                        Text("Hammaddeler (\(ingredients.count))")
                        Spacer()
                        Button { showIngPicker = true } label: {
                            Label("Ekle", systemImage: "plus.circle").font(.caption)
                        }
                    }
                }

                // Constraints
                Section {
                    ForEach($constraints) { $con in
                        TemplateConstraintRow(con: $con)
                    }
                    .onDelete { constraints.remove(atOffsets: $0) }
                } header: {
                    HStack {
                        Text("Besin Kısıtları (\(constraints.count))")
                        Spacer()
                        Button { showConPicker = true } label: {
                            Label("Ekle", systemImage: "plus.circle").font(.caption)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(name.isEmpty ? "Yeni Şablon" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        if template.name.isEmpty {
                            context.delete(template)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showIngPicker) {
                TemplateIngredientPickerSheet(
                    library:     library,
                    existing:    ingredients,
                    onSelect:    { ti in
                        if !ingredients.contains(where: { $0.code == ti.code }) {
                            ingredients.append(ti)
                        }
                    }
                )
            }
            .sheet(isPresented: $showConPicker) {
                TemplateConstraintPickerSheet(existing: constraints) { def in
                    if !constraints.contains(where: { $0.nutrientKey == def.key }) {
                        constraints.append(BFConstraint(
                            nutrientKey: def.key,
                            displayName: def.displayName,
                            unit:        def.unit
                        ))
                    }
                }
            }
        }
        .onAppear {
            name        = template.name
            ingredients = template.ingredients
            constraints = template.constraints
        }
    }

    private func save() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        template.name        = name.trimmingCharacters(in: .whitespaces)
        template.ingredients = ingredients
        template.constraints = constraints
        try? context.save()
        dismiss()
    }
}

// MARK: - Template ingredient row

private struct TemplateIngredientRow: View {
    @Binding var ti: TemplateIngredient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ti.name).font(.subheadline).fontWeight(.medium)
                    Text(ti.code).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                pctField("Min%", $ti.minPct)
                pctField("Max%", $ti.maxPct)
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    private func pctField(_ label: String, _ binding: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField("0", value: binding, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
                .font(.caption.bold())
        }
    }
}

// MARK: - Template constraint row

private struct TemplateConstraintRow: View {
    @Binding var con: BFConstraint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(con.resolvedDisplayName).font(.subheadline).fontWeight(.medium)
                Text("(\(con.unit))").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 16) {
                optField("Min", minBinding)
                optField("Max", maxBinding)
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    private var minBinding: Binding<String> {
        Binding(
            get: {
                guard let v = con.minValue else { return "" }
                return v.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", v)
                    : String(format: "%.4g", v)
            },
            set: { str in
                let clean = str.replacingOccurrences(of: ",", with: ".")
                if clean.isEmpty { con.minValue = nil }
                else if let v = Double(clean) { con.minValue = v }
            }
        )
    }
    private var maxBinding: Binding<String> {
        Binding(
            get: {
                guard let v = con.maxValue else { return "" }
                return v.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", v)
                    : String(format: "%.4g", v)
            },
            set: { str in
                let clean = str.replacingOccurrences(of: ",", with: ".")
                if clean.isEmpty { con.maxValue = nil }
                else if let v = Double(clean) { con.maxValue = v }
            }
        )
    }

    private func optField(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField("—", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .font(.caption.bold())
        }
    }
}

// MARK: - Ingredient picker for template

private struct TemplateIngredientPickerSheet: View {
    let library:   [FeedIngredient]
    let existing:  [TemplateIngredient]
    let onSelect:  (TemplateIngredient) -> Void

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
                let already = existing.contains { $0.code == ing.code }
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
                            onSelect(TemplateIngredient(code: ing.code, name: ing.name))
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

// MARK: - Constraint picker for template

private struct TemplateConstraintPickerSheet: View {
    let existing: [BFConstraint]
    let onSelect: (NutrientDef) -> Void

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
                let already = existing.contains { $0.nutrientKey == def.key }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.displayName).font(.subheadline)
                        Text(def.unit).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if already {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Ekle") { onSelect(def) }
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

// MARK: - Template picker sheet (used in FormulaEditorView)

struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FormulaTemplate.createdAt, order: .reverse) private var templates: [FormulaTemplate]

    let onApply: (FormulaTemplate) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "Şablon Yok",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Önce Şablonlar ekranından şablon oluşturun.")
                    )
                } else {
                    List(templates) { tpl in
                        Button {
                            onApply(tpl)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.badge.gearshape")
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tpl.name).font(.subheadline.bold())
                                    Text("\(tpl.ingredients.count) hammadde · \(tpl.constraints.count) kısıt")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.purple)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Şablon Uygula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
    }
}
