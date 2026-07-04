import UIKit
import Foundation

// MARK: - Çeyreklik Bilanço & Gelir Tablosu PDF Üretici

struct BilancoExportService {

    let bilanco: CeyrekBilanco
    let sirketAdi: String
    let logoImage: UIImage?

    // Türk lirası formatlı metin
    private func tlStr(_ v: Double, parantez: Bool = false) -> String {
        let s = String(format: "%,.0f ₺", abs(v))
        return parantez && v < 0 ? "(\(s))" : (parantez && v == 0 ? s : s)
    }

    private func tlFmt(_ v: Double) -> String { String(format: "%,.0f ₺", v) }

    func generate() -> Data {
        let cv = BornPDFCanvas(landscape: false)

        return cv.render { c in
            drawGelirTablosu(c)
            c.newPage()
            drawBilanco(c)
            c.footer()
        }
    }

    // MARK: Sayfa 1 — Gelir Tablosu

    private func drawGelirTablosu(_ c: BornPDFCanvas) {
        // Antet
        drawAntet(c)

        c.space(8)
        c.sectionHeader("DÖNEM GELİR TABLOSU — \(bilanco.kisaBaslik) (\(bilanco.ceyrekBasligi) \(bilanco.yil))")
        c.space(6)

        let rowH: CGFloat = 18
        let cols: [(String, CGFloat, NSTextAlignment, Bool)] = [
            // (etiket, genişlik, hizalama, kalın?)
            ("", 0, .left, false)   // placeholder — satır bazında çizilecek
        ]
        _ = cols

        let W = c.CW
        let lblW: CGFloat = W * 0.65
        let valW: CGFloat = W * 0.35

        func satir(_ lbl: String, _ val: String, bg: UIColor? = nil, bold: Bool = false, sepOnce: Bool = false, sepSonra: Bool = false) {
            c.checkPage(rowH + 2)
            if sepOnce {
                UIColor(white: 0.75, alpha: 1).setFill()
                UIRectFill(CGRect(x: c.M, y: c.y, width: W, height: 0.5))
                c.y += 2
            }
            if let bg { c.fillR(CGRect(x: c.M, y: c.y, width: W, height: rowH), bg) }
            c.drawText(lbl, in: CGRect(x: c.M + 8, y: c.y + 4, width: lblW - 8, height: 13),
                       size: 9, weight: bold ? .bold : .regular)
            c.drawText(val, in: CGRect(x: c.M + lblW, y: c.y + 4, width: valW - 8, height: 13),
                       size: 9, weight: bold ? .bold : .regular, align: .right)
            c.y += rowH
            if sepSonra {
                UIColor(white: 0.75, alpha: 1).setFill()
                UIRectFill(CGRect(x: c.M, y: c.y, width: W, height: 0.5))
                c.y += 4
            }
        }

        let altBg = UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1)
        let totBg  = UIColor(red: 0.83, green: 0.90, blue: 0.97, alpha: 1)

        satir("Net Satışlar",                    tlFmt(bilanco.netSatislar), bg: altBg)
        satir("(-) Satılan Mal Maliyeti (SMM)",  "(\(tlFmt(bilanco.smmOto)))")
        c.space(2)

        let sep = UIColor(red: 0.00, green: 0.20, blue: 0.50, alpha: 0.3)
        sep.setFill(); UIRectFill(CGRect(x: c.M, y: c.y, width: W, height: 0.7)); c.y += 4

        satir("BRÜT KAR", tlFmt(bilanco.brutKar), bg: totBg, bold: true)
        c.space(6)

        satir("(-) Operasyonel Giderler", "(\(tlFmt(bilanco.opGiderOto)))")
        c.space(2)
        sep.setFill(); UIRectFill(CGRect(x: c.M, y: c.y, width: W, height: 0.7)); c.y += 4

        let netKar = bilanco.donemNetKari
        let netBg  = netKar >= 0
            ? UIColor(red: 0.85, green: 0.96, blue: 0.87, alpha: 1)
            : UIColor(red: 0.98, green: 0.88, blue: 0.88, alpha: 1)
        satir("DÖNEM NET KARI", tlFmt(netKar), bg: netBg, bold: true)

