import Foundation

// MARK: - Sütun indeksleri (TXT col 0-tabanlı, rptBesinMaddeleri.txt sırası)

private enum Col {
    static let name = 0; static let code = 1; static let price = 2

    // Temel Bileşim
    static let dryMatter = 3;    static let crudeProtein = 4
    static let crudeAsh  = 5;    static let crudeFiber  = 6;   static let crudeFat = 7
    static let starch    = 8;    static let sugar        = 9
    static let ndf = 10;         static let adf = 11;           static let adl = 12

    // Enerji
    static let nel = 13;         static let me1xNRC = 14;       static let tse9610 = 15
    static let mePoultryFixed = 16
    static let ufl = 17;         static let ufv = 18

    // Protein
    static let pdie = 19;        static let pdia = 20

    // Karbonhidrat
    static let nfc = 21;         static let nsc = 22

    // Makro Mineraller
    static let availP      = 23; static let availPChick = 24
    static let calcium     = 25; static let phosphorus  = 26
    static let magnesium   = 27; static let potassium   = 28;  static let sodium = 29
    static let chlorine    = 30; static let sulfur      = 31

    // Mikro Mineraller (ppm)
    static let zinc = 32;        static let manganese = 33;    static let copper  = 34
    static let cobalt = 35;      static let iron      = 36
    static let selenium = 37;    static let iodine    = 38

    // Oran
    static let caP = 39

    // Amino – Gerçek
    static let methionine  = 40; static let lysine    = 41; static let metCys    = 42
    static let cystine     = 43; static let linoleicAcid = 44

    // Diğer
    static let dcap = 45

    // Protein parçalanabilirlik
    static let rdp = 46;         static let rup = 47;           static let rupCP = 48
    static let frakA = 49;       static let frakB = 50;         static let frakC = 51
    static let degradationRateB = 52; static let solProtein = 53
    static let tdn = 54;         static let rdsStarch = 55;     static let solubleStarch = 56

    // Kalite
    static let peletRenk = 57;   static let peletKalite = 58;   static let prestKapasite = 59
    static let negKazanc = 60

    // Protein devam
    static let ndcip = 61;       static let adicp = 62;          static let paf = 63
    static let totalPhosphorus = 64

    // Amino – Sindirilebilir
    static let sinMethionine = 65; static let sinLysine  = 66; static let sinMetCys = 67
    static let sinCystine    = 68; static let tryptophan = 69; static let sinTryptophan = 70

    // Enerji – Sabit/Formüllü
    static let meRuminantFixed = 71
    static let meRumAlderman   = 72; static let meRumMaff     = 73
    static let mePoultryCC     = 74; static let mePoultryECNFE = 75
    static let mePoultryEC     = 76; static let mePoultryCobb  = 77

    // Amino – Gerçek devam
    static let arginine    = 78; static let sinArginine   = 79
    static let sinThreonine = 80; static let threonine    = 81
    static let leucine     = 82; static let sinLeucine    = 83
    static let isoleucine  = 84; static let sinIsoleucine = 85
    static let valine      = 86; static let sinValine     = 87
    static let phenylalanin = 88; static let sinPhenylalanin = 89
    static let phenyTyr    = 90; static let glycine       = 91
    static let histidine   = 92; static let sinHistidine  = 93
    static let pdin        = 94; static let tyrosine      = 95
    static let serine      = 96; static let proline       = 97
    static let alanine     = 98; static let asparticAcid  = 99
    static let glutamicAcid = 100; static let glySer      = 101

    // Yağ Asitleri
    static let linolenicAcid   = 102; static let arachidonicAcid = 103
    static let choline         = 104; static let lauricAcid      = 105
    static let myristicAcid    = 106; static let palmiticAcid    = 107
    static let palmoleicAcid   = 108; static let stearicAcid     = 109
    static let oleicAcid       = 110; static let unsatFattyAcid  = 111
    static let satFattyAcid    = 112; static let freeFat         = 113
    static let totalFattyAcid  = 114

    // Oranlar
    static let metLys  = 115; static let mCLys   = 116
    static let argLys  = 117; static let threLys = 118; static let leuLys = 119
    static let valLys  = 120; static let trpLys  = 121; static let nfe    = 122

    // Sindirim Katsayıları
    static let sinMethCoeff = 123; static let sinLysCoeff  = 124; static let sinCysCoeff = 125
    static let sinArgCoeff  = 126; static let sinThrCoeff  = 127; static let sinLeuCoeff = 128
    static let sinIsoCoeff  = 129; static let sinValCoeff  = 130; static let sinTryCoeff = 131
    static let sinPheCoeff  = 132; static let sinHisCoeff  = 133
    static let aldermanCoeff = 134; static let maffCoeff   = 135
    static let ccCoeff       = 136; static let ecNFECoeff  = 137
    static let ecCoeff       = 138; static let cobbCoeff   = 139

