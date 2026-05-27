import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct IngredientImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedIngredient.name) private var saved: [FeedIngredient]

    @State private var candidates:       [FeedIngredientCandidate] = []
    @State private var isImporting       = false
    @State private var isSaving          = false
    @State private var errorMessage:     String?
    @State private var searchText        = ""
    @State private var showFilePicker    = false
    @State private var showAddIngredient = false
    @State private var saveAlert:        SaveAlert?
    @State private var sortOption:       SortOption = .nameAsc
    @State private var selectedTab:      LibTab     = .all

    private enum SortOption: String, CaseIterable, Identifiable {
        case nameAsc  = "İsme Göre (A→Z)"
        case nameDesc = "İsme Göre (Z→A)"
        case codeAsc  = "Koda Göre (Küçük→Büyük)"
        case codeDesc = "Koda Göre (Büyük→Küçük)"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .nameAsc:  return "textformat.abc"
            case .nameDesc: return "textformat.abc"
            case .codeAsc:  return "number"
            case .codeDesc: return "number"
            }
        }
    }

    private enum LibTab: String, CaseIterable, Identifiable {
        case all    = "Tümü"
        case active = "Aktifler"
        var id: String { rawValue }
    }

    private var activeCount: Int { saved.filter { $0.isAvailable }.count }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if !candidates.isEmpty {
                    previewList
                } else if !saved.isEmpty {
                    savedListWithTabs
                } else if let err = errorMessage {
                    errorState(err)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Hammadde Kütüphanesi")
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false,
                onCompletion: handleFilePick
            )
            .sheet(isPresented: $showAddIngredient) {
                EditIngredientView(ingredient: nil)
            }
            .overlay {
                if isImporting || isSaving {
                    ProgressView(isImporting ? "Okunuyor…" : "Kaydediliyor…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(item: $saveAlert) { alert in
                Alert(
                    title: Text("Mükerrer Kayıt"),
                    message: Text("\(alert.duplicateCount) hammadde zaten kayıtlı.\nNe yapmak istersiniz?"),
                    primaryButton: .default(Text("Üzerine Yaz")) { performSave(overwrite: true) },
                    secondaryButton: .default(Text("Yalnızca Yeni Ekle")) { performSave(overwrite: false) }
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { showFilePicker = true } label: {
                    Label("TXT Dosyası Seç", systemImage: "doc.badge.plus")
                }
                Button { showAddIngredient = true } label: {
                    Label("Manuel Hammadde Ekle", systemImage: "plus.circle")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(SortOption.allCases) { opt in
                    Button {
                        sortOption = opt
                    } label: {
                        Label(
                            opt.rawValue,
                            systemImage: sortOption == opt ? "checkmark" : opt.icon
                        )
                    }
                }
            } label: {
                Label("Sırala", systemImage: "arrow.up.arrow.down")
            }
        }
        if !candidates.isEmpty {
            ToolbarItem(placement: .confirmationAction) {
                Button { startSave() } label: {
                    Label("Kaydet", systemImage: "square.and.arrow.down")
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç", role: .cancel) {
                    candidates   = []
                    errorMessage = nil
                }
            }
        }
    }

    // MARK: - Preview list (henüz kaydedilmemiş)

    private var previewList: some View {
        List {
            Section {
                Label("\(candidates.count) hammadde okundu — henüz kaydedilmedi", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(filteredCandidates) { item in
                NavigationLink(destination: IngredientDetailView(candidate: item)) {
                    IngredientCandidateRow(item: item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Hammadde veya kod ara…")
    }

    // MARK: - Saved list (DB'deki kayıtlar)

    private var savedListWithTabs: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(LibTab.allCases) { tab in
                    Text(tab == .active ? "Aktifler (\(activeCount))" : "Tümü (\(saved.count))")
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            savedList
        }
    }

    private var savedList: some View {
        let items = selectedTab == .active
            ? filteredSaved.filter { $0.isAvailable }
            : filteredSaved

        return List {
            Section {
                if selectedTab == .active {
                    Label("\(items.count) aktif hammadde", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label("\(saved.count) hammadde kayıtlı (\(activeCount) aktif)", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            ForEach(items) { item in
                NavigationLink(destination: IngredientDetailView(saved: item)) {
                    IngredientSavedRow(item: item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Hammadde veya kod ara…")
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView(
            "Hammadde Kütüphanesi Boş",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Sağ üstteki butona basarak HAMMADDE TXT dosyanızı seçin.")
        )
    }

    private func errorState(_ msg: String) -> some View {
        ContentUnavailableView("Okuma Hatası", systemImage: "xmark.octagon", description: Text(msg))
    }

    // MARK: - Filtering

    private var filteredCandidates: [FeedIngredientCandidate] {
        let base = searchText.isEmpty ? candidates : candidates.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
        return sorted(base)
    }

    private var filteredSaved: [FeedIngredient] {
        let base = searchText.isEmpty ? Array(saved) : saved.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
        return sorted(base)
    }

    private func sorted(_ items: [FeedIngredientCandidate]) -> [FeedIngredientCandidate] {
        switch sortOption {
        case .nameAsc:  return items.sorted { $0.name < $1.name }
        case .nameDesc: return items.sorted { $0.name > $1.name }
        case .codeAsc:  return items.sorted { (Int($0.code) ?? 0) < (Int($1.code) ?? 0) }
        case .codeDesc: return items.sorted { (Int($0.code) ?? 0) > (Int($1.code) ?? 0) }
        }
    }

    private func sorted(_ items: [FeedIngredient]) -> [FeedIngredient] {
        switch sortOption {
        case .nameAsc:  return items.sorted { $0.name < $1.name }
        case .nameDesc: return items.sorted { $0.name > $1.name }
        case .codeAsc:  return items.sorted { (Int($0.code) ?? 0) < (Int($1.code) ?? 0) }
        case .codeDesc: return items.sorted { (Int($0.code) ?? 0) > (Int($1.code) ?? 0) }
        }
    }

    // MARK: - File Pick

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            errorMessage = e.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting  = true
            errorMessage = nil
            Task.detached(priority: .userInitiated) {
                do {
                    let items = try IngredientImporter.preview(url: url)
                    await MainActor.run {
                        candidates  = items
                        isImporting = false
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isImporting  = false
                    }
                }
            }
        }
    }

    // MARK: - Save logic

    private func startSave() {
        let existingNames = Set(saved.map(\.name))
        let dupes = candidates.filter { existingNames.contains($0.name) }.count
        if dupes > 0 {
            saveAlert = SaveAlert(duplicateCount: dupes)
        } else {
            performSave(overwrite: false)
        }
    }

    // MARK: - Save logic

    private func performSave(overwrite: Bool) {
        isSaving = true
        let toSave = candidates
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                let existingNames = Set(saved.map(\.name))
                for candidate in toSave {
                    if existingNames.contains(candidate.name) {
                        if overwrite, let existing = saved.first(where: { $0.name == candidate.name }) {
                            let oldPrice = existing.priceTL
                            existing.update(from: candidate)
                            if let newPrice = candidate.priceTL, newPrice != oldPrice {
                                modelContext.insert(PriceHistoryEntry(ingredientName: existing.name, priceTL: newPrice))
                            }
                        }
                        // overwrite false → atla
                    } else {
                        let ing = FeedIngredient(from: candidate)
                        modelContext.insert(ing)
                        if let price = candidate.priceTL {
                            modelContext.insert(PriceHistoryEntry(ingredientName: candidate.name, priceTL: price))
                        }
                    }
                }
                try? modelContext.save()
                candidates = []
                isSaving   = false
            }
        }
    }
}

// MARK: - Alert model

private struct SaveAlert: Identifiable {
    let id = UUID()
    let duplicateCount: Int
}

// MARK: - Önizleme satırı (henüz kaydedilmemiş)

private struct IngredientCandidateRow: View {
    let item: FeedIngredientCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        codeBadge(item.code)
                        Text(item.name).font(.headline)
                    }
                }
                Spacer()
                if let p = item.priceTL {
                    Text(p.formatted(.number.locale(Locale(identifier: "tr_TR"))) + " ₺")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 10) {
                chip("KM",  item.dryMatter,    "%")
                chip("HP",  item.crudeProtein, "%")
                chip("Yağ", item.crudeFat,     "%")
                chip("ME",  item.meRuminantFixed,        "kcal")
            }
            .font(.caption)
            HStack(spacing: 10) {
                chip("Ca",  item.calcium,    "%")
                chip("P",   item.phosphorus, "%")
                chip("Lys", item.lysine,     "%")
                chip("Met", item.methionine, "%")
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func codeBadge(_ code: String) -> some View {
        let label = code.isEmpty ? "?" : "[\(code)]"
        return Text(label)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange, in: Capsule())
    }

    private func chip(_ label: String, _ v: Double?, _ unit: String) -> some View {
        HStack(spacing: 2) {
            Text(label + ":").foregroundStyle(.secondary)
            Text(v.map { String(format: "%.2f", $0) + " " + unit } ?? "—")
                .foregroundStyle(v == nil ? .tertiary : .primary)
        }
    }
}

// MARK: - Kayıtlı hammadde satırı

private struct IngredientSavedRow: View {
    let item: FeedIngredient

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        codeBadge(item.code)
                        Text(item.name).font(.headline)
                    }
                }
                Spacer()
                if let p = item.priceTL {
                    Text(p.formatted(.number.locale(Locale(identifier: "tr_TR"))) + " ₺")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 10) {
                chip("KM",  item.dryMatter,    "%")
                chip("HP",  item.crudeProtein, "%")
                chip("Yağ", item.crudeFat,     "%")
                chip("ME",  item.meRuminantFixed,        "kcal")
            }
            .font(.caption)
            HStack(spacing: 10) {
                chip("Ca",  item.calcium,    "%")
                chip("P",   item.phosphorus, "%")
                chip("Lys", item.lysine,     "%")
                chip("Met", item.methionine, "%")
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func codeBadge(_ code: String) -> some View {
        let label = code.isEmpty ? "?" : "[\(code)]"
        return Text(label)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange, in: Capsule())
    }

    private func chip(_ label: String, _ v: Double?, _ unit: String) -> some View {
        HStack(spacing: 2) {
            Text(label + ":").foregroundStyle(.secondary)
            Text(v.map { String(format: "%.2f", $0) + " " + unit } ?? "—")
                .foregroundStyle(v == nil ? .tertiary : .primary)
        }
    }
}

