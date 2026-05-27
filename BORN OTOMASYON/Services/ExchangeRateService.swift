import Foundation

struct ExchangeRateService {

    // open.er-api.com — ücretsiz, API anahtarı gerektirmez
    private let url = "https://open.er-api.com/v6/latest/USD"

    func fetchUSDTRY() async -> Double? {
        guard let endpoint = URL(string: url) else { return nil }
        var req = URLRequest(url: endpoint, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        struct Response: Decodable {
            let result: String?
            let rates: [String: Double]
        }

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let resp = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }

        return resp.rates["TRY"]
    }
}