    // Nişasta Detay
    static let slowStarch   = 140; static let solStarchPct = 141; static let bypassStarch = 142

    // Son
    static let organicMatter = 143; static let maffME = 144
}

// MARK: - Parser

struct IngredientImporter {

    // "14.000,00" → 14000.0
    static func trDouble(_ s: String) -> Double? {
        let c = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return c.isEmpty ? nil : Double(c)
    }

    private static func parseLine(_ cols: [String], src: String) -> FeedIngredientCandidate? {
        guard cols.count > 2 else { return nil }
        let name = cols[Col.name].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let code = cols[Col.code].trimmingCharacters(in: .whitespaces)

        func d(_ i: Int) -> Double? { i < cols.count ? trDouble(cols[i]) : nil }

        var c = FeedIngredientCandidate(name: name, code: code)
        c.sourceFile        = src
        c.priceTL           = d(Col.price)

        // Temel
        c.dryMatter         = d(Col.dryMatter);   c.crudeProtein = d(Col.crudeProtein)
        c.crudeAsh          = d(Col.crudeAsh);    c.crudeFiber   = d(Col.crudeFiber)
        c.crudeFat          = d(Col.crudeFat);    c.starch       = d(Col.starch)
        c.sugar             = d(Col.sugar);        c.ndf          = d(Col.ndf)
        c.adf               = d(Col.adf);          c.adl          = d(Col.adl)
        c.nfc               = d(Col.nfc);          c.nsc          = d(Col.nsc)
        c.nfe               = d(Col.nfe);          c.organicMatter = d(Col.organicMatter)

        // Enerji
        c.nel               = d(Col.nel);          c.me1xNRC      = d(Col.me1xNRC)
        c.tse9610           = d(Col.tse9610);      c.mePoultryFixed = d(Col.mePoultryFixed)
        c.meRuminantFixed   = d(Col.meRuminantFixed)
        c.ufl               = d(Col.ufl);          c.ufv          = d(Col.ufv)
        c.negKazanc         = d(Col.negKazanc);    c.maffME       = d(Col.maffME)

        // Formüllü Enerji
        c.meRumAlderman     = d(Col.meRumAlderman); c.meRumMaff   = d(Col.meRumMaff)
        c.mePoultryCC       = d(Col.mePoultryCC);   c.mePoultryECNFE = d(Col.mePoultryECNFE)
        c.mePoultryEC       = d(Col.mePoultryEC);   c.mePoultryCobb  = d(Col.mePoultryCobb)

        // Protein
        c.pdie              = d(Col.pdie);         c.pdia         = d(Col.pdia)
        c.pdin              = d(Col.pdin);         c.rdp          = d(Col.rdp)
        c.rup               = d(Col.rup);          c.rupCP        = d(Col.rupCP)
        c.frakA             = d(Col.frakA);        c.frakB        = d(Col.frakB)
        c.frakC             = d(Col.frakC);        c.degradationRateB = d(Col.degradationRateB)
        c.solProtein        = d(Col.solProtein);   c.ndcip        = d(Col.ndcip)
        c.adicp             = d(Col.adicp)

        // Karbonhidrat
        c.tdn               = d(Col.tdn);          c.rdsStarch    = d(Col.rdsStarch)
        c.solubleStarch     = d(Col.solubleStarch); c.slowStarch  = d(Col.slowStarch)
        c.solStarchPct      = d(Col.solStarchPct);  c.bypassStarch = d(Col.bypassStarch)

        // Makro Mineraller
        c.calcium           = d(Col.calcium);      c.phosphorus   = d(Col.phosphorus)
        c.totalPhosphorus   = d(Col.totalPhosphorus); c.availP    = d(Col.availP)
        c.availPChick       = d(Col.availPChick);  c.magnesium    = d(Col.magnesium)
        c.potassium         = d(Col.potassium);    c.sodium       = d(Col.sodium)
        c.chlorine          = d(Col.chlorine);     c.sulfur       = d(Col.sulfur)
        c.caP               = d(Col.caP)

        // Mikro Mineraller
        c.zinc              = d(Col.zinc);         c.manganese    = d(Col.manganese)
        c.copper            = d(Col.copper);       c.cobalt       = d(Col.cobalt)
        c.iron              = d(Col.iron);         c.selenium     = d(Col.selenium)
        c.iodine            = d(Col.iodine)

        // Amino – Gerçek
        c.methionine        = d(Col.methionine);   c.lysine       = d(Col.lysine)
        c.metCys            = d(Col.metCys);       c.cystine      = d(Col.cystine)
        c.tryptophan        = d(Col.tryptophan);   c.arginine     = d(Col.arginine)
        c.threonine         = d(Col.threonine);    c.leucine      = d(Col.leucine)
        c.isoleucine        = d(Col.isoleucine);   c.valine       = d(Col.valine)
        c.phenylalanin      = d(Col.phenylalanin); c.phenyTyr     = d(Col.phenyTyr)
        c.glycine           = d(Col.glycine);      c.histidine    = d(Col.histidine)
        c.tyrosine          = d(Col.tyrosine);     c.serine       = d(Col.serine)
        c.proline           = d(Col.proline);      c.alanine      = d(Col.alanine)
        c.asparticAcid      = d(Col.asparticAcid); c.glutamicAcid = d(Col.glutamicAcid)
        c.glySer            = d(Col.glySer)

        // Amino – Sindirilebilir
        c.sinMethionine     = d(Col.sinMethionine); c.sinLysine   = d(Col.sinLysine)
        c.sinMetCys         = d(Col.sinMetCys);     c.sinCystine  = d(Col.sinCystine)
        c.sinTryptophan     = d(Col.sinTryptophan); c.sinArginine = d(Col.sinArginine)
        c.sinThreonine      = d(Col.sinThreonine);  c.sinLeucine  = d(Col.sinLeucine)
        c.sinIsoleucine     = d(Col.sinIsoleucine); c.sinValine   = d(Col.sinValine)
        c.sinPhenylalanin   = d(Col.sinPhenylalanin); c.sinHistidine = d(Col.sinHistidine)

        // Yağ Asitleri
        c.linoleicAcid      = d(Col.linoleicAcid); c.linolenicAcid   = d(Col.linolenicAcid)
        c.arachidonicAcid   = d(Col.arachidonicAcid); c.choline       = d(Col.choline)
        c.lauricAcid        = d(Col.lauricAcid);   c.myristicAcid    = d(Col.myristicAcid)
        c.palmiticAcid      = d(Col.palmiticAcid); c.palmoleicAcid   = d(Col.palmoleicAcid)
        c.stearicAcid       = d(Col.stearicAcid);  c.oleicAcid       = d(Col.oleicAcid)
        c.unsatFattyAcid    = d(Col.unsatFattyAcid); c.satFattyAcid  = d(Col.satFattyAcid)
        c.freeFat           = d(Col.freeFat);       c.totalFattyAcid  = d(Col.totalFattyAcid)

        // Oranlar
        c.metLys  = d(Col.metLys);  c.mCLys   = d(Col.mCLys);   c.argLys  = d(Col.argLys)
        c.threLys = d(Col.threLys); c.leuLys   = d(Col.leuLys);  c.valLys  = d(Col.valLys)
        c.trpLys  = d(Col.trpLys)

        // Katsayılar
        c.sinMethCoeff  = d(Col.sinMethCoeff);  c.sinLysCoeff  = d(Col.sinLysCoeff)
        c.sinCysCoeff   = d(Col.sinCysCoeff);   c.sinArgCoeff  = d(Col.sinArgCoeff)
        c.sinThrCoeff   = d(Col.sinThrCoeff);   c.sinLeuCoeff  = d(Col.sinLeuCoeff)
        c.sinIsoCoeff   = d(Col.sinIsoCoeff);   c.sinValCoeff  = d(Col.sinValCoeff)
        c.sinTryCoeff   = d(Col.sinTryCoeff);   c.sinPheCoeff  = d(Col.sinPheCoeff)
        c.sinHisCoeff   = d(Col.sinHisCoeff);   c.aldermanCoeff = d(Col.aldermanCoeff)
        c.maffCoeff     = d(Col.maffCoeff);     c.ccCoeff      = d(Col.ccCoeff)
        c.ecNFECoeff    = d(Col.ecNFECoeff);    c.ecCoeff      = d(Col.ecCoeff)
        c.cobbCoeff     = d(Col.cobbCoeff)

        // Kalite
        c.dcap          = d(Col.dcap);          c.peletRenk    = d(Col.peletRenk)
        c.peletKalite   = d(Col.peletKalite);   c.prestKapasite = d(Col.prestKapasite)
        c.paf           = d(Col.paf)

        return c
    }

    // MARK: - Ana fonksiyon

    static func preview(url: URL) throws -> [FeedIngredientCandidate] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [.windowsCP1254, .isoLatin1, .utf8]
        guard let raw = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first else {
            throw ImportError.unreadableEncoding
        }

        let src   = url.lastPathComponent
        let lines = raw.components(separatedBy: .newlines)
        let items = lines.dropFirst(2).compactMap { line -> FeedIngredientCandidate? in
            parseLine(line.components(separatedBy: "\t"), src: src)
        }
        if items.isEmpty { throw ImportError.noDataRows }
        return items
    }

    enum ImportError: LocalizedError {
        case unreadableEncoding, noDataRows
        var errorDescription: String? {
            switch self {
            case .unreadableEncoding: return "Dosya kodlaması okunamadı."
            case .noDataRows: return "Geçerli hammadde satırı bulunamadı. TAB ayraçlı TXT dosyası seçtiğinizden emin olun."
            }
        }
    }
}
