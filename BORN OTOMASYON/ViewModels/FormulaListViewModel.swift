import SwiftUI
import Combine

// MARK: - Rasyon grubu (aynı customName'i paylaşan formüller)

struct RasyonGroup: Identifiable {
    let customName:  String
    let formulas:    [FormulaActiveResponse]
    let latestDate:  Date
    var id: String { customName }
    var productCount: Int { formulas.count }
}

// MARK: - Gün grubu (aynı takvim gününe ait rasyonlar)

struct DayGroup: Identifiable {
    let date:    Date          // takvim günü başlangıcı (startOfDay)
    let rasyons: [RasyonGroup]
    var id: String { date.trShort }

    var dayLabel:     String { date.trLong   }  // "27 Nisan 2026, Pazartesi"
    var dayShort:     String { date.trShort  }  // "27 Nisan 2026"
}

// MARK: - ViewModel

@MainActor
final class FormulaListViewModel: ObservableObject {

    @Published var formulas:     [FormulaActiveResponse] = [] { didSet { rebuildGroups() } }
    /// Ay → Gün → Rasyonlar
    @Published var rasyonGroups: [(month: String, days: [DayGroup])] = []
    @Published var isScanning    = false
    @Published var statusMessage = ""
    @Published var scanProgress  = 0.0

    private let service  = FormulaListService()
    private let cache    = FormulaCache.shared
    private var scanTask: Task<Void, Never>?

    // MARK: - İlk yükleme: cache'i göster + arka planda her zaman tara

    func initialLoad() async {
        let cached = cache.load()
        if !cached.isEmpty {
            formulas      = cached
            statusMessage = "\(cached.count) formül"

            // Aynı ay içinde yüklenmiş cache varsa tekrar tarama yapma
            if cache.isCurrentMonth {
                return
            }
            // Ay değiştiyse eski cache'i temizle, yeni ay için tara
            cache.clear()
            formulas      = []
            statusMessage = "Yeni ay — taranıyor…"
        }
        await runScan()
    }

    // MARK: - Elle yenile

    func reload() async {
        scanTask?.cancel()
        cache.clear()
        formulas      = []
        scanProgress  = 0
        statusMessage = "Taranıyor…"
        await runScan()
    }

    func cancelScan() {
        scanTask?.cancel()
        cache.save(formulas)
        isScanning    = false
        statusMessage = "\(formulas.count) formül"
    }

    // MARK: - Tarama motoru

    // Bulunduğumuz ayın 1. günü (00:00:00)
    private var monthStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private func runScan() async {
        isScanning    = true
        statusMessage = "Yükleniyor…"
        scanProgress  = 0

        // 1) Consumption API → bu ayın formulaID'leri (hızlı, doğru yol)
        statusMessage = "Sarfiyat API deneniyor…"
        let (consumption, debug) = await service.fetchFromConsumptionDebug(monthStart: monthStart, today: Date())
        statusMessage = debug   // teşhis mesajını göster
        if !consumption.isEmpty {
            mergeAndSave(consumption)
            isScanning    = false
            statusMessage = "\(formulas.count) formül ✓"
            return
        }

        // 2) Genel liste endpoint'leri
        let list = await service.fetchAll()
        if !list.isEmpty {
            mergeAndSave(list)
            isScanning    = false
            statusMessage = "\(formulas.count) formül"
            return
        }

        // 3) Yedek: ID taraması (yavaş)
        let cutoff = monthStart
        let maxID  = 5000

        scanTask = Task {
            var found: [FormulaActiveResponse] = []

            let stream = service.scan(maxID: maxID, batchSize: 15, cutoff: cutoff) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.scanProgress  = Double(progress) / Double(maxID)
                    self.statusMessage = "\(self.formulas.count) formül • %\(Int(self.scanProgress * 100)) tamamlandı"
                }
            }

            for await f in stream {
                guard !Task.isCancelled else { break }
                found.append(f)
                if found.count % 20 == 0 { mergeAndSave(found) }
            }

            mergeAndSave(found)
            isScanning    = false
            statusMessage = "\(formulas.count) formül"
        }

        await scanTask?.value
    }

    // MARK: - Merge & save

    private func mergeAndSave(_ newItems: [FormulaActiveResponse]) {
        var dict: [Int: FormulaActiveResponse] = Dictionary(
            uniqueKeysWithValues: formulas.map { ($0.formulaID, $0) }
        )
        for item in newItems { dict[item.formulaID] = item }
        formulas = Array(dict.values)
        cache.save(formulas)
    }

    // MARK: - Gruplama: Bu ay → Gün → Rasyonlar

    private func rebuildGroups() {
        let cal    = Calendar.current
        let cutoff = monthStart

        // 1) Bu aya ait formüller — effectiveDate yoksa updateDate/createDate zaten bu ay demek
        //    (consumption API'sinden geldiler), hepsini dahil et
        let recent = formulas.filter {
            let d = $0.effectiveDate ?? Date()   // nil ise "şimdi" say → bu ay içinde kalır
            return d >= cutoff
        }

        // 2) displayName = customName varsa o, yoksa materialName
        let byName = Dictionary(grouping: recent) { f -> String in
            if let n = f.customName, !n.isEmpty { return n }
            return f.materialName
        }
        let allRasyons: [RasyonGroup] = byName.map { name, items in
            let latest = items.map { $0.effectiveDate ?? Date() }.max() ?? Date()
            return RasyonGroup(customName: name, formulas: items, latestDate: latest)
        }

        // 3) Takvim gününe göre grupla
        let byDay = Dictionary(grouping: allRasyons) { (rasyon: RasyonGroup) -> Date in
            cal.startOfDay(for: rasyon.latestDate)
        }

        var dayGroups: [DayGroup] = byDay.map { (date: Date, rasyons: [RasyonGroup]) -> DayGroup in
            DayGroup(date: date, rasyons: rasyons.sorted { $0.customName < $1.customName })
        }
        dayGroups.sort { $0.date > $1.date }

        // 4) Aya göre grupla
        let byMonth = Dictionary(grouping: dayGroups) { monthKey(from: $0.date) }
        rasyonGroups = byMonth.keys
            .sorted { parseMonthKey($0) > parseMonthKey($1) }
            .map { k in (month: k, days: byMonth[k]!.sorted { $0.date > $1.date }) }
    }

    // MARK: - Tarih yardımcıları

    func parseDate(_ formula: FormulaActiveResponse) -> Date {
        formula.effectiveDate ?? .distantPast
    }

    private func monthKey(from date: Date) -> String {
        date == .distantPast ? "Tarihsiz" : date.trMonthYear
    }

    private func parseMonthKey(_ key: String) -> Date {
        guard key != "Tarihsiz" else { return .distantPast }
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "tr_TR")
        fmt.dateFormat = "MMMM yyyy"
        return fmt.date(from: key) ?? .distantPast
    }
}
