import Foundation
import Compression

// MARK: - Bilanço Excel (.xlsx) Üretici
// Harici kütüphane kullanmadan saf Swift OOXML/ZIP ile .xlsx üretir.
// Windows Excel'de açılır; OTO hücreler kilitli+gri, MANUEL hücreler açık.

struct BilancoXLSXService {

    let bilanco: CeyrekBilanco
    let sirketAdi: String

    init(bilanco: CeyrekBilanco, sirketAdi: String) {
        self.bilanco   = bilanco
        self.sirketAdi = sirketAdi
    }

    // `mutating` çünkü shared string tablosunu (`strings`) dolduruyoruz.
    // Çağıran: `var svc = BilancoXLSXService(...); svc.generate()`
    mutating func generate() -> Data {
        // Sayfalar önce oluşturulur — bu sırada `strings` tablosu dolar
        let s1 = sheet1GelirTablosu()
        let s2 = sheet2Bilanco()
        let s3 = sheet3Notlar()

        var files: [String: Data] = [:]
        files["[Content_Types].xml"]            = contentTypes
        files["_rels/.rels"]                    = rootRels
        files["xl/workbook.xml"]                = workbook
        files["xl/_rels/workbook.xml.rels"]     = workbookRels
        files["xl/styles.xml"]                  = styles
        files["xl/sharedStrings.xml"]           = sharedStrings  // strings tablosu hazır
        files["xl/worksheets/sheet1.xml"]       = s1
        files["xl/worksheets/sheet2.xml"]       = s2
        files["xl/worksheets/sheet3.xml"]       = s3

        return buildZip(files)
    }

    // MARK: - Sayı Yardımcıları

    private func n(_ v: Double) -> String { String(Int(v.rounded())) }
    private func q(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }

    // MARK: - Hücre Stilleri
    // 0=normal, 1=baslik(bold+mavi-bg), 2=oto(gri-bg+kilitli), 3=tutar-oto, 4=toplam(bold+mavi-bg), 5=manuel-tutar

    private var styles: Data {
        let xml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="4">
    <font><sz val="10"/><name val="Calibri"/></font>
    <font><sz val="10"/><b/><name val="Calibri"/></font>
    <font><sz val="10"/><name val="Calibri"/><color rgb="FF666666"/></font>
    <font><sz val="11"/><b/><name val="Calibri"/><color rgb="FF003380"/></font>
  </fonts>
  <fills count="5">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFD4E3F5"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFE8E8E8"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFDAEFDC"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/></border>
    <border><left style="thin"><color rgb="FFC0C0C0"/></left><right style="thin"><color rgb="FFC0C0C0"/></right><top style="thin"><color rgb="FFC0C0C0"/></top><bottom style="thin"><color rgb="FFC0C0C0"/></bottom></border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="7">
    <xf numFmtId="0"  fontId="0" fillId="0" borderId="1" xfId="0"><alignment wrapText="1"/></xf>
    <xf numFmtId="0"  fontId="3" fillId="2" borderId="1" xfId="0"><alignment horizontal="center"/></xf>
    <xf numFmtId="0"  fontId="2" fillId="3" borderId="1" xfId="0"/>
    <xf numFmtId="#,##0" fontId="2" fillId="3" borderId="1" xfId="0"><alignment horizontal="right"/></xf>
    <xf numFmtId="#,##0" fontId="1" fillId="2" borderId="1" xfId="0"><alignment horizontal="right"/></xf>
    <xf numFmtId="#,##0" fontId="0" fillId="0" borderId="1" xfId="0"><alignment horizontal="right"/></xf>
    <xf numFmtId="0"  fontId="1" fillId="2" borderId="1" xfId="0"/>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
  <numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0"/></numFmts>
</styleSheet>
"""
        return Data(xml.utf8)
    }

    // Stil indeksleri:
    // 0 = normal metin
    // 1 = başlık (mavi bg, beyaz bold)
    // 2 = oto-metin (gri bg, gri font)
    // 3 = oto-sayı  (gri bg, gri font, sağ hizalı)
    // 4 = toplam-sayı (mavi bg, bold)
    // 5 = manuel-sayı (beyaz bg, siyah, sağ hizalı)
    // 6 = başlık-metin (mavi bg, bold)

    // MARK: - Paylaşılan Stringler

    private var strings: [String] = []

    private mutating func s(_ str: String) -> Int {
        if let i = strings.firstIndex(of: str) { return i }
        strings.append(str); return strings.count - 1
    }

    private var sharedStrings: Data {
        var entries = ""
        for str in strings { entries += "<si><t>\(q(str))</t></si>" }
        let xml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(strings.count)" uniqueCount="\(strings.count)">\(entries)</sst>
"""
        return Data(xml.utf8)
    }

