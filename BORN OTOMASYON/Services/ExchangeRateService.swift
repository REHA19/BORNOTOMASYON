import Foundation

struct ExchangeRateService {

    // open.er-api.com — ücretsiz, API anahtarı gerektirmez
    private let usdURL = "https://open.er-api.com/v6/latest/USD"
    private let eurURL = "https://open.er-api.com/v6/latest/EUR"

    private struct Response: Decodable {
        let result: String?
        let rates: [String: Double]
    }

    func fetchUSDTRY() async -> Double? {
        await fetchRate(urlString: usdURL, target: "TRY")
    }

    func fetchEURTRY() async -> Double? {
        await fetchRate(urlString: eurURL, target: "TRY")
    }

    private func fetchRate(urlString: String, target: String) async -> Double? {
        guard let endpoint = URL(string: urlString) else { return nil }
        var req = URLRequest(url: endpoint, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let resp = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }
        return resp.rates[target]
    }
}
