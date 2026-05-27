import Foundation

final class FormulaCache {

    static let shared = FormulaCache()
    private init() {}

    private struct Envelope: Codable {
        let savedAt:  Date
        let formulas: [FormulaActiveResponse]
    }

    private var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("formula_list_cache.json")
    }

    // MARK: - Kaydet

    func save(_ formulas: [FormulaActiveResponse]) {
        guard !formulas.isEmpty else { return }
        let envelope = Envelope(savedAt: Date(), formulas: formulas)
        if let data = try? JSONEncoder().encode(envelope) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Yükle

    func load() -> [FormulaActiveResponse] {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return [] }
        return envelope.formulas
    }

    // MARK: - Cache ne kadar eski?

    func savedAt() -> Date? {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        return envelope.savedAt
    }

    /// Cache yaşı saat cinsinden
    var ageHours: Double {
        guard let saved = savedAt() else { return .infinity }
        return Date().timeIntervalSince(saved) / 3600
    }

    /// Cache, bulunduğumuz takvim ayına ait mi?
    var isCurrentMonth: Bool {
        guard let saved = savedAt() else { return false }
        return Calendar.current.isDate(saved, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Temizle

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
