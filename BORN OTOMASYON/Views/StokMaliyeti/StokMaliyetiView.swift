import SwiftUI
import SwiftData
import UserNotifications

struct StokMaliyetiView: View {

    // SwiftData
    @Query(filter: #Predicate<StokManuelKalem> { !$0.isArchived },
           sort: \StokManuelKalem.orderIndex)
    private var manuelKalemler: [StokManuelKalem]
    @Query private var ingredients: [FeedIngredient]
    @Query(sort: \BrandDefinition.orderIndex) private var brands: [BrandDefinition]

    // API verileri
    @State private var materials:  [Material]       = []
    @State private var dailyRates: [String: Double] = [:]
    @State private var usdRate:    Double            = 0
    @State private var eurRate:    Double            = 0
    @State private var isLoading   = false

    // UI
    @State private var sortMode:           SortMode         = .byAmountDesc
    @State private var showAddManuel       = false
    @State private var editTarget:         StokManuelKalem? = nil
    @State private var deleteTarget:       StokManuelKalem? = nil
    @State private var showDeleteAlert     = false
    @State private var showForecast        = false
    @State private var showManageKategori  = false
    @State private var showRaporlar        = false
    @State private var isSaving            = false
    @State private var saveToast:          String?          = nil
    @State private var showAntetPicker        = false
    @State private var pendingAntet: UIImage?  = nil
    @State private var hasPendingExport        = false

    @Environment(\.modelContext) private var context

    private let matService  = MaterialService()
    private let stockDaySvc = StockDaysService()
    private let fxService   = ExchangeRateService()

    enum SortMode: String, CaseIterable, Identifiable {
        case byAmountDesc = "Tutar ↓"
        case byAmountAsc  = "Tutar ↑"
        case alphabetical = "A–Z"
        var id: String { rawValue }
    }

    // MARK: - Hesaplamalar

    private var priceMap: [String: Double] {
        var map: [String: Double] = [:]
        for ing in ingredients {
            if let p = ing.priceTL {
                map[ing.code.lowercased().trimmingCharacters(in: .whitespaces)] = p
            }
        }
        return map
    }

    private struct HammaddeRow: Identifiable {
        let id:       String
        let code:     String
        let name:     String
        let stockKg:  Double
        let priceTL:  Double?
        let totalTL:  Double
        let daysLeft: Double?
    }

    private var hammaddeRows: [HammaddeRow] {
        let pm = priceMap
        var rows = materials.map { mat -> HammaddeRow in
            let key   = mat.materialCode.lowercased().trimmingCharacters(in: .whitespaces)
            let price = pm[key]
            let daily = dailyRates[mat.materialCode] ?? 0
            let days  = daily > 0 ? mat.netStock / daily : nil
            // priceTL ₺/ton cinsinden; netStock kg → bölü 1000
            return HammaddeRow(
                id:       mat.materialCode,
                code:     mat.materialCode,
                name:     mat.materialName,
                stockKg:  mat.netStock,
                priceTL:  price,
                totalTL:  mat.netStock * (price ?? 0) / 1000,
                daysLeft: days
            )
        }
        switch sortMode {
        case .byAmountDesc:  rows.sort { $0.totalTL > $1.totalTL }
        case .byAmountAsc:   rows.sort { $0.totalTL < $1.totalTL }
        case .alphabetical:  rows.sort { $0.name < $1.name }
        }
        return rows
    }

    private var hammaddeToplam: Double { hammaddeRows.reduce(0) { $0 + $1.totalTL } }

    private var manuelToplam: Double {
        manuelKalemler.reduce(0) { $0 + $1.totalTL(usdRate: usdRate, eurRate: eurRate) }
    }

    private var grandTotal: Double { hammaddeToplam + manuelToplam }

