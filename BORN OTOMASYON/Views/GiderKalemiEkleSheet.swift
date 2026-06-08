import SwiftUI
import SwiftData

// MARK: - Gider Kalemi Ekle / Düzenle

struct GiderKalemiEkleSheet: View {
    let brand:     String
    let nextOrder: Int
    var existing:  GiderKalemi? = nil

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name:      String = ""
    @State private var valueStr:  String = ""
    @State private var isPercent: Bool   = false

    private var value: Double {
        Double(valueStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var ornekAciklama: String {
        guard value > 0 else { return "" }
        if isPercent {
            return "Örnek: Rasyon 10.000 ₺/ton ise  → \(String(format: "%.0f", 10000 * value / 100)) ₺/ton eklenir"
        } else {
            return "Her tona sabit \(String(format: "%.2f", value)) ₺ eklenir"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Kalem Adı")
                        TextField("örn: Torbalama, Depo, Yakıt", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Yeni Gider Kalemi — \(brand)")
                }

                Section {
                    Picker("Tür", selection: $isPercent) {
                        Text("₺ / ton  (sabit tutar)").tag(false)
                        Text("% Rasyon maliyeti üzerinden").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    HStack {
                        Text(isPercent ? "Oran" : "Tutar")
                        Spacer()
                        TextField("0", text: $valueStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(isPercent ? "%" : "₺/ton")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Hesaplama Türü")
                } footer: {
                    if !ornekAciklama.isEmpty {
                        Text(ornekAciklama).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Gider Kalemi Ekle" : "Kalemi Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Ekle" : "Kaydet") {
                        save(); dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || value <= 0)
                }
            }
            .onAppear {
                if let ex = existing {
                    name      = ex.name
                    valueStr  = ex.value.truncatingRemainder(dividingBy: 1) == 0
                        ? String(format: "%.0f", ex.value)
                        : String(format: "%.2f", ex.value)
                    isPercent = ex.isPercent
                }
            }
        }
    }

    private func save() {
        if let ex = existing {
            ex.name      = name.trimmingCharacters(in: .whitespaces)
            ex.value     = value
            ex.isPercent = isPercent
        } else {
            let item = GiderKalemi(
                name:       name.trimmingCharacters(in: .whitespaces),
                value:      value,
                isPercent:  isPercent,
                brand:      brand,
                orderIndex: nextOrder
            )
            context.insert(item)
        }
        try? context.save()
    }
}