        c.space(16)

        // Notlar
        if !bilanco.notlar.isEmpty {
            c.sectionHeader("NOTLAR")
            c.space(4)
            c.drawText(bilanco.notlar,
                       in: CGRect(x: c.M + 6, y: c.y, width: c.CW - 12, height: 60),
                       size: 8, weight: .regular)
            c.y += 68
        }
    }

    // MARK: Sayfa 2 — Bilanço

    private func drawBilanco(_ c: BornPDFCanvas) {
        drawAntet(c)
        c.space(8)
        c.sectionHeader("BİLANÇO — \(bilanco.kisaBaslik) (\(bilanco.ceyrekBasligi) \(bilanco.yil))")
        c.space(8)

        let totBg  = UIColor(red: 0.83, green: 0.90, blue: 0.97, alpha: 1)
        let altBg  = UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1)
        let blue   = UIColor(red: 0.00, green: 0.20, blue: 0.50, alpha: 1)

        let halfW: CGFloat = c.CW / 2 - 4
        let rowH: CGFloat = 16
        let indent: CGFloat = 12

        // Bilanço satırı çiz (sol veya sağ sütun)
        func bilancoSatiri(side: Int, // 0=sol, 1=sağ
                           lbl: String, val: String?,
                           bg: UIColor? = nil, bold: Bool = false,
                           baslik: Bool = false) {
            let ox: CGFloat = c.M + CGFloat(side) * (halfW + 8)
            if let bg { c.fillR(CGRect(x: ox, y: c.y, width: halfW, height: rowH), bg) }
            let textX: CGFloat = ox + (baslik ? 4 : indent)
            let lblW: CGFloat  = halfW * 0.60
            let valW: CGFloat  = halfW * 0.38
            c.drawText(lbl, in: CGRect(x: textX, y: c.y + 3, width: lblW, height: 11),
                       size: baslik ? 8 : 7.5, weight: bold ? .bold : (baslik ? .semibold : .regular),
                       color: baslik ? blue : .black)
            if let val {
                c.drawText(val, in: CGRect(x: ox + halfW - valW - 2, y: c.y + 3, width: valW, height: 11),
                           size: 7.5, weight: bold ? .bold : .regular, align: .right)
            }
        }

        // Tüm satırları belirle
        struct BilancoSatir {
            let sol: (lbl: String, val: String?, bg: UIColor?, bold: Bool, baslik: Bool)
            let sag: (lbl: String, val: String?, bg: UIColor?, bold: Bool, baslik: Bool)
        }

        let satirlar: [BilancoSatir] = [
            .init(sol: ("AKTİF",               nil,      nil,    true,  true),
                  sag: ("PASİF",               nil,      nil,    true,  true)),
            .init(sol: ("DÖNEN VARLIKLAR",      nil,      altBg,  false, true),
                  sag: ("KISA VADELİ BORÇLAR", nil,      altBg,  false, true)),
            .init(sol: ("Nakit / Banka",        tlFmt(bilanco.nakit),       nil, false, false),
                  sag: ("Ticari Borçlar",       tlFmt(bilanco.kisaVadeli),   nil, false, false)),
            .init(sol: ("Ticari Alacaklar",     tlFmt(bilanco.alacaklar),   nil, false, false),
                  sag: ("",                     nil,      nil, false, false)),
            .init(sol: ("Stok",                 tlFmt(bilanco.stokOto),     altBg, false, false),
                  sag: ("UZUN VADELİ BORÇLAR", nil,      altBg, false, true)),
            .init(sol: ("Diğer Dönen Varlık",   tlFmt(bilanco.digerDonen),  nil, false, false),
                  sag: ("Banka Kredileri",       tlFmt(bilanco.uzunVadeli),  nil, false, false)),
            .init(sol: ("",                     nil,      nil, false, false),
                  sag: ("",                     nil,      nil, false, false)),
            .init(sol: ("DURAN VARLIKLAR",      nil,      altBg, false, true),
                  sag: ("ÖZ KAYNAK",            nil,      altBg, false, true)),
            .init(sol: ("Sabit Kıymet (Brüt)", tlFmt(bilanco.sabitKiymetBrut), nil, false, false),
                  sag: ("Sermaye",              tlFmt(bilanco.sermaye),      nil, false, false)),
            .init(sol: ("Birikmiş Amortisman",  "(\(tlFmt(bilanco.birikmisBrut)))", nil, false, false),
                  sag: ("Geçmiş Yıl Karları",  tlFmt(bilanco.gecmisKarlar), nil, false, false)),
            .init(sol: ("Sabit Kıymet (Net)",   tlFmt(bilanco.sabitKiymetNet), altBg, false, false),
                  sag: ("Dönem Net Karı",       tlFmt(bilanco.donemNetKari), altBg, false, false)),
            .init(sol: ("Diğer Duran Varlık",   tlFmt(bilanco.digerDuran),  nil, false, false),
                  sag: ("",                     nil,      nil, false, false)),
            .init(sol: ("",                     nil,      nil, false, false),
                  sag: ("",                     nil,      nil, false, false)),
            .init(sol: ("TOPLAM AKTİF",         tlFmt(bilanco.toplamAktif), totBg, true, false),
                  sag: ("TOPLAM PASİF",         tlFmt(bilanco.toplamPasif), totBg, true, false)),
        ]

        for satir in satirlar {
            c.checkPage(rowH)
            bilancoSatiri(side: 0, lbl: satir.sol.lbl, val: satir.sol.val,
                          bg: satir.sol.bg, bold: satir.sol.bold, baslik: satir.sol.baslik)
            bilancoSatiri(side: 1, lbl: satir.sag.lbl, val: satir.sag.val,
                          bg: satir.sag.bg, bold: satir.sag.bold, baslik: satir.sag.baslik)
            c.y += rowH
        }

        // Denge durumu
        c.space(8)
        let dengeIcon = bilanco.dengeSaglandı ? "✓ Bilanço Dengesi Sağlandı" : "⚠ Fark: \(tlFmt(abs(bilanco.fark)))"
        let dengeBg   = bilanco.dengeSaglandı
            ? UIColor(red: 0.85, green: 0.96, blue: 0.87, alpha: 1)
            : UIColor(red: 0.98, green: 0.88, blue: 0.88, alpha: 1)
        c.fillR(CGRect(x: c.M, y: c.y, width: c.CW, height: 18), dengeBg)
        c.drawText(dengeIcon,
                   in: CGRect(x: c.M + 8, y: c.y + 4, width: c.CW - 16, height: 12),
                   size: 8.5, weight: .semibold, align: .center)
        c.y += 22
    }

    // MARK: Antet (ortak)

    private func drawAntet(_ c: BornPDFCanvas) {
        let blue = UIColor(red: 0.00, green: 0.20, blue: 0.50, alpha: 1)
        c.fillR(CGRect(x: 0, y: 0, width: c.W, height: 52), blue)

        // Logo
        if let logo = logoImage {
            let logoH: CGFloat = 36
            let logoW: CGFloat = logoH * (logo.size.width / max(logo.size.height, 1))
            logo.draw(in: CGRect(x: c.M, y: 8, width: min(logoW, 80), height: logoH))
        }

        let textX: CGFloat = logoImage != nil ? c.M + 90 : c.M
        c.drawText(sirketAdi,
                   in: CGRect(x: textX, y: 14, width: c.CW * 0.6, height: 24),
                   size: 14, weight: .bold, color: .white)

        let df = DateFormatter(); df.locale = Locale(identifier: "tr_TR"); df.dateStyle = .medium
        c.drawText("Oluşturulma: \(df.string(from: Date()))",
                   in: CGRect(x: c.M + c.CW * 0.6, y: 20, width: c.CW * 0.38, height: 14),
                   size: 8, weight: .regular, color: UIColor(white: 1, alpha: 0.7), align: .right)
        c.y = 60
    }
}

// MARK: - Sayı Formatlayıcı (virgüllü binlik)

private extension String {
    static func format(grouped value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        fmt.locale = Locale(identifier: "tr_TR")
        return fmt.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

private func tlFmt(_ v: Double) -> String {
    "\(String.format(grouped: v)) ₺"
}
