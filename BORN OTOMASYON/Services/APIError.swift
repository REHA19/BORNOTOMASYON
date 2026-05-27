import Foundation

// MARK: - APIError
// Ağ ve HTTP katmanına ait hatalar.
// Domain (iş mantığı) hatalarından ayrı tutulur.

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed(Error)
    case businessError(message: String)   // Success: false → Message
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Geçersiz URL adresi"
        case .invalidResponse:
            return "Sunucudan geçersiz yanıt alındı"
        case .httpError(let code):
            return "Sunucu hatası (HTTP \(code))"
        case .decodingFailed:
            return "Veri ayrıştırılamadı"
        case .businessError(let message):
            return message
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