    // MARK: - Sayfa 1: Gelir Tablosu

    private mutating func sheet1GelirTablosu() -> Data {
        var rows: [String] = []

        func txtCell(_ col: String, _ row: Int, _ text: String, style: Int = 0) -> String {
            let si = s(text)
            return "<c r=\"\(col)\(row)\" t=\"s\" s=\"\(style)\"><v>\(si)</v></c>"
        }
        func numCell(_ col: String, _ row: Int, _ val: Double, style: Int = 3) -> String {
            "<c r=\"\(col)\(row)\" s=\"\(style)\"><v>\(Int(val.rounded()))</v></c>"
        }
        func fmlCell(_ col: String, _ row: Int, _ fml: String, style: Int = 4) -> String {
            "<c r=\"\(col)\(row)\" s=\"\(style)\"><f>\(fml)</f><v>0</v></c>"
        }
        func emptyCell(_ col: String, _ row: Int, style: Int = 0) -> String {
            "<c r=\"\(col)\(row)\" s=\"\(style)\"/>"
        }

        let baslik = "\(sirketAdi) — Çeyreklik Gelir Tablosu \(bilanco.kisaBaslik) (\(bilanco.ceyrekBasligi) \(bilanco.yil))"

        // Satır 1: Başlık
        rows.append("<row r=\"1\">\(txtCell("A", 1, baslik, style: 6))</row>")
        // Satır 2: boş
        rows.append("<row r=\"2\"><c r=\"A2\"/></row>")
        // Satır 3: sütun başlıkları
        rows.append("<row r=\"3\">\(txtCell("A", 3, "KALEM", style: 1))\(txtCell("B", 3, "TUTAR (₺)", style: 1))\(txtCell("C", 3, "AÇIKLAMA", style: 1))</row>")

        // Satır 4: Net Satışlar — MANUEL
        rows.append("<row r=\"4\">\(txtCell("A", 4, "Net Satışlar"))\(emptyCell("B", 4, style: 5))\(txtCell("C", 4, "Muhasebe girişi (elle dolu)"))</row>")

        // Satır 5: SMM — OTO
        rows.append("<row r=\"5\">\(txtCell("A", 5, "(-) Satılan Mal Maliyeti (SMM)", style: 2))\(numCell("B", 5, bilanco.smmOto, style: 3))\(txtCell("C", 5, "Oto-hesaplanan", style: 2))</row>")

        // Satır 6: Diğer satış maliyeti — MANUEL
        rows.append("<row r=\"6\">\(txtCell("A", 6, "(-) Diğer Satış Maliyeti"))\(emptyCell("B", 6, style: 5))\(txtCell("C", 6, "Muhasebe girişi"))</row>")

        // Satır 7: Brüt Kâr — FORMÜL
        rows.append("<row r=\"7\">\(txtCell("A", 7, "BRÜT KÂR", style: 6))\(fmlCell("B", 7, "B4-B5-B6"))\(txtCell("C", 7, "= Net Satışlar − SMM − Diğer"))</row>")

        // Satır 8: boş
        rows.append("<row r=\"8\"><c r=\"A8\"/></row>")

        // Satır 9: Operasyonel Giderler — OTO
        rows.append("<row r=\"9\">\(txtCell("A", 9, "(-) Operasyonel Giderler (Oto)", style: 2))\(numCell("B", 9, bilanco.opGiderOto, style: 3))\(txtCell("C", 9, "Oto-hesaplanan", style: 2))</row>")

        // Satır 10: Ek Giderler — MANUEL
        rows.append("<row r=\"10\">\(txtCell("A", 10, "(-) Ek Giderler / Olağandışı"))\(emptyCell("B", 10, style: 5))\(txtCell("C", 10, "Muhasebe girişi"))</row>")

        // Satır 11: Net Kâr — FORMÜL
        rows.append("<row r=\"11\">\(txtCell("A", 11, "DÖNEM NET KARI", style: 6))\(fmlCell("B", 11, "B7-B9-B10"))\(txtCell("C", 11, "= Brüt Kâr − Giderler"))</row>")

        // Sütun genişlikleri
        let cols = "<col min=\"1\" max=\"1\" width=\"36\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"18\" customWidth=\"1\"/><col min=\"3\" max=\"3\" width=\"28\" customWidth=\"1\"/>"

        let xml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetProtection sheet="1" password="" selectLockedCells="0" selectUnlockedCells="0"/>
  <cols>\(cols)</cols>
  <sheetData>\(rows.joined())</sheetData>
  <mergeCells><mergeCell ref="A1:C1"/></mergeCells>
</worksheet>
"""
        return Data(xml.utf8)
    }

    // MARK: - Sayfa 2: Bilanço

    private mutating func sheet2Bilanco() -> Data {
        var rows: [String] = []

        func t(_ col: String, _ row: Int, _ text: String, style: Int = 0) -> String {
            "<c r=\"\(col)\(row)\" t=\"s\" s=\"\(style)\"><v>\(s(text))</v></c>"
        }
        func n(_ col: String, _ row: Int, _ val: Double, style: Int = 3) -> String {
            "<c r=\"\(col)\(row)\" s=\"\(style)\"><v>\(Int(val.rounded()))</v></c>"
        }
        func f(_ col: String, _ row: Int, _ fml: String, style: Int = 4) -> String {
            "<c r=\"\(col)\(row)\" s=\"\(style)\"><f>\(fml)</f><v>0</v></c>"
        }
        func e(_ col: String, _ row: Int, style: Int = 0) -> String {
            "<c r=\"\(col)\(row)\" s=\"\(style)\"/>"
        }

        let baslik = "\(sirketAdi) — Bilanço \(bilanco.kisaBaslik)"
        rows.append("<row r=\"1\">\(t("A", 1, baslik, style: 6))</row>")
        rows.append("<row r=\"2\"><c r=\"A2\"/></row>")

        // Başlık: AKTİF | PASİF
        rows.append("<row r=\"3\">\(t("A", 3, "AKTİF", style: 1))\(e("B", 3, style: 1))\(t("C", 3, "PASİF", style: 1))\(e("D", 3, style: 1))</row>")

        // Satır 4: DÖNEN VARLIKLAR | KISA VADELİ BORÇLAR (başlıklar)
        rows.append("<row r=\"4\">\(t("A", 4, "DÖNEN VARLIKLAR", style: 2))\(e("B", 4, style: 2))\(t("C", 4, "KISA VADELİ BORÇLAR", style: 2))\(e("D", 4, style: 2))</row>")

        // Satır 5: Nakit | Ticari Borçlar
        rows.append("<row r=\"5\">\(t("A", 5, "Nakit / Banka"))\(e("B", 5, style: 5))\(t("C", 5, "Ticari Borçlar"))\(e("D", 5, style: 5))</row>")

        // Satır 6: Ticari Alacaklar | Diğer Kısa Vadeli
        rows.append("<row r=\"6\">\(t("A", 6, "Ticari Alacaklar"))\(e("B", 6, style: 5))\(t("C", 6, "Diğer Kısa Vadeli Borçlar"))\(e("D", 6, style: 5))</row>")

        // Satır 7: Stok (OTO) | UZUN VADELİ BORÇLAR
        rows.append("<row r=\"7\">\(t("A", 7, "Stok", style: 2))\(n("B", 7, bilanco.stokOto, style: 3))\(t("C", 7, "UZUN VADELİ BORÇLAR", style: 2))\(e("D", 7, style: 2))</row>")

        // Satır 8: Diğer Dönen | Banka Kredisi
        rows.append("<row r=\"8\">\(t("A", 8, "Diğer Dönen Varlık"))\(e("B", 8, style: 5))\(t("C", 8, "Banka Kredileri"))\(e("D", 8, style: 5))</row>")

        // Satır 9: boş
        rows.append("<row r=\"9\">\(e("A", 9))\(e("B", 9))\(e("C", 9))\(e("D", 9))</row>")

        // Satır 10: DURAN VARLIKLAR | ÖZ KAYNAK
        rows.append("<row r=\"10\">\(t("A", 10, "DURAN VARLIKLAR", style: 2))\(e("B", 10, style: 2))\(t("C", 10, "ÖZ KAYNAK", style: 2))\(e("D", 10, style: 2))</row>")

        // Satır 11: Sabit Kıymet Brüt | Sermaye
        rows.append("<row r=\"11\">\(t("A", 11, "Sabit Kıymet (Brüt)"))\(e("B", 11, style: 5))\(t("C", 11, "Ödenmiş Sermaye"))\(e("D", 11, style: 5))</row>")

        // Satır 12: Birik Amortisman | Geçmiş Yıl Karları
        rows.append("<row r=\"12\">\(t("A", 12, "Birikmiş Amortisman (−)"))\(e("B", 12, style: 5))\(t("C", 12, "Geçmiş Yıl Karları"))\(e("D", 12, style: 5))</row>")

        // Satır 13: Sabit Kıymet Net (formül) | Dönem Net Karı (Gelir Tablosu'ndan)
        rows.append("<row r=\"13\">\(t("A", 13, "Sabit Kıymet (Net)", style: 2))\(f("B", 13, "B11-B12", style: 4))\(t("C", 13, "Dönem Net Karı", style: 2))\(f("D", 13, "Gelir_Tablosu!B11", style: 4))</row>")

        // Satır 14: Diğer Duran | boş
        rows.append("<row r=\"14\">\(t("A", 14, "Diğer Duran Varlık"))\(e("B", 14, style: 5))\(e("C", 14))\(e("D", 14))</row>")

        // Satır 15: boş
        rows.append("<row r=\"15\">\(e("A", 15))\(e("B", 15))\(e("C", 15))\(e("D", 15))</row>")

        // Satır 16: TOPLAM AKTİF | TOPLAM PASİF
        rows.append("<row r=\"16\">\(t("A", 16, "TOPLAM AKTİF", style: 6))\(f("B", 16, "B5+B6+B7+B8+B11-B12+B14", style: 4))\(t("C", 16, "TOPLAM PASİF", style: 6))\(f("D", 16, "D5+D6+D8+D11+D12+Gelir_Tablosu!B11", style: 4))</row>")

        // Satır 17: Denge kontrolü
        rows.append("<row r=\"17\">\(t("A", 17, "Denge Kontrolü (0 olmalı)"))\(f("B", 17, "B16-D16", style: 5))\(e("C", 17))\(e("D", 17))</row>")

        let cols = "<col min=\"1\" max=\"1\" width=\"26\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"16\" customWidth=\"1\"/><col min=\"3\" max=\"3\" width=\"26\" customWidth=\"1\"/><col min=\"4\" max=\"4\" width=\"16\" customWidth=\"1\"/>"

        let xml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetProtection sheet="1" password="" selectLockedCells="0" selectUnlockedCells="0"/>
  <cols>\(cols)</cols>
  <sheetData>\(rows.joined())</sheetData>
  <mergeCells><mergeCell ref="A1:D1"/><mergeCell ref="A3:B3"/><mergeCell ref="C3:D3"/></mergeCells>
</worksheet>
"""
        return Data(xml.utf8)
    }

