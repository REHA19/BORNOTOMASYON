import Foundation

// MARK: - Material → Commodity mapping

struct MaterialCommodityInfo {
    let cbotSymbol:   String   // CORN / WHEAT
    let displayName:  String   // Türkçe görünen ad
    let relationship: String   // Fiyat ilişkisi açıklaması
    // CIF Turkey estimate = CBOT $/ton × tryRate + freightTRY
    let cbotTonFactor: Double  // $/bushel → $/ton çevirme katsayısı
    let freightUSD:    Double  // Tahmini navlun + gümrük $/ton
    let priceFactor:   Double  // CBOT'a göre relatif fiyat çarpanı
}

struct CommodityPriceService {

    private let baseURL = "https://www.alphavantage.co/query"

    // MARK: - Fabrika malzeme → CBOT eşleşme tablosu
    // (materialFragment içinde geçen alt string → bilgi)

    static let materialMappings: [(fragment: String, info: MaterialCommodityInfo)] = [
        // ---- MISIR bazlı ----
        ("MISIR KEP",  MaterialCommodityInfo(
            cbotSymbol: "CORN", displayName: "Mısır Kepeği",
            relationship: "Mısır yan ürünü, CBOT mısırın %25-35'i (lokal piyasa)",
            cbotTonFactor: 39.37, freightUSD: 0, priceFactor: 0.30)),

        ("MISIR GLUTEN", MaterialCommodityInfo(
            cbotSymbol: "CORN", displayName: "Mısır Gluteni 60",
            relationship: "Yüksek proteinli mısır ürünü, CBOT mısırın ~%180'i",
            cbotTonFactor: 39.37, freightUSD: 20, priceFactor: 1.80)),

        ("D.D.G.S",    MaterialCommodityInfo(
            cbotSymbol: "CORN", displayName: "DDGS",
            relationship: "Mısır yan ürünü, ABD CBOT mısırın %90-95'i + navlun $35-45",
            cbotTonFactor: 39.37, freightUSD: 40, priceFactor: 0.92)),

        ("MISIR",      MaterialCommodityInfo(
            cbotSymbol: "CORN", displayName: "Mısır",
            relationship: "CBOT ZC vadeli fiyat + Karadeniz navlun ~$35/ton",
            cbotTonFactor: 39.37, freightUSD: 35, priceFactor: 1.00)),

        // ---- BUĞDAY bazlı ----
        ("KEPEK",      MaterialCommodityInfo(
            cbotSymbol: "WHEAT", displayName: "Buğday Kepeği",
            relationship: "TMO buğday fiyatının %35-42'si, Türkiye içi piyasa belirleyici",
            cbotTonFactor: 36.74, freightUSD: 0, priceFactor: 0.38)),

        ("ARPA",       MaterialCommodityInfo(
            cbotSymbol: "WHEAT", displayName: "Arpa",
            relationship: "CBOT buğdayın %80-88'i, Rusya/Ukrayna ihracat fiyatı belirleyici",
            cbotTonFactor: 36.74, freightUSD: 30, priceFactor: 0.84)),

        ("BUGDAY",     MaterialCommodityInfo(
            cbotSymbol: "WHEAT", displayName: "Buğday Kırığı",
            relationship: "CBOT ZW buğday fiyatı + navlun; Türkiye'de TMO ve ithalat fiyatına bağlı",
            cbotTonFactor: 36.74, freightUSD: 30, priceFactor: 1.00)),

        ("PIRINC",     MaterialCommodityInfo(
            cbotSymbol: "WHEAT", displayName: "Kırık Pirinç",
            relationship: "Buğday ile korelasyon yüksek, Asya piyasası da etkili",
            cbotTonFactor: 36.74, freightUSD: 50, priceFactor: 1.10)),

        // ---- SOYA bazlı ----
        ("SOYA FAS",   MaterialCommodityInfo(
            cbotSymbol: "WHEAT", displayName: "Soya Fasulyesi",
            relationship: "CBOT Soya (tahminen buğdayın ~2.1 katı), Chicago CME ZS",
            cbotTonFactor: 36.74, freightUSD: 45, priceFactor: 2.10)),

        ("SOYA KUS",   MaterialCommodityInfo(
            cbotSymbol: "WHEAT", displayName: "Soya Küspesi",
            relationship: "Soya fasulyesinin %75-80'i, yüksek protein → premium fiyat",
            cbotTonFactor: 36.74, freightUSD: 45, priceFactor: 1.95)),

        ("SOYA",       MaterialCommodityInfo(
            cbotSymbol: "WHEAT", displayName: "Soya",
            relationship: "Soya bazlı ürün — buğday fiyatı ile ilişkili proxy",
            cbotTonFactor: 36.74, freightUSD: 45, priceFactor: 2.00)),

        // ---- ŞEKER bazlı ----
        ("MELAS",      MaterialCommodityInfo(
            cbotSymbol: "SUGAR", displayName: "Melas",
            relationship: "Şeker pancarı yan ürünü, şeker fiyatına bağlı",
            cbotTonFactor: 22.04, freightUSD: 0, priceFactor: 0.35)),

        ("SEKER PANC", MaterialCommodityInfo(
            cbotSymbol: "SUGAR", displayName: "Şeker Pancarı Posası",
            relationship: "Yerel şeker fabrikaları yan ürünü, dünya şekerinden etkilenir",
            cbotTonFactor: 22.04, freightUSD: 0, priceFactor: 0.25)),

        // ---- PAMUK / AYÇİÇEK ----
        ("AYCI",       MaterialCommodityInfo(
            cbotSymbol: "COTTON", displayName: "Ayçiçeği Küspesi / Kabuğu",
            relationship: "Küresel ayçiçeği piyasası, Ukrayna ihracatından etkilenir",
            cbotTonFactor: 2.205, freightUSD: 25, priceFactor: 0.55)),
    ]

