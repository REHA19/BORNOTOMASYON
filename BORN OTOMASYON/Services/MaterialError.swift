import Foundation

enum MaterialError: Error, LocalizedError {
    case fileNotFound
    case decodingFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Veri dosyası bulunamadı"
        case .decodingFailed:
            return "Veri okunamadı"
        case .networkError(let message):
            return "Ağ hatası: \(message)"
        }
    }
}
