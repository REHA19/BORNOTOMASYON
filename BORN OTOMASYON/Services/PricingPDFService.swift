import UIKit
import Foundation

// MARK: - BornPDFCanvas Times New Roman uzantısı

extension BornPDFCanvas {

    func drawTimesText(
        _ text:  String,
        in rect: CGRect,
        size:    CGFloat,
        bold:    Bool            = false,
        italic:  Bool            = false,
        color:   UIColor         = .black,
        align:   NSTextAlignment = .left
    ) {
        let fontName: String
        switch (bold, italic) {
        case (true,  true):  fontName = "TimesNewRomanPS-BoldItalicMT"
        case (true,  false): fontName = "TimesNewRomanPS-BoldMT"
        case (false, true):  fontName = "TimesNewRomanPS-ItalicMT"
        default:             fontName = "TimesNewRomanPSMT"
        }
        let font = UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size)
        let ps   = NSMutableParagraphStyle()
        ps.alignment     = align
        ps.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: ps
        ]).draw(in: rect)
    }

    func hline(color: UIColor = UIColor(white: 0.65, alpha: 1), thickness: CGFloat = 0.5) {
        color.setFill()
        UIRectFill(CGRect(x: M, y: y, width: CW, height: thickness))
        y += thickness
    }
}

// MARK: - Yem Bayi Fiyat Listesi PDF — tek sayfa, referans tasarım

struct PricingPDFService {

    struct VadeConfig {
        var tekCekim: Double
        var gun30:    Double
        var gun60:    Double
        var gun90:    Double
    }

