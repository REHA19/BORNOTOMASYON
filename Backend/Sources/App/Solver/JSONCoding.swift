import Foundation

/// Same non-conforming-float convention as the iOS BlendFormula.swift encoder/decoder
/// (∞ / -∞ / NaN as strings) — must match exactly or infeasible-solve JSON blobs
/// produced by the app won't deserialize on the backend, and vice versa (Plan §3).
enum JSONCoding {
    static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "∞", negativeInfinity: "-∞", nan: "NaN"
        )
        return try? dec.decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "∞", negativeInfinity: "-∞", nan: "NaN"
        )
        return (try? String(data: enc.encode(value), encoding: .utf8)) ?? "[]"
    }
}
