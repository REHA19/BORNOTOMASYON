import UIKit
import Foundation

struct StokPDFService {

    // A4 boyutu (nokta, 72 dpi)
    private static let pageW:    CGFloat = 595.2
    private static let pageH:    CGFloat = 841.8
    private static let margin:   CGFloat = 36
    private static var contentW: CGFloat { pageW - 2 * margin }

    // Fiyat listesiyle aynı: antet başlığındaki lacivert şeridin altına denk gelir
    private static let antetContentY: CGFloat = 162
    // Sağ alt köşe kalkan sembolünü korumak için alt sınır
    private static let bottomGuard:   CGFloat = pageH - 75

    // MARK: - Genel API

    /// Kayıtlı rapor → PDF
    static func generate(rapor: StokAylikRapor, antet: UIImage? = nil) -> Data {
        guard let snap = rapor.snapshot else { return Data() }
        return generateFromSnapshot(snap,
                                    baslik: rapor.ayBaslik,
                                    kayitTarihi: rapor.kayitTarihi,
                                    kayitSayisi: rapor.kayitSayisi,
                                    antet: antet)
    }

    /// Anlık (kaydedilmemiş) görüntü → PDF
    static func generateCurrent(snap: StokRaporSnapshot,
                                 baslik: String,
                                 antet: UIImage? = nil) -> Data {
        generateFromSnapshot(snap,
                             baslik: baslik,
                             kayitTarihi: Date(),
                             kayitSayisi: 0,
                             antet: antet)
    }

    // MARK: - PDF üretimi

