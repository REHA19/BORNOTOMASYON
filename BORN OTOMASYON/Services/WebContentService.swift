import Foundation

struct WebContentService {

    // MARK: - Fetch & strip HTML text

    func fetchText(from urlString: String, maxLength: Int = 4000) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        return stripHTML(html, maxLength: maxLength)
    }

    // MARK: - Hammersmith blog — son 3 yazı

    func fetchHammersmithNews() async -> String {
        guard let text = await fetchText(from: "https://hammersmithltd.blogspot.com/", maxLength: 5000) else {
            return "Hammersmith piyasa haberleri alınamadı."
        }
        return "[HAMMERSMITH PİYASA HABERLERİ]\n\(text)"
    }

    // MARK: - Grains.org — haftalık rapor sayfası

    func fetchGrainsReport() async -> String {
        // Try weekly report, fallback to main news page
        let urls = [
            "https://grains.org/markets-tools-data/weekly-export-sales/",
            "https://grains.org/article/weekly-export-sales/",
            "https://grains.org/"
        ]
        for urlStr in urls {
            if let text = await fetchText(from: urlStr, maxLength: 3000), text.count > 200 {
                return "[GRAINS.ORG RAPORU]\n\(text)"
            }
        }
        return "Grains.org raporu alınamadı."
    }

    // MARK: - HTML → plain text

    private func stripHTML(_ html: String, maxLength: Int) -> String {
        var s = html
        s = removeTag("script", from: s)
        s = removeTag("style", from: s)
        s = removeTag("nav", from: s)
        s = removeTag("footer", from: s)
        s = removeTag("header", from: s)

        // Remove tags, keep text
        s = s.replacingOccurrences(of: "<br[^>]*>",  with: "\n",  options: .regularExpression)
        s = s.replacingOccurrences(of: "<p[^>]*>",   with: "\n",  options: .regularExpression)
        s = s.replacingOccurrences(of: "<h[1-6][^>]*>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>",    with: "",    options: .regularExpression)

        // HTML entities
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&laquo;", "«"), ("&raquo;", "»")
        ]
        for (ent, rep) in entities { s = s.replacingOccurrences(of: ent, with: rep) }

        // Collapse whitespace / empty lines
        let lines = s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 20 }  // skip very short lines (menus, buttons)
        s = lines.joined(separator: "\n")

        return String(s.prefix(maxLength))
    }

    private func removeTag(_ tag: String, from html: String) -> String {
        html.replacingOccurrences(
            of: "<\(tag)[\\s\\S]*?</\(tag)>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
