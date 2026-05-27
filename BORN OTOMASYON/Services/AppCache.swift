import Foundation

// MARK: - Uygulama geneli JSON önbellek servisi

final class AppCache {
    static let shared = AppCache()

    private let folder: URL

    // Envelope tip seviyesinde tanımlanmalı (Swift generic function'ın içine alınamaz)
    private struct Envelope: Codable {
        let savedAt: Date
        let payload: Data  // herhangi bir Codable → Data olarak sakla
    }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("BornCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: - Kaydet

    func save<T: Encodable>(_ value: T, key: Key) {
        guard let payload = try? encoder.encode(value) else { return }
        let env = Envelope(savedAt: Date(), payload: payload)
        guard let data = try? encoder.encode(env) else { return }
        try? data.write(to: fileURL(key))
    }

    // MARK: - Yükle

    func load<T: Decodable>(_ type: T.Type, key: Key) -> Entry<T>? {
        guard let data    = try? Data(contentsOf: fileURL(key)),
              let env     = try? decoder.decode(Envelope.self, from: data),
              let value   = try? decoder.decode(T.self, from: env.payload) else { return nil }
        return Entry(value: value, savedAt: env.savedAt)
    }

    func clear(key: Key) { try? FileManager.default.removeItem(at: fileURL(key)) }

    // MARK: - Types

    struct Entry<T> {
        let value:   T
        let savedAt: Date
        var ageHours: Double { Date().timeIntervalSince(savedAt) / 3600 }
        var label:    String { savedAt.trClock }
    }

    enum Key: String {
        case materials       = "materials"
        case stockDays       = "stock_days"
        case commodityPrices = "commodity_prices"
        case usdTry          = "usd_try"
        case aiAnalysis      = "ai_analysis"
        case marketNews      = "market_news"
    }

    // MARK: - Private

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private func fileURL(_ key: Key) -> URL {
        folder.appendingPathComponent("\(key.rawValue).json")
    }
}
