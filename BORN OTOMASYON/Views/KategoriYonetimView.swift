import SwiftUI
import SwiftData

// MARK: - Kategori Yönetimi (renk + sıra + ekle/sil)

struct KategoriYonetimView: View {
    let brand: String

    @Query(sort: \KategoriTanim.orderIndex) private var tumKategoriler: [KategoriTanim]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    @State private var showAddSheet = false
    @State private var editTarget:  KategoriTanim? = nil

    private var kategoriler: [KategoriTanim] {
        tumKategoriler.filter { $0.brand == brand }
    }

    var body: some View {
        NavigationStack {
            List {
                if kategoriler.isEmpty {
                    ContentUnavailableView(
                        "Kategori Yok",
                        systemImage: "square.grid.2x2",
                        description: Text("+ ile kategori ekleyin veya varsayılanları yükleyin.")
                    )
                } else {
                    ForEach(kategoriler) { kat in
                        KategoriSatiri(kat: kat)
                            .onTapGesture { editTarget = kat }
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                }
            }
            .navigationTitle("\(brand) Kategorileri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        EditButton()
                        Menu {
                            Button { showAddSheet = true } label: {
                                Label("Yeni Kategori", systemImage: "plus")
                            }
                            if kategoriler.isEmpty {
                                Button { seedDefaults() } label: {
                                    Label("Varsayılanları Yükle", systemImage: "arrow.down.circle")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                KategoriEkleSheet(brand: brand, nextOrder: kategoriler.count)
            }
            .sheet(item: $editTarget) { kat in
                KategoriDuzenleSheet(kat: kat)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets { context.delete(kategoriler[idx]) }
        try? context.save()
    }

    private func move(from source: IndexSet, to dest: Int) {
        var list = kategoriler
        list.move(fromOffsets: source, toOffset: dest)
        for (i, k) in list.enumerated() { k.orderIndex = i }
        try? context.save()
    }

    private func seedDefaults() {
        let yeni = KategoriTanim.seedIfNeeded(brand: brand, existing: kategoriler)
        yeni.forEach { context.insert($0) }
        try? context.save()
    }
}

// MARK: - Kategori satırı

private struct KategoriSatiri: View {
    let kat: KategoriTanim
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(kat.swiftColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(kat.name).font(.subheadline.bold()).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Yeni kategori ekle

struct KategoriEkleSheet: View {
    let brand:     String
    let nextOrder: Int
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name:     String = ""
    @State private var color:    Color  = Color(hex: "#1A5E9A")

    var body: some View {
        NavigationStack {
            Form {
                Section("Kategori Adı") {
                    TextField("örn: SIĞIR SÜT YEMLERİ( 50 kg)", text: $name)
                }
                Section("Renk") {
                    ColorPicker("Kategori Rengi", selection: $color, supportsOpacity: false)
                }
            }
            .navigationTitle("Yeni Kategori")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { save(); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let hex = UIColor(color).hexString
        let kat = KategoriTanim(name: name.trimmingCharacters(in: .whitespaces),
                                colorHex: hex, orderIndex: nextOrder, brand: brand)
        context.insert(kat)
        try? context.save()
    }
}

// MARK: - Kategori düzenle

struct KategoriDuzenleSheet: View {
    let kat: KategoriTanim
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name:  String = ""
    @State private var color: Color  = .blue

    var body: some View {
        NavigationStack {
            Form {
                Section("Kategori Adı") {
                    TextField("Kategori adı", text: $name)
                }
                Section("Renk") {
                    ColorPicker("Kategori Rengi", selection: $color, supportsOpacity: false)
                    // Önizleme
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(height: 24)
                }
            }
            .navigationTitle("Düzenle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                name  = kat.name
                color = kat.swiftColor
            }
        }
    }

    private func save() {
        kat.name     = name.trimmingCharacters(in: .whitespaces)
        kat.colorHex = UIColor(color).hexString
        try? context.save()
    }
}