    private static func generateFromSnapshot(
        _ snap:        StokRaporSnapshot,
        baslik:        String,
        kayitTarihi:   Date,
        kayitSayisi:   Int,
        antet:         UIImage?
    ) -> Data {

        let hasAntet = antet != nil

        // Antet varsa tam sayfa arka plan olarak çizilir (fiyat listesiyle aynı mantık).
        // İçerik lacivert şeridin hemen altından (antetContentY) başlar.
        let contentTopY: CGFloat = hasAntet ? antetContentY : 0

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH)
        )

        return renderer.pdfData { ctx in

            rowAlt = false
            var y  = contentTopY + margin

            func newPage() {
                ctx.beginPage()
                rowAlt = false
                if let img = antet {
                    // Tam sayfa arka plan — antet her sayfada
                    img.draw(in: CGRect(x: 0, y: 0, width: pageW, height: pageH))
                }
                y = contentTopY + margin
                drawSubHeader(baslik: baslik, kayitTarihi: kayitTarihi, y: &y)
            }

            func checkBreak(_ needed: CGFloat) {
                if y + needed > bottomGuard { newPage() }
            }

            // — İlk sayfa —
            ctx.beginPage()
            if let img = antet {
                // Tam sayfa arka plan
                img.draw(in: CGRect(x: 0, y: 0, width: pageW, height: pageH))
            }
            drawMainHeader(baslik: baslik, kayitTarihi: kayitTarihi, y: &y)

            // Özet kutu
            checkBreak(58)
            drawSummaryBox(snap: snap, y: &y)
            y += 14

            // Hammadde tablosu
            checkBreak(36)
            drawSectionTitle("HAMMADDE STOĞU (\(snap.hammaddeler.count) kalem)", y: &y)

            // Sütunlar toplamı = contentW = 523.2
            let hmCols: [(String, CGFloat, NSTextAlignment)] = [
                ("Hammadde",   210, .left),
                ("Stok (kg)",   90, .right),
                ("₺/ton",       85, .right),
                ("Toplam (₺)", 138, .right),
            ]
            drawTableHeader(cols: hmCols, y: &y)
            for row in snap.hammaddeler.sorted(by: { $0.totalTL > $1.totalTL }) {
                checkBreak(18)
                drawTableRow(cols: hmCols, cells: [
                    row.name,
                    formatNum(row.stockKg, dec: 0),
                    row.priceTL.map { formatNum($0, dec: 0) } ?? "—",
                    formatNum(row.totalTL, dec: 0),
                ], y: &y)
            }
            drawTableTotalRow(cols: hmCols,
                              label: "HAMMADDE TOPLAM",
                              value: formatNum(snap.hammaddeToplam, dec: 0) + " ₺",
                              y: &y)
            y += 14

            // Manuel kalemler tablosu
            if !snap.manuelKalemler.isEmpty {
                checkBreak(40)
                drawSectionTitle("MANUEL KALEMLER (\(snap.manuelKalemler.count) kalem)", y: &y)

                // Sütunlar toplamı = 140+80+70+68+35+130 = 523
                let mkCols: [(String, CGFloat, NSTextAlignment)] = [
                    ("Kalem",        140, .left),
                    ("Kategori",      80, .left),
                    ("Miktar",        70, .right),
                    ("Fiyat",         68, .right),
                    ("Kur",           35, .center),
                    ("Toplam (₺)",   130, .right),
                ]
                drawTableHeader(cols: mkCols, y: &y)
                for item in snap.manuelKalemler {
                    checkBreak(18)
                    drawTableRow(cols: mkCols, cells: [
                        item.name,
                        item.category.isEmpty ? "—" : item.category,
                        String(format: "%.0f %@", item.quantity, item.unit),
                        formatNum(item.unitPrice, dec: 2),
                        item.currency,
                        formatNum(item.totalTL, dec: 0),
                    ], y: &y)
                }
                drawTableTotalRow(cols: mkCols,
                                  label: "MANUEL KALEMLER TOPLAM",
                                  value: formatNum(snap.manuelToplam, dec: 0) + " ₺",
                                  y: &y)
                y += 14
            }

            // Grand total
            checkBreak(36)
            drawGrandTotal(value: snap.grandTotal, y: &y)

            // Kur bilgisi
            y += 10
            var kurText = ""
            if snap.usdRate > 0 { kurText += String(format: "USD/TRY: %.4f  ", snap.usdRate) }
            if snap.eurRate > 0 { kurText += String(format: "EUR/TRY: %.4f", snap.eurRate) }
            if !kurText.isEmpty {
                drawText(kurText, x: margin, y: y, width: contentW,
                         font: .systemFont(ofSize: 8), color: .gray, align: .left)
                y += 12
            }

            // Sayfa footer — antet varsa sol tarafta dar bırak (sağ alt kalkanı koru)
            drawFooter(kayitTarihi: kayitTarihi, kayitSayisi: kayitSayisi, hasAntet: hasAntet)
        }
    }

    // MARK: - Başlık çizimi

    private static func drawMainHeader(baslik: String, kayitTarihi: Date, y: inout CGFloat) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "dd MMMM yyyy"

        drawText(fmt.string(from: kayitTarihi),
                 x: margin, y: y, width: contentW,
                 font: .systemFont(ofSize: 9), color: .gray, align: .right)
        y += 14

        drawText("STOK MALİYET RAPORU",
                 x: margin, y: y, width: contentW,
                 font: .boldSystemFont(ofSize: 18), color: .black, align: .left)
        y += 22

        drawText(baslik,
                 x: margin, y: y, width: contentW,
                 font: .systemFont(ofSize: 13, weight: .medium), color: .darkGray, align: .left)
        y += 18

        drawLine(x: margin, y: y, width: contentW, color: .darkGray)
        y += 8
    }

    private static func drawSubHeader(baslik: String, kayitTarihi: Date, y: inout CGFloat) {
        drawText("STOK MALİYET RAPORU — \(baslik)",
                 x: margin, y: y, width: contentW,
                 font: .boldSystemFont(ofSize: 11), color: .black, align: .left)
        y += 14
        drawLine(x: margin, y: y, width: contentW, color: .lightGray)
        y += 6
    }

    // MARK: - Özet kutu

    private static func drawSummaryBox(snap: StokRaporSnapshot, y: inout CGFloat) {
        let boxH: CGFloat = 52
        let rect  = CGRect(x: margin, y: y, width: contentW, height: boxH)
        UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        UIColor(red: 0.6, green: 0.7, blue: 0.9, alpha: 1).setStroke()
        let border = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6)
        border.lineWidth = 1; border.stroke()

        let thirdW = contentW / 3
        let row1y  = y + 8
        let row2y  = y + 26

        drawText("Hammadde Stoğu",
                 x: margin + 8, y: row1y, width: thirdW - 8,
                 font: .systemFont(ofSize: 8), color: .gray, align: .left)
        drawText(formatNum(snap.hammaddeToplam, dec: 0) + " ₺",
                 x: margin + 8, y: row2y, width: thirdW - 8,
                 font: .boldSystemFont(ofSize: 10), color: .black, align: .left)

        let mid = margin + thirdW
        drawText("Manuel Kalemler",
                 x: mid, y: row1y, width: thirdW,
                 font: .systemFont(ofSize: 8), color: .gray, align: .left)
        drawText(formatNum(snap.manuelToplam, dec: 0) + " ₺",
                 x: mid, y: row2y, width: thirdW,
                 font: .boldSystemFont(ofSize: 10), color: .black, align: .left)

        let right = margin + 2 * thirdW
        drawText("TOPLAM STOK DEĞERİ",
                 x: right, y: row1y, width: thirdW - 8,
                 font: .systemFont(ofSize: 8),
                 color: UIColor(red: 0.7, green: 0.4, blue: 0, alpha: 1), align: .right)
        drawText(formatNum(snap.grandTotal, dec: 0) + " ₺",
                 x: right, y: row2y, width: thirdW - 8,
                 font: .boldSystemFont(ofSize: 13),
                 color: UIColor(red: 0.7, green: 0.3, blue: 0, alpha: 1), align: .right)

        y += boxH + 8
    }

    // MARK: - Tablo çizimi

    private static func drawSectionTitle(_ title: String, y: inout CGFloat) {
        drawText(title, x: margin, y: y, width: contentW,
                 font: .systemFont(ofSize: 9, weight: .semibold),
                 color: UIColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1), align: .left)
        y += 13
    }

    private static func drawTableHeader(cols: [(String, CGFloat, NSTextAlignment)],
                                        y: inout CGFloat) {
        let rowH: CGFloat = 16
        UIColor(red: 0.25, green: 0.35, blue: 0.60, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentW, height: rowH)).fill()
        var xOff = margin
        for (label, width, align) in cols {
            drawText(label, x: xOff + 3, y: y + 2, width: width - 6,
                     font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, align: align)
            xOff += width
        }
        y += rowH
    }

    private static var rowAlt = false

    private static func drawTableRow(cols: [(String, CGFloat, NSTextAlignment)],
                                     cells: [String],
                                     y: inout CGFloat) {
        let rowH: CGFloat = 16
        if rowAlt {
            UIColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: contentW, height: rowH)).fill()
        }
        rowAlt.toggle()
        var xOff = margin
        for (i, (_, width, align)) in cols.enumerated() {
            let cell = i < cells.count ? cells[i] : ""
            drawText(cell, x: xOff + 3, y: y + 3, width: width - 6,
                     font: .systemFont(ofSize: 8), color: .black, align: align)
            xOff += width
        }
        UIColor(red: 0.88, green: 0.88, blue: 0.92, alpha: 1).setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y + rowH))
        line.addLine(to: CGPoint(x: margin + contentW, y: y + rowH))
        line.lineWidth = 0.3; line.stroke()
        y += rowH
    }

    private static func drawTableTotalRow(cols: [(String, CGFloat, NSTextAlignment)],
                                          label: String, value: String,
                                          y: inout CGFloat) {
        let rowH: CGFloat = 18
        rowAlt = false
        UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentW, height: rowH)).fill()

        drawText(label, x: margin + 3, y: y + 3, width: contentW * 0.55,
                 font: .systemFont(ofSize: 8.5, weight: .semibold), color: .black, align: .left)
        // Değeri tam sağa hizala (contentW - 3)
        drawText(value, x: margin, y: y + 3, width: contentW - 3,
                 font: .boldSystemFont(ofSize: 9), color: .black, align: .right)
        y += rowH
    }

    private static func drawGrandTotal(value: Double, y: inout CGFloat) {
        let rowH: CGFloat = 30
        let rect  = CGRect(x: margin, y: y, width: contentW, height: rowH)
        UIColor(red: 0.95, green: 0.88, blue: 0.70, alpha: 1).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
        drawText("GENEL TOPLAM STOK DEĞERİ",
                 x: margin + 10, y: y + 7, width: contentW * 0.55,
                 font: .systemFont(ofSize: 10, weight: .bold), color: .black, align: .left)
        drawText(formatNum(value, dec: 0) + " ₺",
                 x: margin, y: y + 5, width: contentW - 10,
                 font: .boldSystemFont(ofSize: 14),
                 color: UIColor(red: 0.6, green: 0.3, blue: 0, alpha: 1), align: .right)
        y += rowH
    }

    private static func drawFooter(kayitTarihi: Date, kayitSayisi: Int, hasAntet: Bool = false) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "dd.MM.yyyy HH:mm"
        var foot = "Oluşturulma: \(fmt.string(from: kayitTarihi))"
        if kayitSayisi > 0 { foot += "  •  Bu ay kayıt: \(kayitSayisi)" }

        // Antet varsa sağ alt kalkan sembolüyle çakışmamak için genişliği kısalt
        let footW = hasAntet ? contentW * 0.72 : contentW
        let lineY = pageH - 28
        drawLine(x: margin, y: lineY, width: footW, color: .lightGray)
        drawText(foot, x: margin, y: pageH - 24, width: footW,
                 font: .systemFont(ofSize: 7.5), color: .lightGray, align: .left)
    }

    // MARK: - Temel çizim

    private static func drawText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat,
                                  font: UIFont, color: UIColor,
                                  align: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment     = align
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para,
        ]
        text.draw(in: CGRect(x: x, y: y, width: width, height: font.lineHeight + 2),
                  withAttributes: attrs)
    }

    private static func drawLine(x: CGFloat, y: CGFloat, width: CGFloat, color: UIColor) {
        color.setStroke()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + width, y: y))
        p.lineWidth = 0.75; p.stroke()
    }

    // MARK: - Sayı formatı (Türkçe locale)

    private static let intFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        f.maximumFractionDigits = 0
        return f
    }()
    private static let decFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static func formatNum(_ v: Double, dec: Int) -> String {
        let fmt = dec == 0 ? intFmt : decFmt
        return fmt.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}
