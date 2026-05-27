import Foundation

// MARK: - Parsed data types

struct ParsedRasyon: Identifiable {
    var id: String { code }
    let code:       String
    let name:       String
    let date:       Date?
    let totalKg:    Double
    let ingredients: [ParsedRasyonIngredient]
}

struct ParsedRasyonIngredient: Identifiable {
    let id       = UUID()
    let code:    String
    let name:    String
    let amountKg: Double
    var pct:     Double  // amountKg / totalKg * 100
}

// MARK: - Parser

enum RasyonTXTParser {

    static func parse(url: URL) throws -> [ParsedRasyon] {
        let content = readContent(url: url)
        return parseBlocks(content)
    }

    // MARK: Private

    private static func readContent(url: URL) -> String {
        // 1) UTF-8 — geçersiz sekans varsa nil döner, güvenli
        if let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty {
            return s
        }
        // 2) Windows-1254 (Türkçe) — CFString yolu
        let cfEnc   = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)
        )
        let win1254 = String.Encoding(rawValue: cfEnc)
        if let s = try? String(contentsOf: url, encoding: win1254), !s.isEmpty {
            return s
        }
        // 3) ISO Latin-1 son çare
        return (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
    }

    private static func parseBlocks(_ content: String) -> [ParsedRasyon] {
        var results: [ParsedRasyon] = []

        let blocks = content.components(separatedBy: "***")

        for block in blocks {
            let lines = block
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Minimum: kod, ad, tarih, tonaj, tip
            guard lines.count >= 6 else { continue }

            let code    = lines[0]
            let name    = lines[1]
            let dateStr = lines[2]
            let kgStr   = lines[3]
            // lines[4] → "T" (tip) — atla

            guard !code.isEmpty, !name.isEmpty else { continue }

            let fmt = DateFormatter()
            fmt.locale     = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "dd-MM-yyyy"
            let date = fmt.date(from: dateStr)

            let totalKg = Double(kgStr) ?? 1000.0

            var ingredients: [ParsedRasyonIngredient] = []

            for i in 5..<lines.count {
                let tokens = lines[i]
                    .split(separator: " ", omittingEmptySubsequences: true)
                    .map(String.init)

                guard tokens.count >= 3 else { continue }

                let ingCode   = tokens[0]
                let amountStr = tokens[tokens.count - 1]
                let amountKg  = Double(amountStr) ?? 0.0

                guard amountKg > 0 else { continue }   // sıfır miktarlı hammaddeleri atla

                let ingName = tokens[1..<(tokens.count - 1)].joined(separator: " ")
                let pct     = totalKg > 0 ? (amountKg / totalKg) * 100.0 : 0.0

                ingredients.append(ParsedRasyonIngredient(
                    code:     ingCode,
                    name:     ingName,
                    amountKg: amountKg,
                    pct:      pct
                ))
            }

            guard !ingredients.isEmpty else { continue }

            results.append(ParsedRasyon(
                code:        code,
                name:        name,
                date:        date,
                totalKg:     totalKg,
                ingredients: ingredients
            ))
        }

        return results
    }

    // MARK: → BlendFormula dönüşümü

    static func toBFIngredients(from rasyon: ParsedRasyon) -> [BFIngredient] {
        rasyon.ingredients.map { ing in
            BFIngredient(
                id:                    UUID(),
                code:                  ing.code,
                name:                  ing.name,
                isActive:              true,
                hasStock:              true,
                minPct:                0,
                maxPct:                ing.pct,   // TXT'deki oran → üst sınır
                mixPct:                ing.pct,
                productionMixPct:      ing.pct,
                previousMixPct:        0,
                overridePriceTLPerTon: nil
            )
        }
    }
}
