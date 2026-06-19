import Foundation

// MARK: - MultiBlend formül aktarım (transfer) parser
// MultiBlendExportService.generateTransferTXT() ile üretilen kayıpsız formatı okur:
// her formül kod/ad/hammadde min-max-mix oranları ve besin değeri kriterleriyle
// birlikte taşınır. RasyonImportView aynı dosya seçici üzerinden bu formatı da
// otomatik tanır (canParse) ve ParsedRasyon'a dönüştürür.

enum MultiBlendTransferParser {

    static func canParse(_ content: String) -> Bool {
        content.contains("@@@FORMUL@@@")
    }

    // Dosyayı tüm encoding fallback'leriyle (utf8 → windows-1254 → latin1) okuyup
    // kontrol eder. Sadece utf8 ile önizleme yapmak yanlış sonuca yol açar:
    // transfer (WhatsApp/AirDrop/e-posta) sırasında dosyada tek bir geçersiz utf8
    // baytı olsa bile String(contentsOf:encoding:.utf8) TÜM içeriği nil döndürür —
    // bu da yeni formatın tanınamayıp eski "***" parser'ına yanlışlıkla düşmesine
    // ve formüllerin tek bloğa karışıp çökmeye sebep olmasına yol açıyordu.
    static func canParse(url: URL) -> Bool {
        canParse(readContent(url: url))
    }

    static func parse(url: URL) -> [ParsedRasyon] {
        parseBlocks(readContent(url: url))
    }

    // MARK: Private

    private static func readContent(url: URL) -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty {
            return s
        }
        let cfEnc   = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)
        )
        let win1254 = String.Encoding(rawValue: cfEnc)
        if let s = try? String(contentsOf: url, encoding: win1254), !s.isEmpty {
            return s
        }
        return (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
    }

    private static func parseBlocks(_ content: String) -> [ParsedRasyon] {
        var results: [ParsedRasyon] = []
        let blocks = content.components(separatedBy: "@@@FORMUL@@@").dropFirst()

        for raw in blocks {
            let block = raw.components(separatedBy: "@@@SON@@@").first ?? raw
            let lines = block
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            var code = ""
            var name = ""
            var totalKg = 1000.0
            var bfIngs: [BFIngredient] = []
            var constraints: [BFConstraint] = []
            var section = 0   // 0 = başlık, 1 = hammadde, 2 = besin

            for line in lines {
                if line.isEmpty { continue }
                if line == "---HAMMADDE---" { section = 1; continue }
                if line == "---BESIN---"    { section = 2; continue }
                if line.hasPrefix("KOD:")             { code = value(line); continue }
                if line.hasPrefix("AD:")              { name = value(line); continue }
                if line.hasPrefix("TOPLAM_KG:")        { totalKg = Double(value(line)) ?? 1000; continue }
                if line.hasPrefix("HAMMADDE_SAYISI:")  { continue }
                if line.hasPrefix("KOD|AD|")           { continue }   // sütun başlığı
                if line.hasPrefix("ANAHTAR|")          { continue }   // sütun başlığı

                let parts = line.components(separatedBy: "|")
                if section == 1, parts.count >= 8 {
                    bfIngs.append(BFIngredient(
                        code: parts[0], name: parts[1], isActive: parts[2] == "1",
                        minPct: Double(parts[3]) ?? 0, maxPct: Double(parts[4]) ?? 100,
                        mixPct: Double(parts[5]) ?? 0, productionMixPct: Double(parts[6]) ?? 0,
                        overridePriceTLPerTon: parts[7].isEmpty ? nil : Double(parts[7])
                    ))
                } else if section == 2, parts.count >= 6 {
                    constraints.append(BFConstraint(
                        nutrientKey: parts[0], displayName: parts[1], unit: parts[2],
                        minValue: parts[3].isEmpty ? nil : Double(parts[3]),
                        maxValue: parts[4].isEmpty ? nil : Double(parts[4]),
                        currentValue: parts[5].isEmpty ? nil : Double(parts[5])
                    ))
                }
            }

            guard !code.isEmpty, !name.isEmpty, !bfIngs.isEmpty else { continue }

            let displayIngs = bfIngs.map { ing in
                ParsedRasyonIngredient(
                    code: ing.code, name: ing.name,
                    amountKg: ing.mixPct * totalKg / 100.0, pct: ing.mixPct
                )
            }

            results.append(ParsedRasyon(
                code: code, name: name, date: nil, totalKg: totalKg,
                ingredients: displayIngs, fullIngredients: bfIngs, constraints: constraints
            ))
        }

        return results
    }

    private static func value(_ line: String) -> String {
        guard let idx = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
    }
}
