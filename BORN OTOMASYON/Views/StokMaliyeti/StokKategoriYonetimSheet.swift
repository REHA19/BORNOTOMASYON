import SwiftUI
import SwiftData

struct StokKategoriYonetimSheet: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \StokKategori.orderIndex) private var kategoriler: [StokKategori]

    @State private var showAddSheet  = false
    @State private var editTarget:   StokKategori? = nil
    @State private var editName      = ""
    @State private var showEditAlert = false
    @State private var deleteAlert:  StokKategori? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(kategoriler) { kat in
                        HStack {
                            Text(kat.name)
                                .foregroundStyle(kat.isFixed ? .secondary : .primary)
                            Spacer()
                            if kat.isFixed {
                                Text("Sabit")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !kat.isFixed {
                                Button(role: .destructive) {
                                    deleteAlert    = kat
                                    showDeleteAlert = true
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                                Button {
                                    editTarget = kat
                                    editName   = kat.name
                                    showEditAlert = true
                                } label: {
                                    Label("Yeniden Adlandır", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .contextMenu {
                            if !kat.isFixed {
                                Button {
                                    editTarget = kat
                                    editName   = kat.name
                                    showEditAlert = true
                                } label: {
                                    Label("Yeniden Adlandır", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deleteAlert    = kat
                                    showDeleteAlert = true
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: { Text("Kategoriler") }
                  footer: { Text("Sabit kategoriler silinemez. Kullanıcı kategorilerini kaydırarak silebilir veya yeniden adlandırabilirsiniz.") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Kategorileri Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                KategoriEkleInlineSheet { name in
                    addKategori(name: name)
                }
            }
            .alert("Yeniden Adlandır", isPresented: $showEditAlert, presenting: editTarget) { kat in
                TextField("Kategori adı", text: $editName)
                Button("Kaydet") {
                    let trimmed = editName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { kat.name = trimmed; try? context.save() }
                }
                Button("İptal", role: .cancel) {}
            } message: { kat in
                Text("\"\(kat.name)\" kategorisini yeniden adlandır")
            }
            .alert("Kategoriyi Sil", isPresented: $showDeleteAlert, presenting: deleteAlert) { kat in
                Button("Sil", role: .destructive) { context.delete(kat); try? context.save() }
                Button("Vazgeç", role: .cancel) {}
            } message: { kat in
                Text("\"\(kat.name)\" kategorisi silinecek. Bu kategorideki kalemler etkilenmez.")
            }
        }
    }

    private func addKategori(name: String) {
        let kat = StokKategori(name: name, isFixed: false, orderIndex: kategoriler.count)
        context.insert(kat)
        try? context.save()
    }
}

// MARK: - Inline add sheet (sheet içi sheet için ayrı struct)

private struct KategoriEkleInlineSheet: View {
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Yeni kategori adı", text: $name)
                        .textInputAutocapitalization(.words)
                } header: { Text("Kategori Adı") }
            }
            .navigationTitle("Kategori Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { onAdd(trimmed) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
