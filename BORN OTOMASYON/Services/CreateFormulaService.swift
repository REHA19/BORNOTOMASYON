import Foundation

struct CreateFormulaService {
    func create(model: FormulaCreateAppModel) async throws -> FormulaCreateResponse {
        guard let url = URL(string: AppConfig.baseURL + AppConfig.Endpoint.createFormula) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: AppConfig.Timeout.request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(model)

        print("[CreateFormula] POST \(url)")
        if let body = request.httpBody, let str = String(data: body, encoding: .utf8) {
            print("[CreateFormula] body: \(str.prefix(600))")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            print("[CreateFormula] status: \(http.statusCode)")
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        print("[CreateFormula] raw: \(raw.prefix(600))")

        if let result = try? JSONDecoder().decode(FormulaCreateResponse.self, from: data) {
            // Sunucu success:false dönerse hata olarak fırlat
            if !result.success {
                let msg = result.message ?? "Sunucu isteği reddetti."
                throw NSError(domain: "CreateFormula", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            return result
        }

        // Sunucu düz string döndürüyorsa başarı say
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            return FormulaCreateResponse(success: true, message: raw.isEmpty ? nil : raw)
        }

        throw NSError(domain: "CreateFormula", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Beklenmeyen yanıt:\n\(raw.prefix(400))"])
    }
}
