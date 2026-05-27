import Foundation

// MARK: - NetworkManager
// Tüm HTTP iletişiminden tek sorumlu katman.
// İş mantığı içermez; ham JSON decode eder, APIError fırlatır.

final class NetworkManager {

    static let shared = NetworkManager()
    private init() {}

    // MARK: - Private

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // API farklı formatlarda tarih gönderiyor:
        // "2026-03-24T15:48:50.6439228" (7 haneli kesir)
        // "2026-03-23T05:55:52"         (kesir yok)
        // Kesir kısmını 3 haneye indir, sonra parse et.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            var raw = try container.decode(String.self)

            if let dotIndex = raw.firstIndex(of: ".") {
                let fracStart = raw.index(after: dotIndex)
                let fracPart = raw[fracStart...]
                if fracPart.count > 3 {
                    raw = String(raw[..<fracStart]) + fracPart.prefix(3)
                }
            }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = raw.contains(".") ? "yyyy-MM-dd'T'HH:mm:ss.SSS"
                                                     : "yyyy-MM-dd'T'HH:mm:ss"
            guard let date = formatter.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Tarih çözümlenemedi: \(raw)"
                )
            }
            return date
        }
        return d
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = AppConfig.Timeout.request
        config.timeoutIntervalForResource = AppConfig.Timeout.resource
        return URLSession(configuration: config)
    }()

    // MARK: - GET

    func get<Response: Decodable>(endpoint: String) async throws -> Response {
        let request = try buildRequest(endpoint: endpoint, method: "GET", body: nil as EmptyBody?)
        return try await execute(request)
    }

    // MARK: - POST

    func post<Body: Encodable, Response: Decodable>(
        endpoint: String,
        body: Body
    ) async throws -> Response {
        let request = try buildRequest(endpoint: endpoint, method: "POST", body: body)
        return try await execute(request)
    }

    // MARK: - Private Helpers

    private func buildRequest<Body: Encodable>(
        endpoint: String,
        method: String,
        body: Body?
    ) throws -> URLRequest {
        guard let url = URL(string: AppConfig.baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func execute<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.unknown(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            // DEBUG: Ham yanıtı ve hatayı konsola yaz
            print("=== DECODE HATASI ===")
            print("Ham JSON:", String(data: data, encoding: .utf8) ?? "okunamadı")
            print("Hata:", error)
            print("====================")
            throw APIError.decodingFailed(error)
        }
    }
}

// MARK: - EmptyBody
// POST olmayan isteklerde body tipi için yer tutucu.
private struct EmptyBody: Encodable {}
