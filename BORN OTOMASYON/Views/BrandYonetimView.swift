import SwiftUI
import SwiftData

// MARK: - Marka Yönetimi

struct BrandYonetimView: View {
    @Query(sort: \BrandDefinition.orderIndex) private var brands: [BrandDefinition]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    @State private var showAddBrand  = false
    @State private var yeniBrandAdi  = ""
    @State private var editTarget:   BrandDefinition? = nil

    var body: some View {
        NavigationStack {
            List {
                if brands.isEmpty {
                    ContentUnavailableView("Marka Yok", systemImage: "building.2",
                                          description: Text("+ butonuyla ilk markayı ekleyin."))
                } else {
                    ForEach(brands) { brand in
                        BrandRow(brand: brand)
                            .onTapGesture { editTarget = brand }
                    }
                    .onDelete(perform: deleteBrands)
                    .onMove(perform: moveBrands)
                }
            }
            .navigationTitle("Marka Yönetimi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        EditButton()
                        Button { showAddBrand = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddBrand) {
                AddBrandSheet { name in
                    let m = BrandDefinition(name: name, orderIndex: brands.count)
                    context.insert(m)
                    try? context.save()
                }
            }
            .sheet(item: $editTarget) { brand in
                BrandEditSheet(brand: brand)
            }
        }
    }

    private func deleteBrands(at offsets: IndexSet) {
        for idx in offsets { context.delete(brands[idx]) }
        try? context.save()
    }

    private func moveBrands(from source: IndexSet, to dest: Int) {
        var list = brands
        list.move(fromOffsets: source, toOffset: dest)
        for (i, b) in list.enumerated() { b.orderIndex = i }
        try? context.save()
    }
}

// MARK: - Marka satırı

private struct BrandRow: View {
    let brand: BrandDefinition
    var body: some View {
        HStack(spacing: 12) {
            if let img = brand.antetImage {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 56, height: 32)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 56, height: 32)
                    .overlay(Image(systemName: "doc.text.image")
                        .foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(brand.name).font(.subheadline.bold())
                Text(brand.hasCustomAntet ? "Antet yüklü ✓" : "Antet yok")
                    .font(.caption2)
                    .foregroundStyle(brand.hasCustomAntet ? .green : .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Yeni marka ekle

private struct AddBrandSheet: View {
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Marka Adı") {
                    TextField("örn: Alapala, Karadeniz, Bayrak…", text: $name)
                }
            }
            .navigationTitle("Yeni Marka")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { onAdd(name.trimmingCharacters(in: .whitespaces)); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Marka düzenleme + antet yükleme

struct BrandEditSheet: View {
    let brand: BrandDefinition
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Marka Adı") {
                    TextField("Marka adı", text: $name)
                }

                Section {
                    // Mevcut antet önizlemesi
                    if let img = brand.antetImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 90)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }

                    ResimYukleButon(
                        baslik: brand.hasCustomAntet ? "Anteti Değiştir" : "Antetli Kağıt Yükle",
                        ikon: "doc.badge.arrow.up"
                    ) { img in
                        kaydetAntet(img)
                    }

                    if brand.hasCustomAntet {
                        Button("Anteti Kaldır") {
                            brand.antetImagePath = ""
                            try? context.save()
                        }
                        .foregroundStyle(.red)
                    }
                } header: {
                    Text("Antetli Kağıt")
                } footer: {
                    Text("PDF fiyat listesinin arka planı olarak kullanılır.")
                        .font(.caption2)
                }
            }
            .navigationTitle(brand.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { name = brand.name }
        }
    }

    private func save() {
        brand.name = name.trimmingCharacters(in: .whitespaces)
        try? context.save()
    }

    private func kaydetAntet(_ img: UIImage) {
        guard let jpeg = img.jpegData(compressionQuality: 0.90) else { return }
        brand.antetImageData = jpeg   // CloudKit CKAsset olarak senkronize edilir
        brand.antetImagePath = ""     // eski lokal path artık kullanılmıyor
        try? context.save()
    }
}