    // MARK: - Sayfa 3: Notlar

    private mutating func sheet3Notlar() -> Data {
        let xml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s" s="6"><v>\(s("NOTLAR — \(bilanco.kisaBaslik)"))</v></c></row>
    <row r="2"><c r="A2" t="s" s="0"><v>\(s("Bu sayfa muhasebeciye ayrılmıştır. El yazısıyla not alınabilir veya dijital olarak doldurulabilir."))</v></c></row>
    <row r="3"><c r="A3"/></row>
    <row r="4"><c r="A4" t="s"><v>\(s("Not 1:"))</v></c></row>
    <row r="8"><c r="A8" t="s"><v>\(s("Not 2:"))</v></c></row>
    <row r="12"><c r="A12" t="s"><v>\(s("Not 3:"))</v></c></row>
    <row r="16"><c r="A16" t="s"><v>\(s("Not 4:"))</v></c></row>
  </sheetData>
  <rowBreaks count="4" manualBreakCount="4">
    <brk id="7" max="1048575" man="1"/><brk id="11" max="1048575" man="1"/>
    <brk id="15" max="1048575" man="1"/><brk id="19" max="1048575" man="1"/>
  </rowBreaks>
</worksheet>
"""
        return Data(xml.utf8)
    }

    // MARK: - OOXML Altyapısı

    private var contentTypes: Data {
        Data("""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>
""".utf8)
    }

    private var rootRels: Data {
        Data("""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
""".utf8)
    }

    private var workbook: Data {
        let baslik = q("\(bilanco.kisaBaslik) Bilançosu")
        return Data("""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <fileVersion appName="xl" lastEdited="5" lowestEdited="5"/>
  <workbookPr date1904="0"/>
  <sheets>
    <sheet name="Gelir Tablosu" sheetId="1" r:id="rId1"/>
    <sheet name="Bilanço" sheetId="2" r:id="rId2"/>
    <sheet name="Notlar" sheetId="3" r:id="rId3"/>
  </sheets>
  <definedNames>
    <definedName name="Gelir_Tablosu">Gelir Tablosu!$A$1:$C$20</definedName>
  </definedNames>
</workbook>
""".utf8)
    }

    private var workbookRels: Data {
        Data("""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
  <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
""".utf8)
    }

    // MARK: - Minimal ZIP Üretici (PKZIP Local File + Central Directory)

    private func buildZip(_ files: [String: Data]) -> Data {
        var zip = Data()
        var centralDir: [(offset: UInt32, entry: Data)] = []

        for (name, content) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(content)
            let offset = UInt32(zip.count)

            // Local file header
            var local = Data()
            local += uint16le(0x4B50)  // PK
            local += uint16le(0x0403)  // local sig
            local += uint16le(0x0014)  // version needed
            local += uint16le(0x0000)  // flags
            local += uint16le(0x0000)  // compression: stored
            local += uint16le(0x0000); local += uint16le(0x0000) // mod time/date
            local += uint32le(crc)
            local += uint32le(UInt32(content.count))
            local += uint32le(UInt32(content.count))
            local += uint16le(UInt16(nameData.count))
            local += uint16le(0x0000)  // extra len
            local += nameData
            local += content
            zip += local

            // Central directory entry
            var cd = Data()
            cd += uint16le(0x4B50); cd += uint16le(0x0201)  // central sig
            cd += uint16le(0x0014); cd += uint16le(0x0014)  // version made/needed
            cd += uint16le(0x0000); cd += uint16le(0x0000)  // flags, compression
            cd += uint16le(0x0000); cd += uint16le(0x0000)  // time, date
            cd += uint32le(crc)
            cd += uint32le(UInt32(content.count)); cd += uint32le(UInt32(content.count))
            cd += uint16le(UInt16(nameData.count)); cd += uint16le(0x0000); cd += uint16le(0x0000)
            cd += uint16le(0x0000); cd += uint16le(0x0000); cd += uint32le(0x0000)  // disk, attr
            cd += uint32le(offset)
            cd += nameData
            centralDir.append((offset: offset, entry: cd))
        }

        let cdStart = UInt32(zip.count)
        var cdData = Data()
        for item in centralDir { cdData += item.entry }
        zip += cdData

        // End of central directory
        var eocd = Data()
        eocd += uint16le(0x4B50); eocd += uint16le(0x0605)  // EOCD sig
        eocd += uint16le(0x0000); eocd += uint16le(0x0000)  // disk numbers
        eocd += uint16le(UInt16(centralDir.count)); eocd += uint16le(UInt16(centralDir.count))
        eocd += uint32le(UInt32(cdData.count)); eocd += uint32le(cdStart)
        eocd += uint16le(0x0000)  // comment len
        zip += eocd

        return zip
    }

    private func uint16le(_ v: UInt16) -> Data {
        var val = v.littleEndian; return Data(bytes: &val, count: 2)
    }
    private func uint32le(_ v: UInt32) -> Data {
        var val = v.littleEndian; return Data(bytes: &val, count: 4)
    }

    private func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Convenience + operatör

private func += (lhs: inout Data, rhs: Data) { lhs.append(rhs) }
