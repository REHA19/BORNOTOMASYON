import SwiftUI

// MARK: - CombinationsView

struct CombinationsView: View {
    @Binding var combinations: [BFCombination]
    let ingredients: [BFIngredient]
    let totalKg:     Double
    let lastSolve:   BFSolveResult?

    @Environment(\.dismiss) private var dismiss

    private let maxSlots = 10
    private let colWidth: CGFloat = 64
    private let codeWidth: CGFloat = 50
    private let nameWidth: CGFloat = 150

    // Aktif hammaddeler: stokta olanlar önce, stokta olmayanlar sönük olarak altta
    private var activeIngs: [BFIngredient] {
        ingredients
            .filter { $0.isActive }
            .sorted { ($0.hasStock ? 0 : 1) < ($1.hasStock ? 0 : 1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    headerRow
                    Divider()
                    ingredientRows
                    Divider()
                    footerRows
                }
                .padding(.bottom, 16)
            }
            .navigationTitle("Hammadde Kombinasyonları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Temizle") { combinations.removeAll() }
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("KOD")
                .font(.caption.bold())
                .frame(width: codeWidth, alignment: .leading)
                .padding(.leading, 8)
            Text("Hammadde Adı")
                .font(.caption.bold())
                .frame(width: nameWidth, alignment: .leading)
            ForEach(1...maxSlots, id: \.self) { slot in
                Text("\(slot)")
                    .font(.caption.bold())
                    .frame(width: colWidth)
                    .foregroundStyle(hasAnyData(slot: slot) ? .teal : .secondary)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Ingredient rows

    private var ingredientRows: some View {
        ForEach(activeIngs) { ing in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(ing.code.isEmpty ? "—" : ing.code)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: codeWidth, alignment: .leading)
                        .padding(.leading, 8)

                    HStack(spacing: 4) {
                        Text(ing.name)
                            .font(.caption)
                            .lineLimit(1)
                            .strikethrough(!ing.hasStock, color: .red)
                        if !ing.hasStock {
                            Text("STOK YOK")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.red, in: Capsule())
                        }
                    }
                    .frame(width: nameWidth, alignment: .leading)

                    ForEach(1...maxSlots, id: \.self) { slot in
                        CombinationCell(
                            isActive:    isActive(ing: ing, slot: slot),
                            slotColor:   color(for: slot),
                            disabled:    !ing.hasStock
                        ) {
                            toggleIngredient(ing: ing, slot: slot)
                        }
                        .frame(width: colWidth)
                    }
                }
                .padding(.vertical, 6)
                .background(rowBackground(ing: ing))
                .opacity(ing.hasStock ? 1.0 : 0.4)
                Divider().opacity(0.4)
            }
        }
    }

    // MARK: - Footer rows (Min, Max, Değer)

    private var footerRows: some View {
        VStack(spacing: 0) {
            footerRow(label: "Min (kg)",  keyPath: \.minKg,  isMin: true)
            Divider().opacity(0.5)
            footerRow(label: "Max (kg)",  keyPath: \.maxKg,  isMin: false)
            Divider().opacity(0.5)
            degerRow
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func footerRow(label: String,
                           keyPath: WritableKeyPath<BFCombination, Double?>,
                           isMin: Bool) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: codeWidth + nameWidth, alignment: .leading)
                .padding(.leading, 8)

            ForEach(1...maxSlots, id: \.self) { slot in
                CombinationLimitField(
                    value: Binding(
                        get: {
                            combinations.first { $0.slot == slot }?[keyPath: keyPath]
                        },
                        set: { newVal in
                            ensureSlot(slot)
                            if let i = combinations.firstIndex(where: { $0.slot == slot }) {
                                combinations[i][keyPath: keyPath] = newVal
                            }
                        }
                    ),
                    placeholder: isMin ? "Min" : "Max",
                    accentColor: isMin ? .blue : .orange
                )
                .frame(width: colWidth)
            }
        }
        .padding(.vertical, 6)
    }

    private var degerRow: some View {
        HStack(spacing: 0) {
            Text("Değer")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: codeWidth + nameWidth, alignment: .leading)
                .padding(.leading, 8)

            ForEach(1...maxSlots, id: \.self) { slot in
                let val = currentValue(slot: slot)
                Text(val > 0 ? String(format: "%.1f", val) : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(val > 0 ? valueColor(slot: slot, value: val) : Color.secondary)
                    .frame(width: colWidth)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func isActive(ing: BFIngredient, slot: Int) -> Bool {
        combinations.first { $0.slot == slot }?.ingredientCodes.contains(ing.code) ?? false
    }

    private func hasAnyData(slot: Int) -> Bool {
        guard let combo = combinations.first(where: { $0.slot == slot }) else { return false }
        return !combo.ingredientCodes.isEmpty || combo.minKg != nil || combo.maxKg != nil
    }

    private func toggleIngredient(ing: BFIngredient, slot: Int) {
        ensureSlot(slot)
        guard let i = combinations.firstIndex(where: { $0.slot == slot }) else { return }
        if combinations[i].ingredientCodes.contains(ing.code) {
            combinations[i].ingredientCodes.removeAll { $0 == ing.code }
            // Slot tamamen boşaldıysa ve limit de yoksa sil
            if combinations[i].ingredientCodes.isEmpty
               && combinations[i].minKg == nil
               && combinations[i].maxKg == nil {
                combinations.remove(at: i)
            }
        } else {
            combinations[i].ingredientCodes.append(ing.code)
        }
    }

    private func ensureSlot(_ slot: Int) {
        if !combinations.contains(where: { $0.slot == slot }) {
            combinations.append(BFCombination(slot: slot))
        }
    }

    private func currentValue(slot: Int) -> Double {
        guard let combo = combinations.first(where: { $0.slot == slot }),
              !combo.ingredientCodes.isEmpty,
              let solve = lastSolve else { return 0 }
        let sumPct = combo.ingredientCodes.reduce(0.0) { acc, code in
            acc + (solve.percentagesByCode[code] ?? 0)
        }
        return sumPct / 100.0 * totalKg
    }

    private func valueColor(slot: Int, value: Double) -> Color {
        guard let combo = combinations.first(where: { $0.slot == slot }) else { return .primary }
        if let max = combo.maxKg, value > max + 0.05 { return .red }
        if let min = combo.minKg, value < min - 0.05 { return .orange }
        return .green
    }

    private func color(for slot: Int) -> Color {
        let colors: [Color] = [.teal, .blue, .indigo, .purple, .pink,
                               .red, .orange, .yellow, .green, .mint]
        return colors[(slot - 1) % colors.count]
    }

    private func rowBackground(ing: BFIngredient) -> Color {
        let inAny = combinations.contains { $0.ingredientCodes.contains(ing.code) }
        return inAny ? Color.teal.opacity(0.06) : Color.clear
    }
}

// MARK: - Cell

private struct CombinationCell: View {
    let isActive:  Bool
    let slotColor: Color
    var disabled:  Bool = false
    let onTap:     () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? slotColor.opacity(0.2) : Color(.systemFill))
                    .frame(width: 44, height: 30)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? slotColor : Color.clear, lineWidth: 1.5)
                    .frame(width: 44, height: 30)
                if isActive {
                    Text("1")
                        .font(.caption.bold())
                        .foregroundStyle(slotColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Limit field (Min / Max per slot)

private struct CombinationLimitField: View {
    @Binding var value: Double?
    let placeholder: String
    let accentColor: Color

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.caption.monospacedDigit())
            .multilineTextAlignment(.center)
            .keyboardType(.decimalPad)
            .focused($focused)
            .frame(width: 52, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(focused ? accentColor.opacity(0.12) : Color(.systemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(focused ? accentColor : Color.clear, lineWidth: 1)
            )
            .onAppear { loadText() }
            .onChange(of: value) { _, _ in if !focused { loadText() } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onSubmit { commit() }
    }

    private func loadText() {
        text = value.map { String(format: "%.0f", $0) } ?? ""
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if cleaned.isEmpty {
            value = nil
        } else if let d = Double(cleaned), d >= 0 {
            value = d
        }
    }
}
