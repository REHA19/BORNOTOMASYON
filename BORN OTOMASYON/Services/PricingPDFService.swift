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

// MARK: - Yem Bayi Fiyat Listesi PDF

struct PricingPDFService {

    struct VadeConfig {
        var tekCekim: Double
        var gun30:    Double
        var gun60:    Double
        var gun90:    Double
    }

    // ── Sabit kategori sırası (PDF'de bu sırayla çıkar) ──────────────────
    private static let categoryOrder: [String] = [
        "SIĞIR SÜT YEMLERİ( 50 kg)",
        "SIĞIR BESİ YEMLERİ( 50 kg)",
        "SIĞIR BESİ TOZ YEMLERİ( 50 kg)",
        "KUZU TOKLU YEMLERİ( 50 kg)",
        "BUZAĞI YEMLERİ( 40-50 kg)",
        "ÖZEL YEMLER( 50 kg)",
        "KANATLI YEMLERİ ( 50 KG)",
    ]

    private static func categoryRank(_ cat: String) -> Int {
        categoryOrder.firstIndex(of: cat) ?? 999
    }

    // ── Renkler ──────────────────────────────────────────────────────────
    private static let navyDark  = UIColor(red: 0.03, green: 0.10, blue: 0.30, alpha: 1)
    private static let navyMid   = UIColor(red: 0.06, green: 0.18, blue: 0.52, alpha: 1)
    private static let navyLight = UIColor(red: 0.10, green: 0.25, blue: 0.62, alpha: 1)
    private static let groupClr  = UIColor(red: 0.69, green: 0.49, blue: 0.16, alpha: 1)
    private static let altRow    = UIColor(red: 0.95, green: 0.96, blue: 0.99, alpha: 1)
    private static let borderClr = UIColor(red: 0.18, green: 0.30, blue: 0.55, alpha: 0.35)

    // ── Sayfa sabitleri ───────────────────────────────────────────────────
    private static let PW: CGFloat = 595.28
    private static let PH: CGFloat = 841.89
    private static let ML: CGFloat = 22.0

    // ── Sütun genişlikleri (toplam = PW - 2*ML = 551.28) ─────────────────
    private struct Cols {
        let kod:      CGFloat = 48
        let urun:     CGFloat = 138
        let logo:     CGFloat = 36
        let form:     CGFloat = 50
        let protein:  CGFloat = 27
        let pesin:    CGFloat = 56
        let tekCekim: CGFloat = 56
        let gun30:    CGFloat = 44
        let gun60:    CGFloat = 44
        var gun90:    CGFloat { 551.28 - kod - urun - logo - form - protein - pesin - tekCekim - gun30 - gun60 }
        var total:    CGFloat { 551.28 }
    }
    private static let C = Cols()

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Ana üretim
    // ────────────────────────────────────────────────────────────────────

    // Antet görselinin sayfadaki içerik başlangıç noktası (pt)
    // Banner (~88) + adres (~70) = ~158 — biraz boşluk bırakarak 162
    private static let antetContentY: CGFloat = 162

