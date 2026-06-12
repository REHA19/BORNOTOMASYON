import SwiftUI
import SwiftData

struct StokManuelKalemSheet: View {
    var existing:  StokManuelKalem? = nil
    let nextOrder: Int
    let usdRate:   Double
    let eurRate:   Double

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \StokKategori.orderIndex) private var kategoriler: [StokKategori]

    @State private var name:              String = ""
    @State private var category:          String = ""
    @State private var quantityStr:       String = ""
    @State private var unit:              String = "adet"
    @State private var priceStr:          String = ""
    @State private var currency:          String = "TL"
    @State private var note:              String = ""

    @State private var showManageKategori    = false
    @State private var showKategoriEkleAlert = false
    @State private var newKategoriName       = ""

    private let units      = ["adet", "kg", "lt", "m", "koli", "paket"]
    private let currencies = ["TL", "USD", "EUR"]

    private var quantity: Double {
        Double(quantityStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var price: Double {
        Double(priceStr.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var rate: Double {
        switch currency {
        case "USD": return usdRate
        case "EUR": return eurRate
        default:    return 1.0
        }
    }
    private var totalTL: Double { quantity * price * rate }

    private var fxPreview: String? {
        guard currency != "TL", rate > 1, price > 0 else { return nil }
        let symbol = currency == "USD" ? "$" : "€"
        return "1 \(symbol) = \(String(format: "%.2f", rate)) ₺  →  birim: \(String(format: "%.2f", price * rate)) ₺/\(unit)"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && quantity > 0 && price > 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Kalem Bilgisi
                Section {
                    HStack {
                        Text("Ad")
                        Spacer()
                        TextField("örn: Etiket, Kimyasal, Çuval", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    kategoriRow
                } header: { Text("Kalem Bilgisi") }

                // Miktar & Fiyat
                Section {
                    HStack {
                        Text("Miktar")
                        Spacer()
                        TextField("0", text: $quantityStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Picker("", selection: $unit) {
                            ForEach(units, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }

                    HStack {
                        Text("Birim Fiyat")
                        Spacer()
                        TextField("0", text: $priceStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Picker("", selection: $currency) {
                            ForEach(currencies, id: \.self) { c in
                                Text(c).tag(c)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        Text("/\(unit)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Miktar & Fiyat") }
                  footer: {
                    VStack(alignment: .leading, spacing: 3) {
                        if let preview = fxPreview {
                            Text(preview).font(.caption2).foregroundStyle(.orange)
                        }
                        if totalTL > 0 {
                            Text("Toplam: \(totalTL.tlString)")
                                .font(.caption2.bold()).foregroundStyle(.secondary)
                        }
                    }
                  }

                // Not
                Section {
                    HStack {
                        Text("Not")
                        Spacer()
                        TextField("İsteğe bağlı", text: $note)
                            .multilineTextAlignment(.trailing)
                    }
                } header: { Text("Açıklama") }
            }
            .navigationTitle(existing == nil ? "Manuel Kalem Ekle" : "Kalemi Düzenle")
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
                    .disabled(!canSave)
                }
            }
            .onAppear { applyExisting() }
            .sheet(isPresented: $showManageKategori) {
                StokKategoriYonetimSheet()
            }
            .alert("Yeni Kategori", isPresented: $showKategoriEkleAlert) {
                TextField("Kategori adı", text: $newKategoriName)
                Button("Ekle") {
                    let trimmed = newKategoriName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        let kat = StokKategori(name: trimmed, isFixed: false,
                                               orderIndex: kategoriler.count)
                        context.insert(kat)
                        try? context.save()
                        category = trimmed
                    }
                    newKategoriName = ""
                }
                Button("İptal", role: .cancel) { newKategoriName = "" }
            } message: {
                Text("Yeni bir stok kategorisi ekleyin.")
            }
        }
    }

    // MARK: - Kategori satırı

    private var kategoriRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Kategori", selection: $category) {
                    Text("— Seçin —").tag("")
                    ForEach(kategoriler) { kat in
                        Text(kat.name).tag(kat.name)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    newKategoriName = ""
                    showKategoriEkleAlert = true
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
            }
            Button {
                showManageKategori = true
            } label: {
                Label("Kategorileri Düzenle / Sil", systemImage: "list.bullet.indent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Helpers

    private func applyExisting() {
        guard let ex = existing else { return }
        name        = ex.name
        category    = ex.category
        quantityStr = formatted(ex.quantity)
        unit        = ex.unit
        priceStr    = formatted(ex.unitPrice)
        currency    = ex.currency
        note        = ex.note
    }

    private func formatted(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.2f", v)
    }

    private func save() {
        if let ex = existing {
            ex.name      = name.trimmingCharacters(in: .whitespaces)
            ex.category  = category
            ex.quantity  = quantity
            ex.unit      = unit
            ex.unitPrice = price
            ex.currency  = currency
            ex.note      = note
        } else {
            let item = StokManuelKalem(
                name:       name.trimmingCharacters(in: .whitespaces),
                category:   category,
                quantity:   quantity,
                unit:       unit,
                unitPrice:  price,
                currency:   currency,
                note:       note,
                orderIndex: nextOrder
            )
            context.insert(item)
        }
        try? context.save()
    }
}
