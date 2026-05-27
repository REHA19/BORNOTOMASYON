import Foundation

// MARK: - StockSnapshot

struct StockSnapshot: Codable, Identifiable {
    let id: UUID
    let date: Date
    let materials: [Material]

    init(date: Date, materials: [Material]) {
        self.id = UUID()
        self.date = date
        self.materials = materials
    }

    var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - SnapshotStore

final class SnapshotStore {

    static let shared = SnapshotStore()
    private init() {}

    private var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stock_snapshots.json")
    }

    // MARK: - Public

    /// Her çağrıda ayrı kayıt tutar (son 200 kayıt saklanır)
    func save(materials: [Material]) {
        var snapshots = load()
        snapshots.append(StockSnapshot(date: Date(), materials: materials))
        let trimmed = snapshots.sorted { $0.date < $1.date }.suffix(200)
        if let data = try? JSONEncoder().encode(Array(trimmed)) {
            try? data.write(to: fileURL)
        }
    }

    /// Tüm kayıtlı snapshotları tarihe göre sıralı döner
    func load() -> [StockSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshots = try? JSONDecoder().decode([StockSnapshot].self, from: data)
        else { return [] }
        return snapshots.sorted { $0.date < $1.date }
    }

    /// Belirli ID'li kaydı siler
    func delete(id: UUID) {
        var snapshots = load()
        snapshots.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: fileURL)
        }
    }

    /// Tüm kayıtları siler
    func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Belirli tarih aralığındaki snapshotları döner
    func snapshots(from start: Date, to end: Date) -> [StockSnapshot] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay   = cal.startOfDay(for: end)
        return load().filter {
            let day = cal.startOfDay(for: $0.date)
            return day >= startDay && day <= endDay
        }
    }
}