    // MARK: - Fragment eşleştirme (normalize edilmiş)

    static func mapping(for materialName: String) -> MaterialCommodityInfo? {
        let n = normalize(materialName)
        for (fragment, info) in materialMappings {
            if n.contains(normalize(fragment)) { return info }
        }
        return nil
    }

    // MARK: - Fabrika malzemesi → CBOT sembolü

    static func symbol(for materialName: String) -> String? {
        mapping(for: materialName)?.cbotSymbol
    }

    // MARK: - Türkiye CIF fiyat tahmini (TL/ton)

    static func estimateTurkeyPrice(cbotPricePerBushel: Double,
                                    info: MaterialCommodityInfo,
                                    usdTry: Double) -> Double {
        let cbotPerTon  = cbotPricePerBushel * info.cbotTonFactor
        let cifUSD      = (cbotPerTon + info.freightUSD) * info.priceFactor
        return cifUSD * usdTry
    }

    // MARK: - Tüm semboller

    static let allSymbols = ["CORN", "WHEAT", "SUGAR", "COTTON"]

    static func displayName(for symbol: String) -> String {
        switch symbol {
        case "CORN":   return "Mısır (CBOT ZC)"
        case "WHEAT":  return "Buğday (CBOT ZW)"
        case "SUGAR":  return "Şeker (ICE)"
        case "COTTON": return "Pamuk (ICE)"
        default:       return symbol
        }
    }

    // MARK: - Fetch all

    func fetchAll(apiKey: String) async -> [String: CommodityPrice] {
        guard !apiKey.isEmpty else { return [:] }
        var result: [String: CommodityPrice] = [:]
        await withTaskGroup(of: (String, CommodityPrice?)?.self) { group in
            for symbol in Self.allSymbols {
                group.addTask { [symbol] in
                    guard let p = await self.fetch(symbol: symbol, apiKey: apiKey) else { return nil }
                    return (symbol, p)
                }
            }
            for await pair in group {
                if let (sym, price) = pair { result[sym] = price }
            }
        }
        return result
    }

    func fetch(symbol: String, apiKey: String) async -> CommodityPrice? {
        guard let url = URL(string: "\(baseURL)?function=\(symbol)&interval=weekly&apikey=\(apiKey)") else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            if let note = (try? JSONDecoder().decode(AVNote.self, from: data))?.note,
               note.lowercased().contains("api") { return nil }

            let decoded = try JSONDecoder().decode(CommodityResponse.self, from: data)
            let valid = Array(decoded.data.compactMap { p -> CommodityDataPoint? in
                guard let v = p.doubleValue, v > 0 else { return nil }
                return p
            }.prefix(12))  // son 12 hafta

            guard let latest = valid.first?.doubleValue else { return nil }

            return CommodityPrice(
                id:            symbol,
                symbol:        symbol,
                displayName:   Self.displayName(for: symbol),
                unit:          decoded.unit,
                latestPrice:   latest,
                previousPrice: valid.dropFirst().first?.doubleValue,
                points:        valid
            )
        } catch {
            print("[Commodity] \(symbol):", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Helper

    static func normalize(_ s: String) -> String {
        s.uppercased()
            .replacingOccurrences(of: "İ", with: "I")
            .replacingOccurrences(of: "Ş", with: "S")
            .replacingOccurrences(of: "Ğ", with: "G")
            .replacingOccurrences(of: "Ç", with: "C")
            .replacingOccurrences(of: "Ö", with: "O")
            .replacingOccurrences(of: "Ü", with: "U")
    }
}

private struct AVNote: Decodable {
    let note: String?
    enum CodingKeys: String, CodingKey { case note = "Note" }
}