    private var rateLabel: String {
        guard usdRate > 0 || eurRate > 0 else { return "" }
        var parts: [String] = []
        if usdRate > 0 { parts.append(String(format: "1$ = %.2f ₺", usdRate)) }
        if eurRate > 0 { parts.append(String(format: "1€ = %.2f ₺", eurRate)) }
        return parts.joined(separator: "  •  ")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if isLoading && materials.isEmpty {
                        ProgressView("Stok yükleniyor…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        mainList
                    }
                }

                // Toast bildirimi
                if let toast = saveToast {
                    Text(toast)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.green.opacity(0.92), in: Capsule())
                        .shadow(radius: 6)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: saveToast)
            .navigationTitle("Stok Maliyeti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(isPresented: $showRaporlar) {
                StokRaporlarView()
            }
            .sheet(isPresented: $showAddManuel) {
                StokManuelKalemSheet(nextOrder: manuelKalemler.count,
                                     usdRate: usdRate, eurRate: eurRate)
            }
            .sheet(item: $editTarget) { item in
                StokManuelKalemSheet(existing: item, nextOrder: item.orderIndex,
                                     usdRate: usdRate, eurRate: eurRate)
            }
            .sheet(isPresented: $showForecast) {
                StokMaliyetiForecastView(
                    materials:  materials,
                    dailyRates: dailyRates,
                    priceMap:   priceMap
                )
            }
            .sheet(isPresented: $showManageKategori) {
                StokKategoriYonetimSheet()
            }
            .sheet(isPresented: $showAntetPicker, onDismiss: {
                if hasPendingExport {
                    hasPendingExport = false
                    doExportCurrent(antet: pendingAntet)
                }
            }) {
                AntetSecimSheet(brands: brands.filter { $0.antetImage != nil }) { brand in
                    pendingAntet = brand?.antetImage
                    hasPendingExport = true
                }
            }
            .alert("Kalemi Sil", isPresented: $showDeleteAlert, presenting: deleteTarget) { item in
                Button("Sil", role: .destructive) { deleteManuel(item) }
                Button("Vazgeç", role: .cancel) {}
            } message: { item in
                Text("\"\(item.name)\" kalıcı olarak silinecek.")
            }
        }
        .task {
            StokKategori.seedIfNeeded(context: context)
            await load()
            checkAutoSave()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 14) {
                // Yenile
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)

                // Kaydet
                Button {
                    saveCurrentMonth()
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Label("Kaydet", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isSaving || materials.isEmpty)

                // Menü
                Menu {
                    Section("Sıralama") {
                        ForEach(SortMode.allCases) { mode in
                            Button {
                                sortMode = mode
                            } label: {
                                if sortMode == mode {
                                    Label(mode.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(mode.rawValue)
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            exportCurrentPDF()
                        } label: {
                            Label("PDF Olarak Paylaş", systemImage: "square.and.arrow.up")
                        }
                        .disabled(materials.isEmpty)

                        Button {
                            showRaporlar = true
                        } label: {
                            Label("Aylık Raporlar", systemImage: "archivebox.fill")
                        }

                        Button {
                            showManageKategori = true
                        } label: {
                            Label("Kategorileri Düzenle", systemImage: "list.bullet.indent")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Main list

    private var mainList: some View {
        List {
            // Özet kart
            Section {
                summaryCard
            }

            // Güncel kur bilgisi
            if !rateLabel.isEmpty {
                Section {
                    Text(rateLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Hammaddeler
            Section {
                if hammaddeRows.isEmpty {
                    Label("Stok verisi yüklenemedi", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(hammaddeRows) { row in
                        hammaddeCell(row)
                    }
                }
            } header: {
                HStack {
                    Text("Hammadde Stoğu")
                    Spacer()
                    if isLoading { ProgressView().scaleEffect(0.7) }
                }
            } footer: {
                if hammaddeRows.contains(where: { $0.priceTL == nil }) {
                    Text("Gri satırlar: FeedIngredient fiyatı girilmemiş.")
                        .font(.caption2)
                }
            }

            // Manuel kalemler
            Section {
                ForEach(manuelKalemler) { item in
                    manuelCell(item)
                }
                Button {
                    showAddManuel = true
                } label: {
                    Label("Kalem Ekle", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            } header: {
                HStack {
                    Text("Manuel Kalemler")
                    Spacer()
                    Button {
                        showManageKategori = true
                    } label: {
                        Image(systemName: "list.bullet.indent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                if !manuelKalemler.isEmpty {
                    Text("Toplam: \(manuelToplam.tlString)")
                        .font(.caption2.bold())
                }
            }

            // 30 günlük rapor
            Section {
                Button {
                    showForecast = true
                } label: {
                    Label("30 Günlük Tedarik Bütçesi Raporu", systemImage: "chart.bar.fill")
                        .foregroundStyle(.indigo)
                }
                .disabled(materials.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Hammadde Stoğu", systemImage: "shippingbox.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(hammaddeToplam.tlString)
                    .font(.subheadline.bold())
            }
            HStack {
                Label("Manuel Kalemler", systemImage: "list.clipboard.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(manuelToplam.tlString)
                    .font(.subheadline.bold())
            }
            Divider()
            HStack {
                Text("TOPLAM STOK DEĞERİ")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(grandTotal.tlString)
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Hammadde cell

    @ViewBuilder
    private func hammaddeCell(_ row: HammaddeRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(row.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .foregroundStyle(row.priceTL == nil ? .secondary : .primary)
                Spacer()
                if row.priceTL == nil {
                    Text("Fiyat girilmedi")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text(row.totalTL.tlString)
                        .font(.subheadline.bold())
                }
            }
            HStack(spacing: 14) {
                Text(row.stockKg.kgString)
                    .font(.caption).foregroundStyle(.secondary)
                if let p = row.priceTL {
                    Text("× \(p.tlString)/ton")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let days = row.daysLeft {
                    daysTag(days)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(row.priceTL == nil ? 0.55 : 1)
    }

    @ViewBuilder
    private func daysTag(_ days: Double) -> some View {
        let color: Color = days < 7 ? .red : days < 14 ? .orange : days < 30 ? .yellow : .green
        Text(String(format: "%.0f gün", days))
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Manuel cell

    @ViewBuilder
    private func manuelCell(_ item: StokManuelKalem) -> some View {
        let total = item.totalTL(usdRate: usdRate, eurRate: eurRate)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.bold())
                    if !item.category.isEmpty {
                        Text(item.category)
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(String(format: "%.2f %@", item.quantity, item.unit))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("×")
                        .font(.caption).foregroundStyle(.tertiary)
                    Text(currencyLabel(item))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(total.tlString)
                .font(.subheadline.bold())
        }
        .contentShape(Rectangle())
        .onTapGesture { editTarget = item }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget    = item
                showDeleteAlert = true
            } label: {
                Label("Sil", systemImage: "trash")
            }
            Button { editTarget = item } label: {
                Label("Düzenle", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button { editTarget = item } label: {
                Label("Düzenle", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteTarget    = item
                showDeleteAlert = true
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    private func currencyLabel(_ item: StokManuelKalem) -> String {
        switch item.currency {
        case "USD": return String(format: "%.2f $ → %.2f ₺/%@", item.unitPrice, item.unitPrice * usdRate, item.unit)
        case "EUR": return String(format: "%.2f € → %.2f ₺/%@", item.unitPrice, item.unitPrice * eurRate, item.unit)
        default:    return String(format: "%.2f ₺/%@", item.unitPrice, item.unit)
        }
    }

    // MARK: - Data loading

    private func load() async {
        isLoading = true
        async let mats    = try? matService.fetchMaterials()
        async let usd     = fxService.fetchUSDTRY()
        async let eur     = fxService.fetchEURTRY()

        let (fetchedMats, fetchedUSD, fetchedEUR) = await (mats, usd, eur)
        let resolvedMats = fetchedMats ?? []
        let rates = await stockDaySvc.calculateDailyRates(currentStock: resolvedMats)

        await MainActor.run {
            materials  = resolvedMats
            dailyRates = rates
            if let u = fetchedUSD { usdRate = u }
            if let e = fetchedEUR { eurRate = e }
            isLoading  = false
        }
    }

    private func deleteManuel(_ item: StokManuelKalem) {
        context.delete(item)
        try? context.save()
    }

    // MARK: - Snapshot oluştur

    private func buildCurrentSnapshot() -> StokRaporSnapshot {
        let hmSnaps = hammaddeRows.map { row in
            HammaddeSnapshot(
                code:    row.code,
                name:    row.name,
                stockKg: row.stockKg,
                priceTL: row.priceTL,
                totalTL: row.totalTL
            )
        }
        return StokAylikRapor.buildSnapshot(
            hammaddeRows:   hmSnaps,
            manuelKalemler: Array(manuelKalemler),
            hammaddeToplam: hammaddeToplam,
            manuelToplam:   manuelToplam,
            grandTotal:     grandTotal,
            usdRate:        usdRate,
            eurRate:        eurRate
        )
    }

    // MARK: - Manuel kaydet (bu ay)

    private func saveCurrentMonth() {
        guard !materials.isEmpty else { return }
        isSaving = true
        let snap = buildCurrentSnapshot()
        let cal  = Calendar.current
        let now  = Date()
        let yil  = cal.component(.year,  from: now)
        let ay   = cal.component(.month, from: now)
        StokAylikRapor.upsert(snapshot: snap, yil: yil, ay: ay,
                              otomatik: false, context: context)
        isSaving = false
        showToast("✓ \(currentMonthBaslik()) raporu kaydedildi")
        scheduleMonthEndNotification()
    }

    // MARK: - Otomatik kaydet (ay geçişinde)

    private func checkAutoSave() {
        guard !materials.isEmpty else { return }
        let cal  = Calendar.current
        let now  = Date()
        let yil  = cal.component(.year,  from: now)
        let ay   = cal.component(.month, from: now)

        // Geçen ayı hesapla
        guard let prevMonth = cal.date(byAdding: .month, value: -1, to: now) else { return }
        let prevYil = cal.component(.year,  from: prevMonth)
        let prevAy  = cal.component(.month, from: prevMonth)

        // Geçen ay için kayıt yoksa otomatik kaydet
        if StokAylikRapor.existing(yil: prevYil, ay: prevAy, in: context) == nil {
            let snap = buildCurrentSnapshot()
            StokAylikRapor.upsert(snapshot: snap, yil: prevYil, ay: prevAy,
                                  otomatik: true, context: context)
            print("🗃 Otomatik stok raporu: \(prevAy)/\(prevYil)")
        }

        // Aynı ay için de yoksa ve bu ayın son 3 günündeyse kaydet
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        if dayOfMonth >= daysInMonth - 2,
           StokAylikRapor.existing(yil: yil, ay: ay, in: context) == nil {
            let snap = buildCurrentSnapshot()
            StokAylikRapor.upsert(snapshot: snap, yil: yil, ay: ay,
                                  otomatik: true, context: context)
        }
    }

    // MARK: - PDF paylaş

    private func exportCurrentPDF() {
        guard !materials.isEmpty else { return }
        // Antetli markalar varsa seçim sun; yoksa doğrudan oluştur
        let brandsWithAntet = brands.filter { $0.antetImage != nil }
        if brandsWithAntet.count > 1 {
            showAntetPicker = true
        } else {
            doExportCurrent(antet: brandsWithAntet.first?.antetImage)
        }
    }

    private func doExportCurrent(antet: UIImage?) {
        let snap   = buildCurrentSnapshot()
        let baslik = currentMonthBaslik()
        Task.detached(priority: .userInitiated) {
            let data = StokPDFService.generateCurrent(snap: snap, baslik: baslik, antet: antet)
            let url  = await MainActor.run { writeTempPDF(data: data) }
            await MainActor.run { ShareService.share(items: [url]) }
        }
    }

    private func writeTempPDF(data: Data) -> URL {
        let name = currentMonthBaslik().replacingOccurrences(of: " ", with: "_")
        let url  = FileManager.default.temporaryDirectory
            .appendingPathComponent("StokRaporu_\(name).pdf")
        try? data.write(to: url)
        return url
    }

    // MARK: - Yardımcılar

    private func currentMonthBaslik() -> String {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: Date()).capitalized
    }

    private func showToast(_ message: String) {
        withAnimation { saveToast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { saveToast = nil }
        }
    }

    // Ay sonunda kullanıcıya hatırlatma bildirimi zamanla
    private func scheduleMonthEndNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["stok_ay_sonu"])

        let cal  = Calendar.current
        let now  = Date()
        guard let interval   = cal.dateInterval(of: .month, for: now),
              let lastDay    = cal.date(byAdding: .day, value: -1, to: interval.end)
        else { return }

        var comps        = cal.dateComponents([.year, .month, .day], from: lastDay)
        comps.hour       = 23
        comps.minute     = 55

        let content      = UNMutableNotificationContent()
        content.title    = "Aylık Stok Raporu"
        content.body     = "Bu ayın stok maliyet raporunu kaydetmek için uygulamayı açın."
        content.sound    = .default

        let trigger      = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request      = UNNotificationRequest(identifier: "stok_ay_sonu",
                                                  content: content, trigger: trigger)
        center.add(request)
    }
}
