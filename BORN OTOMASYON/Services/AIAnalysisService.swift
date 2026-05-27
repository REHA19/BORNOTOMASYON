import Foundation

struct MarketContext {
    let marketInfos:    [MaterialMarketInfo]
    let commodities:    [String: CommodityPrice]
    let usdTry:         Double?
    let hammersmithNews:String
    let grainsReport:   String
}

struct AIAnalysisService {

    private let apiURL = "https://api.anthropic.com/v1/messages"
    private let model  = "claude-haiku-4-5-20251001"

    // MARK: - Ana analiz

    func analyze(context: MarketContext, apiKey: String) async -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else {
            return "⚠️ Claude API anahtarı girilmemiş. Piyasa sekmesi → 🔑 butonundan ekleyin."
        }

        let prompt = buildPrompt(context: context)

        do {
            guard let url = URL(string: apiURL) else { return "URL hatası" }
            var req = URLRequest(url: url, timeoutInterval: 90)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let body: [String: Any] = [
                "model":      model,
                "max_tokens": 2000,
                "system":     systemPrompt,
                "messages":   [["role": "user", "content": prompt]]
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)

            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                let raw = String(data: data, encoding: .utf8) ?? ""
                return "API hatası (\(status)):\n\(raw.prefix(400))"
            }

            struct Resp: Decodable {
                struct Block: Decodable { let type: String; let text: String }
                let content: [Block]
            }
            return (try JSONDecoder().decode(Resp.self, from: data)).content.first?.text
                ?? "Yanıt alınamadı."

        } catch {
            return "Analiz hatası: \(error.localizedDescription)"
        }
    }

    // MARK: - System prompt

    private var systemPrompt: String {
        """
        Sen bir yem fabrikası için kıdemli hammadde satın alma danışmanısın.
        Görevin: CBOT/ICE fiyatları, navlun, Türkiye ithalat koşulları (gümrük tarifeleri, \
        TMO politikaları, kur), piyasa haberleri ve fabrika stok durumunu birleştirerek net, \
        uygulanabilir alım önerileri vermek.

        KURALLARIN:
        1. Her malzeme için ayrı ayrı analiz yap
        2. "Al" veya "Bu Hafta Al" önerisinde EN AZ 2 somut gerekçe ver
        3. Haftalık VE aylık trendi mutlaka belirt
        4. Türkiye piyasa fiyat tahmini ver (TL/ton)
        5. Piyasa haberi varsa direkt referans ver ("Hammersmith'e göre...", "Grains.org raporunda...")
        6. Yanıtların Türkçe, maddeli ve kısa olsun
        7. Sonunda 3-4 cümlelik GENEL PIYASA ÖZETI yaz
        """
    }

    // MARK: - Prompt oluşturucu

    private func buildPrompt(context: MarketContext) -> String {
        var parts: [String] = []

        // 1. Tarih & kur
        parts.append("📅 ANALİZ TARİHİ: \(Date().trShort)")
        if let rate = context.usdTry {
            parts.append("💱 USD/TRY: \(String(format: "%.2f", rate)) TL")
        }
        parts.append("")

        // 2. CBOT fiyatları
        if !context.commodities.isEmpty {
            parts.append("📊 CBOT/ICE FIYATLARI (haftalık veri):")
            for (_, price) in context.commodities.sorted(by: { $0.key < $1.key }) {
                var line = "  \(price.displayName): $\(String(format: "%.2f", price.latestPrice))/bushel"
                if let ch = price.changePercent {
                    line += " | Haftalık: \(ch > 0 ? "+" : "")\(String(format: "%.1f", ch))%"
                }
                if let ch3 = price.change3Month {
                    line += " | Aylık: \(ch3 > 0 ? "+" : "")\(String(format: "%.1f", ch3))%"
                }
                parts.append(line)
            }
            parts.append("")
        }

        // 3. Fabrika stok durumu
        parts.append("🏭 FABRİKA HAMMADDE DURUMU:")
        for info in context.marketInfos.sorted(by: { $0.urgency < $1.urgency }) {
            var line = "  \(urgencyIcon(info.urgency)) \(info.material.materialName)"
            if let d = info.stockDays {
                line += " → \(Int(d.rounded())) günlük stok"
            } else {
                line += " → stok süresi hesaplanamadı"
            }
            line += " (net: \(info.material.netStock.kgWholeString))"

            if let mapping = CommodityPriceService.mapping(for: info.material.materialName) {
                line += "\n     Piyasa bağlantısı: \(mapping.relationship)"
                if let rate = context.usdTry,
                   let cbotPrice = context.commodities[mapping.cbotSymbol]?.latestPrice {
                    let turkeyTL = CommodityPriceService.estimateTurkeyPrice(
                        cbotPricePerBushel: cbotPrice,
                        info: mapping,
                        usdTry: rate
                    )
                    line += "\n     Türkiye CIF tahmini: ~\(Int(turkeyTL.rounded(-2))) TL/ton"
                }
            }
            parts.append(line)
        }
        parts.append("")

        // 4. Hammersmith haberleri
        if !context.hammersmithNews.isEmpty && !context.hammersmithNews.contains("alınamadı") {
            parts.append("📰 PİYASA HABERLERİ (Hammersmith):")
            parts.append(String(context.hammersmithNews.prefix(2500)))
            parts.append("")
        }

        // 5. Grains.org raporu
        if !context.grainsReport.isEmpty && !context.grainsReport.contains("alınamadı") {
            parts.append("🌾 TAHIL RAPORU (Grains.org):")
            parts.append(String(context.grainsReport.prefix(2000)))
            parts.append("")
        }

        // 6. İstenen çıktı
        parts.append("""
        ─────────────────────────────
        GÖREV: Yukarıdaki tüm verileri kullanarak aşağıdaki formatta analiz yap:

        [Her hammadde için]:
        ━━ [MALZEME ADI]
        📈 Haftalık Trend: [yön + yüzde]
        📆 Aylık Trend: [yön + yüzde]
        💰 Türkiye Fiyat Tahmini: ~[X.XXX] TL/ton
        🛒 Öneri: [HEMEN AL / BU HAFTA AL / BEKLE / İZLE]
        📋 Gerekçe:
           • [Gerekçe 1 — piyasa/haber bazlı]
           • [Gerekçe 2 — fiyat trendi bazlı]
           • [Gerekçe 3 — stok durumu bazlı, varsa]

        Son olarak:
        📊 GENEL PİYASA ÖZETİ: [3-4 cümle genel değerlendirme]
        """)

        return parts.joined(separator: "\n")
    }

    private func urgencyIcon(_ u: PurchaseUrgency) -> String {
        switch u {
        case .critical:    return "🔴"
        case .warning:     return "🟠"
        case .planning:    return "🟡"
        case .sufficient:  return "🔵"
        case .comfortable: return "🟢"
        case .noData:      return "⚪️"
        }
    }
}

// Double rounding helper
private extension Double {
    func rounded(_ places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