    static func generate(
        rows:         [(formula: BlendFormula, meta: ProductPricingMeta?)],
        brand:        String = "Alapala",
        antetImage:   UIImage? = nil,
        kategoriInfo: [(name: String, color: UIColor, order: Int)]? = nil,
        ipCuval:      Double, firePct: Double, elektrik: Double,
        nakliye:      Double, iscilik: Double, globalKarPct: Double,
        vade:         VadeConfig,
        period:       String,
        extraItems:   [(value: Double, isPercent: Bool)] = []
    ) -> Data {

        // Dinamik kategori sırası ve renkleri
        let effectiveCategoryOrder: [String]
        let categoryColors: [String: UIColor]
        if let info = kategoriInfo, !info.isEmpty {
            effectiveCategoryOrder = info.sorted { $0.order < $1.order }.map { $0.name }
            categoryColors = info.reduce(into: [:]) { $0[$1.name] = $1.color }
        } else {
            effectiveCategoryOrder = categoryOrder
            categoryColors = [:]
        }

        let visible = rows.filter { $0.meta?.isVisible ?? true }
            .compactMap { formula, meta -> RowData? in
                let rasyon = formula.currentCostTL > 0 ? formula.currentCostTL : formula.recordedCostTL
                guard rasyon > 0 else { return nil }
                let effKar = (meta?.overrideKarPct ?? -1) >= 0 ? meta!.overrideKarPct : globalKarPct
                let bagKg  = meta?.bagKg ?? 50
                let calc   = PricingCalc.calculate(
                    rasyon: rasyon, ipCuval: ipCuval, firePct: firePct,
                    elektrik: elektrik, nakliye: nakliye, iscilik: iscilik,
                    karPct: effKar, bagKg: bagKg, extraItems: extraItems
                )
                let baseProtein = formula.lastSolve?.nutrientValues["crudeProtein"]
                    ?? formula.constraints.first { $0.nutrientKey == "crudeProtein" }?.currentValue
                let protOvr = meta?.proteinOverride ?? -1
                let effectiveProtein: Double? = protOvr >= 0 ? protOvr : baseProtein
                return RowData(
                    kod:           formula.code,
                    name:          formula.name,
                    form:          meta?.form ?? "Pelet",
                    protein:       effectiveProtein,
                    logoName:      meta?.logoName ?? "",
                    logoImagePath: meta?.logoImagePath ?? "",
                    category:      meta?.categoryGroup ?? "",
                    orderIdx:      meta?.orderIndex ?? 999,
                    calc:          calc,
                    manualPesin:   meta?.manualPesin ?? -1
                )
            }
            .sorted {
                let li = effectiveCategoryOrder.firstIndex(of: $0.category) ?? 999
                let ri = effectiveCategoryOrder.firstIndex(of: $1.category) ?? 999
                if li != ri { return li < ri }
                return $0.orderIdx < $1.orderIdx
            }

        // Antet görseli: parametre > asset catalog
        let resolvedAntet: UIImage?
        if let img = antetImage {
            resolvedAntet = img
        } else {
            let assetName = brand == "Karadeniz" ? "KaradenizYemAntet" : "AlapalaYemAntet"
            resolvedAntet = UIImage(named: assetName)
        }
        let hasAntet = resolvedAntet != nil

        let uniqueGroups = Set(visible.map { $0.category }).filter { !$0.isEmpty }.count
        let totalLines   = visible.count + uniqueGroups

        // Kullanılabilir yükseklik: antet varsa içerik alanı, yoksa çizilen header
        let headerH: CGFloat = hasAntet
            ? antetContentY + 18 + 22   // antetContentY + başlık + tblHdr
            : 88 + 24 + 6 + 54 + 22     // banner+adres+gap+bilgi+tblHdr
        let footerH: CGFloat = 38
        let available  = PH - 2 * ML - headerH - footerH
        let rowH: CGFloat = totalLines > 0 ? max(9.5, min(13.5, available / CGFloat(totalLines))) : 11.5
        let grpH: CGFloat = rowH + 1.0
        let fSz:  CGFloat = rowH <= 10.0 ? 6.3 : (rowH <= 11.5 ? 6.8 : 7.3)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: PW, height: PH))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var curY: CGFloat = 0

            if let antet = resolvedAntet {
                // ── Antet görseli tam sayfa arka plan ──────────────────
                antet.draw(in: CGRect(x: 0, y: 0, width: PW, height: PH))
                curY = antetContentY
                curY = drawInfoAndTitle(y: curY, period: period)
                curY = drawTableHeader(y: curY, height: 22)
            } else {
                // ── Programatik çizim (fallback) ───────────────────────
                curY = drawBanner(y: curY)
                curY = drawAddressBar(y: curY)
                curY += 6
                curY = drawInfoAndTitle(y: curY, period: period)
                curY = drawTableHeader(y: curY, height: 22)
            }

            curY = drawProducts(y: curY, rows: visible, rowH: rowH, grpH: grpH, fSz: fSz,
                                vade: vade, catColors: categoryColors)
            drawFooter(y: curY, fSz: fSz, hasAntet: hasAntet)
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Header Banner (~88pt) — Alapala Yem antetli kağıt tasarımı
    // ────────────────────────────────────────────────────────────────────

    @discardableResult
    private static func drawBanner(y: CGFloat) -> CGFloat {
        let H: CGFloat = 88
        guard let ctx = UIGraphicsGetCurrentContext() else { return y + H }

        // ── Lacivert gradyan zemin ─────────────────────────────────────
        ctx.saveGState()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradColors = [navyDark.cgColor, navyLight.cgColor, navyDark.cgColor] as CFArray
        let locs: [CGFloat] = [0.0, 0.55, 1.0]
        if let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: locs) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0,  y: y),
                end:   CGPoint(x: PW, y: y),
                options: []
            )
        }
        ctx.restoreGState()

        // Alt kenarda ince beyaz parlak çizgi
        UIColor.white.withAlphaComponent(0.30).setFill()
        UIRectFill(CGRect(x: 0, y: y + H - 1.5, width: PW, height: 1.5))

        // ── Sol: Alapala Yem logosu ───────────────────────────────────
        if let img = UIImage(named: "AlapalaYemLogo") {
            let maxH = H - 16
            let ratio = img.size.width / img.size.height
            let imgW  = min(PW * 0.42, maxH * ratio)
            let imgH  = imgW / ratio
            img.draw(in: CGRect(x: ML, y: y + (H - imgH) / 2, width: imgW, height: imgH))
        } else {
            drawFallbackLogo(x: ML, y: y, H: H, ctx: ctx)
        }

        // ── Sağ: Hayvan rozet logoları ────────────────────────────────
        if let img = UIImage(named: "AlapalaHayvanLogolari") {
            let imgH = H - 10
            let imgW = imgH * img.size.width / img.size.height
            img.draw(in: CGRect(x: PW - ML - imgW, y: y + 5, width: imgW, height: imgH))
        } else {
            drawAnimalBadges(bannerX: 0, bannerY: y, H: H, ctx: ctx)
        }

        return y + H
    }

    // Logosuz fallback: ok/şerit ikonları + "Alapala Yem" italik metin
    private static func drawFallbackLogo(x: CGFloat, y: CGFloat, H: CGFloat, ctx: CGContext) {
        let iconSize: CGFloat = H - 18
        let iconX = x
        let iconY = y + 9

        ctx.saveGState()
        // İki beyaz ok/şerit
        func arrowPath(offsetX: CGFloat) -> UIBezierPath {
            let p  = UIBezierPath()
            let ox = iconX + offsetX
            let oy = iconY
            let w  = iconSize * 0.42
            let h  = iconSize
            p.move(to:    CGPoint(x: ox + w * 0.28, y: oy))
            p.addLine(to: CGPoint(x: ox,            y: oy + h * 0.50))
            p.addLine(to: CGPoint(x: ox + w * 0.25, y: oy + h * 0.50))
            p.addLine(to: CGPoint(x: ox,            y: oy + h))
            p.addLine(to: CGPoint(x: ox + w,        y: oy + h * 0.50))
            p.addLine(to: CGPoint(x: ox + w * 0.75, y: oy + h * 0.50))
            p.close()
            return p
        }
        UIColor.white.withAlphaComponent(0.95).setFill()
        arrowPath(offsetX: 0).fill()
        UIColor.white.withAlphaComponent(0.55).setFill()
        arrowPath(offsetX: iconSize * 0.24).fill()
        ctx.restoreGState()

        // "Alapala Yem" — italik, beyaz
        let textX = iconX + iconSize * 0.75
        let textW = CGFloat(130)
        let ps = NSMutableParagraphStyle(); ps.alignment = .left
        let font = UIFont(name: "TimesNewRomanPS-BoldItalicMT", size: 20)
            ?? UIFont.italicSystemFont(ofSize: 20)
        NSAttributedString(string: "Alapala Yem", attributes: [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: ps
        ]).draw(in: CGRect(x: textX, y: y + H * 0.28, width: textW, height: H * 0.44))
    }

    // Hayvan rozetleri: KUZU / İNEK / BESİ
    private static func drawAnimalBadges(bannerX: CGFloat, bannerY: CGFloat, H: CGFloat, ctx: CGContext) {
        let diam:  CGFloat = H * 0.72
        let gap:   CGFloat = 5
        let total  = diam * 3 + gap * 2
        var cx     = PW - ML - total
        let by     = bannerY + (H - diam) / 2

        let badges: [(UIColor, String, String)] = [
            (UIColor(red: 0.78, green: 0.08, blue: 0.08, alpha: 1), "KUZU", "YEMİ"),
            (UIColor(red: 0.08, green: 0.30, blue: 0.70, alpha: 1), "İNEK", "YEMİ"),
            (UIColor(red: 0.78, green: 0.08, blue: 0.08, alpha: 1), "BESİ", "YEMİ"),
        ]

        for (clr, l1, l2) in badges {
            let oval = CGRect(x: cx, y: by, width: diam, height: diam)
            // Beyaz dış halka
            UIColor.white.setFill()
            UIBezierPath(ovalIn: oval.insetBy(dx: -1.5, dy: -1.5)).fill()
            // Renkli zemin
            clr.setFill()
            UIBezierPath(ovalIn: oval.insetBy(dx: 1.0, dy: 1.0)).fill()
            // İç ince beyaz halka
            ctx.saveGState()
            UIColor.white.withAlphaComponent(0.35).setStroke()
            let inner = UIBezierPath(ovalIn: oval.insetBy(dx: 4, dy: 4))
            inner.lineWidth = 0.7; inner.stroke()
            ctx.restoreGState()
            // Metin
            let fSz: CGFloat = diam < 40 ? 5.2 : 6.0
            drawT(l1, CGRect(x: cx, y: by + diam * 0.30, width: diam, height: diam * 0.26),
                  sz: fSz, bold: true, clr: .white, align: .center)
            drawT(l2, CGRect(x: cx, y: by + diam * 0.54, width: diam, height: diam * 0.26),
                  sz: fSz, bold: true, clr: .white, align: .center)
            cx += diam + gap
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Adres Şeridi (~24pt)
    // ────────────────────────────────────────────────────────────────────

    @discardableResult
    private static func drawAddressBar(y: CGFloat) -> CGFloat {
        let H: CGFloat = 24
        // Beyaz arka plan
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: y, width: PW, height: H))
        // Alt ince çizgi
        UIColor(white: 0.78, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: y + H - 0.5, width: PW, height: 0.5))

        let adresClr = UIColor(red: 0.20, green: 0.35, blue: 0.65, alpha: 1)
        let textClr  = UIColor(white: 0.22, alpha: 1)
        let fSz: CGFloat = 6.3
        let tY = y + (H - fSz) / 2 - 1

        // Sol blok: pin ikonu + adres + tel
        drawT("⊙", CGRect(x: ML, y: tY, width: 9, height: fSz + 2),
              sz: fSz + 0.5, clr: adresClr)
        drawT("Ankara Yolu 7. Km, 19100  Merkez / ÇORUM",
              CGRect(x: ML + 11, y: tY, width: 160, height: fSz + 2), sz: fSz, clr: textClr)
        drawT("T.(+90) 364 235 00 34",
              CGRect(x: ML + 11, y: tY + fSz + 1.5, width: 120, height: fSz + 1), sz: fSz - 0.3, clr: textClr)

        // Orta blok: web
        let midX = ML + C.total * 0.42
        drawT("⊕", CGRect(x: midX, y: tY, width: 9, height: fSz + 2),
              sz: fSz + 0.5, clr: adresClr)
        drawT("www.", CGRect(x: midX + 11, y: tY, width: 20, height: fSz + 2), sz: fSz, clr: textClr)
        // "alboas" kalın lacivert
        let boldAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "TimesNewRomanPS-BoldMT", size: fSz) ?? UIFont.boldSystemFont(ofSize: fSz),
            .foregroundColor: adresClr,
            .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .left; return p }()
        ]
        NSAttributedString(string: "alboas", attributes: boldAttr)
            .draw(in: CGRect(x: midX + 28, y: tY, width: 30, height: fSz + 2))
        drawT(".com.tr", CGRect(x: midX + 55, y: tY, width: 30, height: fSz + 2), sz: fSz, clr: textClr)

        // Sağ blok: mail
        let mailX = midX + 90
        drawT("✉", CGRect(x: mailX, y: tY, width: 10, height: fSz + 2),
              sz: fSz + 0.5, clr: adresClr)
        drawT("info@alboas.com.tr",
              CGRect(x: mailX + 12, y: tY, width: 90, height: fSz + 2), sz: fSz, clr: textClr)

        return y + H
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Bilgi Bloğu + Başlık (~54pt)
    // ────────────────────────────────────────────────────────────────────

    @discardableResult
    private static func drawInfoAndTitle(y: CGFloat, period: String) -> CGFloat {
        var curY = y

        // Sağ: müşteri mektubu
        let rightX = ML + C.total * 0.48
        let rightW = C.total * 0.52
        let df = DateFormatter()
        df.locale     = Locale(identifier: "tr_TR")
        df.dateFormat = "dd MMMM yyyy"
        let dateStr = period.isEmpty ? df.string(from: Date()) : period

        drawT("Değerli Müşterilerimiz,",
              CGRect(x: rightX, y: curY, width: rightW, height: 9),
              sz: 7.5, bold: true, clr: UIColor(white: 0.18, alpha: 1))
        drawT("\(dateStr) tarihinden itibaren geçerli yem fiyatları aşağıda belirtilmiştir.",
              CGRect(x: rightX, y: curY + 10, width: rightW, height: 8),
              sz: 6.5, clr: UIColor(white: 0.28, alpha: 1))
        drawT("Bilgilerinize sunar, hayırlı işler dileriz.",
              CGRect(x: rightX, y: curY + 19, width: rightW, height: 8),
              sz: 6.5, clr: UIColor(white: 0.28, alpha: 1))

        curY += 22

        // Sol: Büyük başlık "YEM BAYİ FİYAT LİSTESİ"
        drawT("YEM BAYİ FİYAT LİSTESİ",
              CGRect(x: ML, y: curY, width: C.total * 0.65, height: 20),
              sz: 15, bold: true, clr: navyDark)

        // Sağ: Saygılarımızla
        drawT("Saygılarımızla.",
              CGRect(x: ML + C.total * 0.60, y: curY + 6, width: C.total * 0.40, height: 12),
              sz: 7.5, italic: true, clr: UIColor(white: 0.30, alpha: 1), align: .right)

        curY += 20

        // Başlık altı çizgi (lacivert)
        navyDark.withAlphaComponent(0.55).setFill()
        UIRectFill(CGRect(x: ML, y: curY, width: C.total, height: 0.8))
        curY += 5

        return curY
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Tablo Başlığı
    // ────────────────────────────────────────────────────────────────────

    @discardableResult
    private static func drawTableHeader(y: CGFloat, height: CGFloat) -> CGFloat {
        navyDark.setFill()
        UIRectFill(CGRect(x: ML, y: y, width: C.total, height: height))

        // Üst parlak şerit
        UIColor.white.withAlphaComponent(0.10).setFill()
        UIRectFill(CGRect(x: ML, y: y, width: C.total, height: height * 0.35))

        let fSz: CGFloat = 6.3
        let vP:  CGFloat = 2.5
        var x    = ML + 3

        let hCells: [(String, CGFloat, NSTextAlignment)] = [
            ("KOD",                    C.kod,       .center),
            ("YEM CİNSLERİ",           C.urun,      .left),
            ("LOGO",                   C.logo,      .center),
            ("Form",                   C.form,      .center),
            ("Protein\n%",             C.protein,   .center),
            ("Peşin\n₺/çuval",         C.pesin,     .center),
            ("Tek Çekim\nKredi Kartı", C.tekCekim,  .center),
            ("30 Gün\nVadeli",         C.gun30,     .center),
            ("60 Gün\nVadeli",         C.gun60,     .center),
            ("90 Gün\nVadeli",         C.gun90,     .center),
        ]
        for (txt, w, align) in hCells {
            drawT(txt, CGRect(x: x, y: y + vP, width: w - 4, height: height - vP * 2),
                  sz: fSz, bold: true, clr: .white, align: align)
            x += w
        }
        // Sütun ayraçları
        x = ML + C.kod
        for w in [C.urun, C.logo, C.form, C.protein, C.pesin, C.tekCekim, C.gun30, C.gun60] {
            UIColor(white: 1, alpha: 0.18).setFill()
            UIRectFill(CGRect(x: x, y: y + 3, width: 0.4, height: height - 5))
            x += w
        }
        return y + height
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Ürün Satırları
    // ────────────────────────────────────────────────────────────────────

    private static func drawProducts(
        y:         CGFloat,
        rows:      [RowData],
        rowH:      CGFloat,
        grpH:      CGFloat,
        fSz:       CGFloat,
        vade:      VadeConfig,
        catColors: [String: UIColor] = [:]
    ) -> CGFloat {
        var curY    = y
        var lastGrp = ""
        var rowIdx  = 0

        // Kategori başına ürün sayısı ve sıra numarası (PDF sırasına göre)
        var countByGroup: [String: Int] = [:]
        for row in rows { countByGroup[row.category, default: 0] += 1 }
        let usedGroups = categoryOrder.filter { countByGroup[$0] != nil }
        let totalGroups = usedGroups.count

        for row in rows {
            let grp = row.category.trimmingCharacters(in: .whitespaces)
            if !grp.isEmpty && grp != lastGrp {
                lastGrp = grp

                // ── Kategori başlık satırı ──────────────────────────────
                let hH = grpH + 2
                let hdrColor = catColors[grp] ?? groupClr
                hdrColor.setFill()
                UIRectFill(CGRect(x: ML, y: curY, width: C.total, height: hH))

                // Sol: kategori adı (büyük harf)
                let textW = C.total * 0.72
                drawT(grp.uppercased(),
                      CGRect(x: ML + 6, y: curY + (hH - fSz - 1) / 2,
                             width: textW, height: fSz + 2),
                      sz: fSz, bold: true, clr: .white)

                // Sağ: "15 ürün  •  2/7"
                let count   = countByGroup[grp] ?? 0
                let grpIdx  = (usedGroups.firstIndex(of: grp) ?? 0) + 1
                let rightTxt = "\(count) ürün  •  \(grpIdx)/\(totalGroups)"
                drawT(rightTxt,
                      CGRect(x: ML + textW, y: curY + (hH - fSz - 1) / 2,
                             width: C.total - textW - 4, height: fSz + 2),
                      sz: fSz - 0.5, clr: UIColor.white.withAlphaComponent(0.82), align: .right)

                // Alt çizgi (daha koyu gölge efekti)
                UIColor(white: 0, alpha: 0.15).setFill()
                UIRectFill(CGRect(x: ML, y: curY + hH - 1, width: C.total, height: 1))

                curY  += hH
                rowIdx = 0
            }

            let bg = rowIdx % 2 == 0 ? UIColor.white : altRow
            bg.setFill()
            UIRectFill(CGRect(x: ML, y: curY, width: C.total, height: rowH))

            // Manuel fiyat varsa o baz alınır, yoksa hesaplanan
            let pesinBase = row.manualPesin >= 0 ? row.manualPesin : row.calc.pesin
            let pesin    = pesinBase
            let tekCekim = pesinBase * (1 + vade.tekCekim / 100)
            let gun30    = pesinBase * (1 + vade.gun30    / 100)
            let gun60    = pesinBase * (1 + vade.gun60    / 100)
            let gun90    = pesinBase * (1 + vade.gun90    / 100)

            let vP = max(1.0, (rowH - fSz) / 2 - 0.5)
            let tY = curY + vP
            let tH = rowH - vP * 2
            var x  = ML + 3

            // KOD — lacivert bold
            drawT(row.kod,
                  CGRect(x: x, y: tY, width: C.kod - 4, height: tH),
                  sz: fSz, bold: true, clr: navyDark, align: .center)
            x += C.kod

            // Ürün adı
            drawT(row.name,
                  CGRect(x: x, y: tY, width: C.urun - 4, height: tH),
                  sz: fSz, bold: true)
            x += C.urun

            // Logo — nizami kutu içinde, ölçekli ve ortalı
            if let img = loadLogoImage(name: row.logoName, path: row.logoImagePath) {
                let pad:  CGFloat = 1.5
                let bx   = x + pad;         let by = curY + pad
                let bw   = C.logo - pad*2;  let bh = rowH  - pad*2
                UIColor.white.setFill(); UIRectFill(CGRect(x: bx, y: by, width: bw, height: bh))
                UIColor(white: 0.70, alpha: 0.8).setStroke()
                let bp = UIBezierPath(rect: CGRect(x: bx, y: by, width: bw, height: bh))
                bp.lineWidth = 0.4; bp.stroke()
                let ratio = img.size.width / img.size.height
                var dw = bw - 2; var dh = dw / ratio
                if dh > bh - 2 { dh = bh - 2; dw = dh * ratio }
                img.draw(in: CGRect(x: bx + (bw - dw)/2, y: by + (bh - dh)/2, width: dw, height: dh))
            }
            x += C.logo

            // Form
            drawT(row.form,
                  CGRect(x: x, y: tY, width: C.form - 4, height: tH),
                  sz: fSz, align: .center)
            x += C.form

            // Protein
            drawT(protStr(row.protein),
                  CGRect(x: x, y: tY, width: C.protein - 2, height: tH),
                  sz: fSz, align: .center)
            x += C.protein

            // Fiyatlar
            let priceClr = UIColor(white: 0.08, alpha: 1)
            for (val, w) in [(pesin, C.pesin), (tekCekim, C.tekCekim),
                             (gun30, C.gun30), (gun60, C.gun60), (gun90, C.gun90)] {
                drawT(priceFmt(val),
                      CGRect(x: x + 1, y: tY, width: w - 4, height: tH),
                      sz: fSz, clr: priceClr, align: .right)
                x += w
            }

            // Alt çizgi
            UIColor(white: 0.82, alpha: 1).setFill()
            UIRectFill(CGRect(x: ML, y: curY + rowH - 0.3, width: C.total, height: 0.3))

            // Sütun ayraçları
            x = ML + C.kod
            for w in [C.urun, C.logo, C.form, C.protein, C.pesin, C.tekCekim, C.gun30, C.gun60] {
                borderClr.setFill()
                UIRectFill(CGRect(x: x, y: curY + 1.5, width: 0.3, height: rowH - 3))
                x += w
            }

            curY  += rowH
            rowIdx += 1
        }

        // Tablo dış kenarlığı
        navyDark.withAlphaComponent(0.35).setStroke()
        let tablePath = UIBezierPath(rect: CGRect(x: ML, y: y, width: C.total, height: curY - y))
        tablePath.lineWidth = 0.5
        tablePath.stroke()

        return curY
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Footer
    // ────────────────────────────────────────────────────────────────────

    private static func drawFooter(y: CGFloat, fSz: CGFloat, hasAntet: Bool = false) {
        var curY = y + 5
        // Üst çizgi
        UIColor(white: 0.50, alpha: 1).setFill()
        UIRectFill(CGRect(x: ML, y: curY, width: C.total, height: 0.6))
        curY += 5

        let lH  = fSz + 2.5
        let txtW = C.total * 0.73

        drawT("Her zam geçişlerinde içerideki siparişler güncel fiyattan faturalanacaktır.",
              CGRect(x: ML, y: curY, width: txtW, height: lH),
              sz: fSz, clr: UIColor(white: 0.25, alpha: 1))
        curY += lH

        drawT("Pancar Küspesi Satışlarımız Peşindir. GÜNCEL FİYAT ALINIZ",
              CGRect(x: ML, y: curY, width: txtW, height: lH),
              sz: fSz, bold: true, clr: .red)
        curY += lH

        drawT("Fiyatlarda KDV dahildir. (KDV %0'dır — 10.02.2016 itibarı ile)",
              CGRect(x: ML, y: curY, width: txtW, height: lH),
              sz: fSz, clr: UIColor(white: 0.25, alpha: 1))

        // ── ALBO AŞ kuruluşudur kutusu — antet yoksa çiz ────────────
        guard !hasAntet else { return }
        let boxW: CGFloat = 78
        let boxH: CGFloat = lH * 3.2
        let boxX = ML + C.total - boxW
        let boxY = y + 5

        navyDark.setFill()
        UIRectFill(CGRect(x: boxX, y: boxY, width: boxW, height: boxH))

        // İnce parlak üst şerit
        UIColor.white.withAlphaComponent(0.12).setFill()
        UIRectFill(CGRect(x: boxX, y: boxY, width: boxW, height: boxH * 0.30))

        if let img = UIImage(named: "AlboLogo") {
            img.draw(in: CGRect(x: boxX + 4, y: boxY + 3, width: boxW - 8, height: boxH - 6))
        } else {
            drawT("ALBO AŞ",
                  CGRect(x: boxX, y: boxY + boxH * 0.14, width: boxW, height: boxH * 0.40),
                  sz: fSz + 1.5, bold: true, clr: .white, align: .center)
            drawT("kuruluşudur.",
                  CGRect(x: boxX, y: boxY + boxH * 0.58, width: boxW, height: boxH * 0.30),
                  sz: fSz - 0.5, italic: true, clr: UIColor(white: 0.80, alpha: 1), align: .center)
        }

        // ── Sağ alt köşe kıvrımı (page fold efekti) ─────────────────
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let foldSize: CGFloat = 22
        let fx = PW - foldSize
        let fy = PH - foldSize

        ctx.saveGState()
        // Karanlık alt üçgen (gölge)
        UIColor(white: 0.55, alpha: 0.5).setFill()
        let shadow = UIBezierPath()
        shadow.move(to:    CGPoint(x: fx,  y: fy))
        shadow.addLine(to: CGPoint(x: PW,  y: fy))
        shadow.addLine(to: CGPoint(x: PW,  y: PH))
        shadow.addLine(to: CGPoint(x: fx,  y: PH))
        shadow.close()
        shadow.fill()

        // Açık mavi kıvrım üçgeni
        navyLight.withAlphaComponent(0.85).setFill()
        let fold = UIBezierPath()
        fold.move(to:    CGPoint(x: fx,  y: fy))
        fold.addLine(to: CGPoint(x: PW,  y: fy))
        fold.addLine(to: CGPoint(x: PW,  y: PH))
        fold.close()
        fold.fill()

        // Beyaz kıvrım üçgeni (kağıt görünümü)
        UIColor.white.setFill()
        let foldLight = UIBezierPath()
        foldLight.move(to:    CGPoint(x: fx,      y: fy))
        foldLight.addLine(to: CGPoint(x: fx + foldSize * 0.55, y: fy))
        foldLight.addLine(to: CGPoint(x: fx,      y: fy + foldSize * 0.55))
        foldLight.close()
        foldLight.fill()

        ctx.restoreGState()
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Yardımcı
    // ────────────────────────────────────────────────────────────────────

    private static func drawT(
        _ text: String, _ rect: CGRect,
        sz:    CGFloat,
        bold:  Bool            = false,
        italic:Bool            = false,
        clr:   UIColor         = .black,
        align: NSTextAlignment = .left
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
        n.minimumFractionDigits = 2
        n.maximumFractionDigits = 2
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
        let kod:           String
        let name:          String
        let form:          String
        let protein:       Double?
        let logoName:      String
        let logoImagePath: String
        let category:      String
        let orderIdx:      Int
        let calc:          PricingCalc
        let manualPesin:   Double   // -1 = hesaplanan
    }

    private static func loadLogoImage(name: String, path: String) -> UIImage? {
        if !path.isEmpty,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent(path)
            if let img = UIImage(contentsOfFile: url.path) { return img }
        }
        if !name.isEmpty { return UIImage(named: name) }
        return nil
    }
}