    // ── Renkler ──────────────────────────────────────────────────────────
    private static let navy     = UIColor(red: 0.06, green: 0.14, blue: 0.32, alpha: 1)
    private static let groupClr = UIColor(red: 0.69, green: 0.49, blue: 0.16, alpha: 1)
    private static let altRow   = UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)
    private static let hdrTxt   = UIColor.white
    private static let grpTxt   = UIColor.white
    private static let borderClr = UIColor(red: 0.18, green: 0.30, blue: 0.55, alpha: 0.4)

    // ── Sayfa sabitleri ───────────────────────────────────────────────────
    private static let PW:  CGFloat = 595.28   // A4 portrait width
    private static let PH:  CGFloat = 841.89   // A4 portrait height
    private static let ML:  CGFloat = 20.0     // sol/sağ margin

    // ── Sütun genişlikleri ────────────────────────────────────────────────
    // Toplam kullanılabilir: 595.28 - 2×20 = 555.28pt
    private struct Cols {
        let kod:      CGFloat = 50
        let urun:     CGFloat = 140
        let logo:     CGFloat = 38
        let form:     CGFloat = 52
        let protein:  CGFloat = 28
        let pesin:    CGFloat = 57
        let tekCekim: CGFloat = 57
        let gun30:    CGFloat = 45
        let gun60:    CGFloat = 45
        // 90 gün = kalan
        var gun90:    CGFloat { 555.28 - kod - urun - logo - form - protein - pesin - tekCekim - gun30 - gun60 }
        var total:    CGFloat { 555.28 }
    }
    private static let C = Cols()

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Ana üretim
    // ────────────────────────────────────────────────────────────────────

    static func generate(
        rows:        [(formula: BlendFormula, meta: ProductPricingMeta?)],
        ipCuval:     Double, firePct: Double, elektrik: Double,
        nakliye:     Double, iscilik: Double, globalKarPct: Double,
        vade:        VadeConfig,
        period:      String
    ) -> Data {

        // 1. Satırları hazırla
        let visible = rows.filter { $0.meta?.isVisible ?? true }
            .compactMap { formula, meta -> RowData? in
                let rasyon = formula.currentCostTL > 0 ? formula.currentCostTL : formula.recordedCostTL
                guard rasyon > 0 else { return nil }
                let effKar = (meta?.overrideKarPct ?? -1) >= 0 ? meta!.overrideKarPct : globalKarPct
                let bagKg  = meta?.bagKg ?? 50
                let calc   = PricingCalc.calculate(
                    rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                    elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                    karPct: effKar, bagKg: bagKg
                )
                let protein = formula.lastSolve?.nutrientValues["crudeProtein"]
                    ?? formula.constraints.first { $0.nutrientKey == "crudeProtein" }?.currentValue
                return RowData(
                    kod:       formula.code,
                    name:      formula.name,
                    form:      meta?.form ?? "Pelet",
                    protein:   protein,
                    logoName:  meta?.logoName ?? "",
                    category:  meta?.categoryGroup ?? "",
                    orderIdx:  meta?.orderIndex ?? 999,
                    calc:      calc
                )
            }
            .sorted { lhs, rhs in
                if lhs.category != rhs.category { return lhs.category < rhs.category }
                return lhs.orderIdx < rhs.orderIdx
            }

        // 2. Satır yüksekliğini hesapla — TEK SAYFAYA SIĞACAK ŞEKİLDE
        let uniqueGroups = Set(visible.map { $0.category }).filter { !$0.isEmpty }.count
        let totalLines   = visible.count + uniqueGroups
        let fixedH: CGFloat = 62 + 22 + 4 + 32 + 18 + 20 + 38  // banner+addr+gap+info+title+tableHdr+footer
        let available    = PH - 2 * ML - fixedH
        let rowH:  CGFloat = totalLines > 0 ? max(9.5, min(13.0, available / CGFloat(totalLines))) : 11.0
        let grpH:  CGFloat = rowH + 1.0
        let fSz:   CGFloat = rowH <= 10.0 ? 6.3 : (rowH <= 11.5 ? 6.8 : 7.3)

        // 3. PDF render
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: PW, height: PH)
        )
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var curY: CGFloat = 0

            // ── Header banner ──────────────────────────────────────────
            curY = drawBanner(y: curY)

            // ── Adres şeridi ───────────────────────────────────────────
            curY = drawAddressBar(y: curY)

            // ── Bilgi + Başlık ─────────────────────────────────────────
            curY = drawInfoAndTitle(y: curY, period: period)

            // ── Tablo başlığı ──────────────────────────────────────────
            curY = drawTableHeader(y: curY, height: 20)

            // ── Ürün satırları ─────────────────────────────────────────
            curY = drawProducts(y: curY, rows: visible, rowH: rowH, grpH: grpH,
                                fSz: fSz, vade: vade)

            // ── Footer ─────────────────────────────────────────────────
            drawFooter(y: curY, fSz: fSz)
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Header Banner (~62pt)
    // ────────────────────────────────────────────────────────────────────

    @discardableResult
    private static func drawBanner(y: CGFloat) -> CGFloat {
        let H: CGFloat = 62
        // Lacivert zemin
        navy.setFill(); UIRectFill(CGRect(x: 0, y: y, width: PW, height: H))

        // ── Sol: Alapala Yem logosu ───────────────────────────────────
        let logoW: CGFloat = PW * 0.50
        if let img = UIImage(named: "AlapalaYemLogo") {
            let imgH = H - 8
            let imgW = imgH * img.size.width / img.size.height
            img.draw(in: CGRect(x: ML, y: y + 4, width: imgW, height: imgH))
        } else {
            // Metin tabanlı fallback: beyaz kutu + "A" + "Alapala Yem"
            let boxSz: CGFloat = H - 14
            UIColor.white.withAlphaComponent(0.12).setFill()
            UIRectFill(CGRect(x: ML, y: y + 7, width: boxSz, height: boxSz))
            drawT("A", CGRect(x: ML, y: y + 7, width: boxSz, height: boxSz),
                  sz: boxSz * 0.6, bold: true, clr: .white, align: .center)
            drawT("Alapala Yem",
                  CGRect(x: ML + boxSz + 8, y: y + H * 0.22, width: logoW - boxSz - 16, height: H * 0.35),
                  sz: 14, bold: true, clr: .white)
        }

        // ── Sağ: Hayvan logoları ──────────────────────────────────────
        if let img = UIImage(named: "AlapalaHayvanLogolari") {
            let imgH = H - 8
            let imgW = imgH * img.size.width / img.size.height
            img.draw(in: CGRect(x: PW - ML - imgW, y: y + 4, width: imgW, height: imgH))
        } else {
            // Üç renkli daire
            let diam:  CGFloat = H * 0.72
            let gap:   CGFloat = 6
            let totalW = diam * 3 + gap * 2
            var cx = PW - ML - totalW + diam / 2
            let cy = y + H / 2
            let halves: [(UIColor, String, String)] = [
                (UIColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 0.90), "KUZU", "YEMİ"),
                (UIColor(red: 0.85, green: 0.45, blue: 0.05, alpha: 0.90), "İNEK", "YEMİ"),
                (UIColor(red: 0.12, green: 0.40, blue: 0.75, alpha: 0.90), "BESİ", "YEMİ"),
            ]
            for (clr, l1, l2) in halves {
                let oval = CGRect(x: cx - diam/2, y: cy - diam/2, width: diam, height: diam)
                clr.setFill(); UIBezierPath(ovalIn: oval).fill()
                UIColor.white.withAlphaComponent(0.25).setFill()
                UIBezierPath(ovalIn: oval.insetBy(dx: 2, dy: 2)).stroke()
                drawT(l1, CGRect(x: cx - diam/2, y: cy - diam * 0.30, width: diam, height: diam * 0.28),
                      sz: 5.5, bold: true, clr: .white, align: .center)
                drawT(l2, CGRect(x: cx - diam/2, y: cy + diam * 0.00, width: diam, height: diam * 0.28),
                      sz: 5.5, bold: true, clr: .white, align: .center)
                cx += diam + gap
            }
        }

        return y + H
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Adres Şeridi (~22pt)
    // ────────────────────────────────────────────────────────────────────

    private static func drawAddressBar(y: CGFloat) -> CGFloat {
        let H: CGFloat = 22
        UIColor(white: 1.0, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: y, width: PW, height: H))
        UIColor(white: 0.78, alpha: 1).setFill(); UIRectFill(CGRect(x: 0, y: y + H - 0.5, width: PW, height: 0.5))

        let baseY = y + 3
        let fSz: CGFloat = 6.5
        // Sol: adres + tel
        drawT("⊙ Ankara Yolu 7. Km, 19100 Merkez / ÇORUM   T.(+90) 364 235 00 34",
              CGRect(x: ML, y: baseY, width: PW * 0.50, height: 8), sz: fSz, clr: UIColor(white: 0.22, alpha: 1))
        // Sağ: web + mail
        drawT("⊕ www.alboas.com.tr   ✉ info@alboas.com.tr",
              CGRect(x: ML + PW * 0.45, y: baseY, width: PW * 0.45, height: 8), sz: fSz,
              clr: UIColor(white: 0.22, alpha: 1), align: .right)

        return y + H
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Bilgi Bloğu + Başlık (~50pt)
    // ────────────────────────────────────────────────────────────────────

    private static func drawInfoAndTitle(y: CGFloat, period: String) -> CGFloat {
        var curY = y + 4

        // Sağ: Değerli Müşterilerimiz
        let rightX = ML + C.total * 0.50
        let rightW = C.total * 0.50
        let df = DateFormatter(); df.locale = Locale(identifier: "tr_TR"); df.dateFormat = "dd.MM.yyyy"
        let dateStr = period.isEmpty ? df.string(from: Date()) : period

        drawT("Değerli Müşterilerimiz,",
              CGRect(x: rightX, y: curY, width: rightW, height: 9),
              sz: 7, bold: true, clr: UIColor(white: 0.20, alpha: 1))
        drawT("\(dateStr) tarihinden itibaren geçerli yem fiyatları aşağıda belirtilmiştir.",
              CGRect(x: rightX, y: curY + 9, width: rightW, height: 8), sz: 6.5, clr: UIColor(white: 0.28, alpha: 1))
        drawT("Bilgilerinize sunar hayırlı işler dileriz.",
              CGRect(x: rightX, y: curY + 17, width: rightW, height: 8), sz: 6.5, clr: UIColor(white: 0.28, alpha: 1))
        // Dönem (sağ)
        drawT(period, CGRect(x: rightX, y: curY + 25, width: rightW, height: 8),
              sz: 6.5, clr: UIColor(white: 0.35, alpha: 1), align: .right)

        curY += 32

        // ── Başlık ─────────────────────────────────────────────────────
        // Orta-sol: "YEM BAYİ FİYAT LİSTESİ"
        drawT("YEM BAYİ FİYAT LİSTESİ",
              CGRect(x: ML, y: curY, width: C.total * 0.70, height: 18),
              sz: 14, bold: true, clr: UIColor(red: 0.06, green: 0.14, blue: 0.32, alpha: 1))
        // Sağ: "Saygılarımızla."
        drawT("Saygılarımızla.",
              CGRect(x: ML + C.total * 0.60, y: curY + 5, width: C.total * 0.40, height: 12),
              sz: 7.5, bold: true, italic: true, clr: UIColor(white: 0.30, alpha: 1), align: .right)

        curY += 18
        // Alt çizgi
        navy.withAlphaComponent(0.6).setFill()
        UIRectFill(CGRect(x: ML, y: curY, width: C.total, height: 0.8))
        curY += 4
        return curY
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Tablo Başlığı
    // ────────────────────────────────────────────────────────────────────

    private static func drawTableHeader(y: CGFloat, height: CGFloat) -> CGFloat {
        // Zemin
        navy.setFill(); UIRectFill(CGRect(x: ML, y: y, width: C.total, height: height))

        let fSz: CGFloat = 6.5
        let vP:  CGFloat = 2
        var x    = ML + 3
        let hCells: [(String, CGFloat, NSTextAlignment)] = [
            ("KOD",                  C.kod,      .center),
            ("YEM CİNSLERİ",         C.urun,     .left),
            ("LOGO",                 C.logo,     .center),
            ("Form",                 C.form,     .center),
            ("Protein",              C.protein,  .center),
            ("Peşin",                C.pesin,    .center),
            ("Tek Çekim\nKredi Kartı", C.tekCekim, .center),
            ("30 gün\nvadeli",       C.gun30,    .center),
            ("60 gün\nvadeli",       C.gun60,    .center),
            ("90 gün\nvadeli",       C.gun90,    .center),
        ]
        for (txt, w, align) in hCells {
            drawT(txt, CGRect(x: x, y: y + vP, width: w - 4, height: height - vP * 2),
                  sz: fSz, bold: true, clr: .white, align: align)
            x += w
        }
        // Sütun ayraçları
        x = ML + C.kod
        for w in [C.urun, C.logo, C.form, C.protein, C.pesin, C.tekCekim, C.gun30, C.gun60] {
            UIColor(white: 1, alpha: 0.20).setFill()
            UIRectFill(CGRect(x: x, y: y + 3, width: 0.4, height: height - 5))
            x += w
        }
        return y + height
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Ürün Satırları
    // ────────────────────────────────────────────────────────────────────

    private static func drawProducts(
        y:     CGFloat,
        rows:  [RowData],
        rowH:  CGFloat,
        grpH:  CGFloat,
        fSz:   CGFloat,
        vade:  VadeConfig
    ) -> CGFloat {
        var curY   = y
        var lastGrp = ""
        var rowIdx  = 0

        for row in rows {
            // Grup başlığı
            let grp = row.category.trimmingCharacters(in: .whitespaces)
            if !grp.isEmpty && grp != lastGrp {
                lastGrp = grp
                groupBg  = UIColor(red: 0.69, green: 0.49, blue: 0.16, alpha: 1)
                groupBg.setFill(); UIRectFill(CGRect(x: ML, y: curY, width: C.total, height: grpH))
                drawT(grp, CGRect(x: ML + 3, y: curY + (grpH - fSz - 1) / 2, width: C.total - 6, height: fSz + 2),
                      sz: fSz, bold: true, clr: .white)
                curY  += grpH
                rowIdx = 0
            }

            // Ürün satırı arka plan
            let bg = rowIdx % 2 == 0 ? UIColor.white : altRow
            bg.setFill(); UIRectFill(CGRect(x: ML, y: curY, width: C.total, height: rowH))

            // Fiyatlar
            let pesin    = row.calc.pesin
            let tekCekim = row.calc.vadePrice(pct: vade.tekCekim)
            let gun30    = row.calc.vadePrice(pct: vade.gun30)
            let gun60    = row.calc.vadePrice(pct: vade.gun60)
            let gun90    = row.calc.vadePrice(pct: vade.gun90)

            let vP:  CGFloat = max(1.0, (rowH - fSz) / 2 - 0.5)
            let tY   = curY + vP
            let tH   = rowH - vP * 2

            var x = ML + 3
            // KOD
            drawT(row.kod, CGRect(x: x, y: tY, width: C.kod - 4, height: tH),
                  sz: fSz, bold: true, clr: UIColor(red: 0.06, green: 0.14, blue: 0.32, alpha: 1), align: .center)
            x += C.kod
            // Ürün adı
            drawT(row.name, CGRect(x: x, y: tY, width: C.urun - 4, height: tH), sz: fSz, bold: true)
            x += C.urun
            // Logo
            if !row.logoName.isEmpty, let img = UIImage(named: row.logoName) {
                let logoH = rowH - 2
                let logoW = logoH * img.size.width / img.size.height
                let logoX = x + (C.logo - logoW) / 2
                img.draw(in: CGRect(x: logoX, y: curY + 1, width: logoW, height: logoH))
            }
            x += C.logo
            // Form
            drawT(row.form, CGRect(x: x, y: tY, width: C.form - 4, height: tH),
                  sz: fSz, align: .center)
            x += C.form
            // Protein
            drawT(protStr(row.protein), CGRect(x: x, y: tY, width: C.protein - 2, height: tH),
                  sz: fSz, align: .center)
            x += C.protein
            // Fiyatlar
            for (val, w) in [(pesin, C.pesin), (tekCekim, C.tekCekim), (gun30, C.gun30), (gun60, C.gun60), (gun90, C.gun90)] {
                drawT(priceFmt(val), CGRect(x: x + 1, y: tY, width: w - 4, height: tH),
                      sz: fSz, align: .right)
                x += w
            }

            // İnce alt çizgi
            UIColor(white: 0.80, alpha: 1).setFill()
            UIRectFill(CGRect(x: ML, y: curY + rowH - 0.3, width: C.total, height: 0.3))

            // Sütun ayraçları
            x = ML + C.kod
            for w in [C.urun, C.logo, C.form, C.protein, C.pesin, C.tekCekim, C.gun30, C.gun60] {
                UIColor(white: 0.72, alpha: 0.5).setFill()
                UIRectFill(CGRect(x: x, y: curY + 1.5, width: 0.3, height: rowH - 3))
                x += w
            }

            curY  += rowH
            rowIdx += 1
        }

        return curY
    }

    // Grup rengi için geçici değişken
    private static var groupBg = UIColor(red: 0.69, green: 0.49, blue: 0.16, alpha: 1)

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Footer
    // ────────────────────────────────────────────────────────────────────

    private static func drawFooter(y: CGFloat, fSz: CGFloat) {
        var curY = y + 4
        // Üst çizgi
        UIColor(white: 0.55, alpha: 1).setFill()
        UIRectFill(CGRect(x: ML, y: curY, width: C.total, height: 0.6))
        curY += 5

        let lH = fSz + 2.5
        drawT("Her zam geçişlerinde içerideki siparişler güncel fiyattan faturalanacaktır.",
              CGRect(x: ML, y: curY, width: C.total * 0.74, height: lH), sz: fSz, clr: UIColor(white: 0.25, alpha: 1))
        curY += lH
        drawT("Pancar Küspesi Satışlarımız Peşindir. GÜNCEL FİYAT ALINIZ",
              CGRect(x: ML, y: curY, width: C.total * 0.74, height: lH), sz: fSz, bold: true, clr: .red)
        curY += lH
        drawT("Fiyatlarda KDV dahildir.(KDV % 0 'dır. 10.02.2016 itibari ile)",
              CGRect(x: ML, y: curY, width: C.total * 0.74, height: lH), sz: fSz, clr: UIColor(white: 0.25, alpha: 1))

        // ALBO AŞ kutusu — sağ alt
        let boxW: CGFloat = 75; let boxH: CGFloat = lH * 2.5
        let boxX = ML + C.total - boxW
        let boxY = y + 5
        navy.setFill(); UIRectFill(CGRect(x: boxX, y: boxY, width: boxW, height: boxH))
        // Logo varsa çiz
        if let img = UIImage(named: "AlboLogo") {
            img.draw(in: CGRect(x: boxX + 4, y: boxY + 3, width: boxW - 8, height: boxH - 6))
        } else {
            drawT("ALBO AŞ",    CGRect(x: boxX, y: boxY + boxH * 0.15, width: boxW, height: boxH * 0.38),
                  sz: fSz + 1, bold: true, clr: .white, align: .center)
            drawT("kuruluşudur.", CGRect(x: boxX, y: boxY + boxH * 0.55, width: boxW, height: boxH * 0.32),
                  sz: fSz - 0.5, clr: UIColor(white: 0.82, alpha: 1), align: .center)
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Yardımcı — drawT (kısa isim)
    // ────────────────────────────────────────────────────────────────────

    private static func drawT(
        _ text:  String,
        _ rect:  CGRect,
        sz:      CGFloat,
        bold:    Bool            = false,
        italic:  Bool            = false,
        clr:     UIColor         = .black,
        align:   NSTextAlignment = .left
    ) {
        let fontName: String
        switch (bold, italic) {
        case (true,  true):  fontName = "TimesNewRomanPS-BoldItalicMT"
        case (true,  false): fontName = "TimesNewRomanPS-BoldMT"
        case (false, true):  fontName = "TimesNewRomanPS-ItalicMT"
        default:             fontName = "TimesNewRomanPSMT"
        }
        let font = UIFont(name: fontName, size: sz) ?? UIFont.systemFont(ofSize: sz)
        let ps   = NSMutableParagraphStyle()
        ps.alignment = align; ps.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: clr, .paragraphStyle: ps
        ]).draw(in: rect)
    }

    private static func priceFmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.locale = Locale(identifier: "tr_TR")
        n.numberStyle = .decimal
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    private static func protStr(_ p: Double?) -> String {
        guard let p, p > 0 else { return "—" }
        return String(format: "%.0f", p)
    }

    static func writeToTemp(data: Data, filename: String = "FiyatListesi") -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename).pdf")
        return (try? data.write(to: url)) == nil ? nil : url
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Satır verisi
    // ────────────────────────────────────────────────────────────────────

    private struct RowData {
        let kod:      String
        let name:     String
        let form:     String
        let protein:  Double?
        let logoName: String
        let category: String
        let orderIdx: Int
        let calc:     PricingCalc
    }
}
