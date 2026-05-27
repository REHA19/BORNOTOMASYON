import SwiftData
import Foundation

@Model
final class FeedIngredient {

    var name: String        = ""
    var code: String        = ""
    var priceTL: Double?
    var importedAt: Date    = Date()
    var sourceFile: String  = ""
    var isAvailable: Bool   = true   // false → stokta yok, tüm formüllerden dışlanır

    // ── 1. Temel Bileşim ──
    var dryMatter:    Double?
    var crudeProtein: Double?
    var crudeAsh:     Double?
    var crudeFiber:   Double?
    var crudeFat:     Double?
    var starch:       Double?
    var sugar:        Double?
    var ndf:          Double?
    var adf:          Double?
    var adl:          Double?
    var nfc:          Double?
    var nsc:          Double?
    var nfe:          Double?
    var organicMatter:Double?

    // ── 2. Enerji ──
    var nel:             Double?
    var me1xNRC:         Double?
    var tse9610:         Double?
    var mePoultryFixed:  Double?
    var meRuminantFixed: Double?
    var ufl:             Double?
    var ufv:             Double?
    var negKazanc:       Double?
    var maffME:          Double?

    // ── 3. Formüllü Enerji ──
    var meRumAlderman:  Double?
    var meRumMaff:      Double?
    var mePoultryCC:    Double?
    var mePoultryECNFE: Double?
    var mePoultryEC:    Double?
    var mePoultryCobb:  Double?

    // ── 4. Protein Parçalanabilirliği ──
    var pdie:            Double?
    var pdia:            Double?
    var pdin:            Double?
    var rdp:             Double?
    var rup:             Double?
    var rupCP:           Double?
    var frakA:           Double?
    var frakB:           Double?
    var frakC:           Double?
    var degradationRateB:Double?
    var solProtein:      Double?
    var ndcip:           Double?
    var adicp:           Double?

    // ── 5. Karbonhidrat Detay ──
    var tdn:           Double?
    var rdsStarch:     Double?
    var solubleStarch: Double?
    var slowStarch:    Double?
    var solStarchPct:  Double?
    var bypassStarch:  Double?

    // ── 6. Makro Mineraller ──
    var calcium:         Double?
    var phosphorus:      Double?
    var totalPhosphorus: Double?
    var availP:          Double?
    var availPChick:     Double?
    var magnesium:       Double?
    var potassium:       Double?
    var sodium:          Double?
    var chlorine:        Double?
    var sulfur:          Double?
    var caP:             Double?

    // ── 7. Mikro Mineraller (ppm) ──
    var zinc:      Double?
    var manganese: Double?
    var copper:    Double?
    var cobalt:    Double?
    var iron:      Double?
    var selenium:  Double?
    var iodine:    Double?

    // ── 8. Amino Asitler – Gerçek ──
    var methionine:  Double?
    var lysine:      Double?
    var metCys:      Double?
    var cystine:     Double?
    var tryptophan:  Double?
    var arginine:    Double?
    var threonine:   Double?
    var leucine:     Double?
    var isoleucine:  Double?
    var valine:      Double?
    var phenylalanin:Double?
    var phenyTyr:    Double?
    var glycine:     Double?
    var histidine:   Double?
    var tyrosine:    Double?
    var serine:      Double?
    var proline:     Double?
    var alanine:     Double?
    var asparticAcid:Double?
    var glutamicAcid:Double?
    var glySer:      Double?

    // ── 9. Amino Asitler – Sindirilebilir ──
    var sinMethionine:  Double?
    var sinLysine:      Double?
    var sinMetCys:      Double?
    var sinCystine:     Double?
    var sinTryptophan:  Double?
    var sinArginine:    Double?
    var sinThreonine:   Double?
    var sinLeucine:     Double?
    var sinIsoleucine:  Double?
    var sinValine:      Double?
    var sinPhenylalanin:Double?
    var sinHistidine:   Double?

    // ── 10. Yağ Asitleri ──
    var linoleicAcid:    Double?
    var linolenicAcid:   Double?
    var arachidonicAcid: Double?
    var choline:         Double?
    var lauricAcid:      Double?
    var myristicAcid:    Double?
    var palmiticAcid:    Double?
    var palmoleicAcid:   Double?
    var stearicAcid:     Double?
    var oleicAcid:       Double?
    var unsatFattyAcid:  Double?
    var satFattyAcid:    Double?
    var freeFat:         Double?
    var totalFattyAcid:  Double?

    // ── 11. Oranlar ──
    var metLys:  Double?
    var mCLys:   Double?
    var argLys:  Double?
    var threLys: Double?
    var leuLys:  Double?
    var valLys:  Double?
    var trpLys:  Double?

    // ── 12. Sindirim Katsayıları ──
    var sinMethCoeff: Double?
    var sinLysCoeff:  Double?
    var sinCysCoeff:  Double?
    var sinArgCoeff:  Double?
    var sinThrCoeff:  Double?
    var sinLeuCoeff:  Double?
    var sinIsoCoeff:  Double?
    var sinValCoeff:  Double?
    var sinTryCoeff:  Double?
    var sinPheCoeff:  Double?
    var sinHisCoeff:  Double?
    var aldermanCoeff:Double?
    var maffCoeff:    Double?
    var ccCoeff:      Double?
    var ecNFECoeff:   Double?
    var ecCoeff:      Double?
    var cobbCoeff:    Double?

    // ── 13. Kalite / Diğer ──
    var dcap:         Double?
    var peletRenk:    Double?
    var peletKalite:  Double?
    var prestKapasite:Double?
    var paf:          Double?

    // ── Kullanıcı tanımlı ek kriterler ──
    var extrasJSON: String?

    var extras: [String: Double] {
        get {
            guard let j = extrasJSON,
                  let data = j.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: Double].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            extrasJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? nil
        }
    }

    // MARK: - Init from candidate

    init(from c: FeedIngredientCandidate) {
        name = c.name; code = c.code; priceTL = c.priceTL
        importedAt = Date(); sourceFile = c.sourceFile
        apply(c)
        extrasJSON = nil
    }

    // MARK: - Manual init

    init(name: String, code: String = "", priceTL: Double? = nil) {
        self.name = name; self.code = code; self.priceTL = priceTL
        importedAt = Date(); sourceFile = "Manuel"
        extrasJSON = nil
    }

    // MARK: - Update

    func update(from c: FeedIngredientCandidate) {
        code = c.code; priceTL = c.priceTL
        importedAt = Date(); sourceFile = c.sourceFile
        apply(c)
    }

    private func apply(_ c: FeedIngredientCandidate) {
        dryMatter = c.dryMatter; crudeProtein = c.crudeProtein
        crudeAsh = c.crudeAsh; crudeFiber = c.crudeFiber; crudeFat = c.crudeFat
        starch = c.starch; sugar = c.sugar
        ndf = c.ndf; adf = c.adf; adl = c.adl
        nfc = c.nfc; nsc = c.nsc; nfe = c.nfe; organicMatter = c.organicMatter
        nel = c.nel; me1xNRC = c.me1xNRC; tse9610 = c.tse9610
        mePoultryFixed = c.mePoultryFixed; meRuminantFixed = c.meRuminantFixed
        ufl = c.ufl; ufv = c.ufv; negKazanc = c.negKazanc; maffME = c.maffME
        meRumAlderman = c.meRumAlderman; meRumMaff = c.meRumMaff
        mePoultryCC = c.mePoultryCC; mePoultryECNFE = c.mePoultryECNFE
        mePoultryEC = c.mePoultryEC; mePoultryCobb = c.mePoultryCobb
        pdie = c.pdie; pdia = c.pdia; pdin = c.pdin
        rdp = c.rdp; rup = c.rup; rupCP = c.rupCP
        frakA = c.frakA; frakB = c.frakB; frakC = c.frakC
        degradationRateB = c.degradationRateB; solProtein = c.solProtein
        ndcip = c.ndcip; adicp = c.adicp
        tdn = c.tdn; rdsStarch = c.rdsStarch; solubleStarch = c.solubleStarch
        slowStarch = c.slowStarch; solStarchPct = c.solStarchPct; bypassStarch = c.bypassStarch
        calcium = c.calcium; phosphorus = c.phosphorus
        totalPhosphorus = c.totalPhosphorus; availP = c.availP; availPChick = c.availPChick
        magnesium = c.magnesium; potassium = c.potassium; sodium = c.sodium
        chlorine = c.chlorine; sulfur = c.sulfur; caP = c.caP
        zinc = c.zinc; manganese = c.manganese; copper = c.copper
        cobalt = c.cobalt; iron = c.iron; selenium = c.selenium; iodine = c.iodine
        methionine = c.methionine; lysine = c.lysine; metCys = c.metCys
        cystine = c.cystine; tryptophan = c.tryptophan; arginine = c.arginine
        threonine = c.threonine; leucine = c.leucine; isoleucine = c.isoleucine
        valine = c.valine; phenylalanin = c.phenylalanin; phenyTyr = c.phenyTyr
        glycine = c.glycine; histidine = c.histidine; tyrosine = c.tyrosine
        serine = c.serine; proline = c.proline; alanine = c.alanine
        asparticAcid = c.asparticAcid; glutamicAcid = c.glutamicAcid; glySer = c.glySer
        sinMethionine = c.sinMethionine; sinLysine = c.sinLysine
        sinMetCys = c.sinMetCys; sinCystine = c.sinCystine
        sinTryptophan = c.sinTryptophan; sinArginine = c.sinArginine
        sinThreonine = c.sinThreonine; sinLeucine = c.sinLeucine
        sinIsoleucine = c.sinIsoleucine; sinValine = c.sinValine
        sinPhenylalanin = c.sinPhenylalanin; sinHistidine = c.sinHistidine
        linoleicAcid = c.linoleicAcid; linolenicAcid = c.linolenicAcid
        arachidonicAcid = c.arachidonicAcid; choline = c.choline
        lauricAcid = c.lauricAcid; myristicAcid = c.myristicAcid
        palmiticAcid = c.palmiticAcid; palmoleicAcid = c.palmoleicAcid
        stearicAcid = c.stearicAcid; oleicAcid = c.oleicAcid
        unsatFattyAcid = c.unsatFattyAcid; satFattyAcid = c.satFattyAcid
        freeFat = c.freeFat; totalFattyAcid = c.totalFattyAcid
        metLys = c.metLys; mCLys = c.mCLys; argLys = c.argLys
        threLys = c.threLys; leuLys = c.leuLys; valLys = c.valLys; trpLys = c.trpLys
        sinMethCoeff = c.sinMethCoeff; sinLysCoeff = c.sinLysCoeff
        sinCysCoeff = c.sinCysCoeff; sinArgCoeff = c.sinArgCoeff
        sinThrCoeff = c.sinThrCoeff; sinLeuCoeff = c.sinLeuCoeff
        sinIsoCoeff = c.sinIsoCoeff; sinValCoeff = c.sinValCoeff
        sinTryCoeff = c.sinTryCoeff; sinPheCoeff = c.sinPheCoeff
        sinHisCoeff = c.sinHisCoeff; aldermanCoeff = c.aldermanCoeff
        maffCoeff = c.maffCoeff; ccCoeff = c.ccCoeff
        ecNFECoeff = c.ecNFECoeff; ecCoeff = c.ecCoeff; cobbCoeff = c.cobbCoeff
        dcap = c.dcap; peletRenk = c.peletRenk; peletKalite = c.peletKalite
        prestKapasite = c.prestKapasite; paf = c.paf
    }
}

// MARK: - FeedIngredient → Candidate

extension FeedIngredientCandidate {
    init(saved s: FeedIngredient) {
        name = s.name; code = s.code; priceTL = s.priceTL; sourceFile = s.sourceFile
        dryMatter = s.dryMatter; crudeProtein = s.crudeProtein; crudeAsh = s.crudeAsh
        crudeFiber = s.crudeFiber; crudeFat = s.crudeFat
        starch = s.starch; sugar = s.sugar
        ndf = s.ndf; adf = s.adf; adl = s.adl
        nfc = s.nfc; nsc = s.nsc; nfe = s.nfe; organicMatter = s.organicMatter
        nel = s.nel; me1xNRC = s.me1xNRC; tse9610 = s.tse9610
        mePoultryFixed = s.mePoultryFixed; meRuminantFixed = s.meRuminantFixed
        ufl = s.ufl; ufv = s.ufv; negKazanc = s.negKazanc; maffME = s.maffME
        meRumAlderman = s.meRumAlderman; meRumMaff = s.meRumMaff
        mePoultryCC = s.mePoultryCC; mePoultryECNFE = s.mePoultryECNFE
        mePoultryEC = s.mePoultryEC; mePoultryCobb = s.mePoultryCobb
        pdie = s.pdie; pdia = s.pdia; pdin = s.pdin
        rdp = s.rdp; rup = s.rup; rupCP = s.rupCP
        frakA = s.frakA; frakB = s.frakB; frakC = s.frakC
        degradationRateB = s.degradationRateB; solProtein = s.solProtein
        ndcip = s.ndcip; adicp = s.adicp
        tdn = s.tdn; rdsStarch = s.rdsStarch; solubleStarch = s.solubleStarch
        slowStarch = s.slowStarch; solStarchPct = s.solStarchPct; bypassStarch = s.bypassStarch
        calcium = s.calcium; phosphorus = s.phosphorus
        totalPhosphorus = s.totalPhosphorus; availP = s.availP; availPChick = s.availPChick
        magnesium = s.magnesium; potassium = s.potassium; sodium = s.sodium
        chlorine = s.chlorine; sulfur = s.sulfur; caP = s.caP
        zinc = s.zinc; manganese = s.manganese; copper = s.copper
        cobalt = s.cobalt; iron = s.iron; selenium = s.selenium; iodine = s.iodine
        methionine = s.methionine; lysine = s.lysine; metCys = s.metCys
        cystine = s.cystine; tryptophan = s.tryptophan; arginine = s.arginine
        threonine = s.threonine; leucine = s.leucine; isoleucine = s.isoleucine
        valine = s.valine; phenylalanin = s.phenylalanin; phenyTyr = s.phenyTyr
        glycine = s.glycine; histidine = s.histidine; tyrosine = s.tyrosine
        serine = s.serine; proline = s.proline; alanine = s.alanine
        asparticAcid = s.asparticAcid; glutamicAcid = s.glutamicAcid; glySer = s.glySer
        sinMethionine = s.sinMethionine; sinLysine = s.sinLysine
        sinMetCys = s.sinMetCys; sinCystine = s.sinCystine
        sinTryptophan = s.sinTryptophan; sinArginine = s.sinArginine
        sinThreonine = s.sinThreonine; sinLeucine = s.sinLeucine
        sinIsoleucine = s.sinIsoleucine; sinValine = s.sinValine
        sinPhenylalanin = s.sinPhenylalanin; sinHistidine = s.sinHistidine
        linoleicAcid = s.linoleicAcid; linolenicAcid = s.linolenicAcid
        arachidonicAcid = s.arachidonicAcid; choline = s.choline
        lauricAcid = s.lauricAcid; myristicAcid = s.myristicAcid
        palmiticAcid = s.palmiticAcid; palmoleicAcid = s.palmoleicAcid
        stearicAcid = s.stearicAcid; oleicAcid = s.oleicAcid
        unsatFattyAcid = s.unsatFattyAcid; satFattyAcid = s.satFattyAcid
        freeFat = s.freeFat; totalFattyAcid = s.totalFattyAcid
        metLys = s.metLys; mCLys = s.mCLys; argLys = s.argLys
        threLys = s.threLys; leuLys = s.leuLys; valLys = s.valLys; trpLys = s.trpLys
        sinMethCoeff = s.sinMethCoeff; sinLysCoeff = s.sinLysCoeff
        sinCysCoeff = s.sinCysCoeff; sinArgCoeff = s.sinArgCoeff
        sinThrCoeff = s.sinThrCoeff; sinLeuCoeff = s.sinLeuCoeff
        sinIsoCoeff = s.sinIsoCoeff; sinValCoeff = s.sinValCoeff
        sinTryCoeff = s.sinTryCoeff; sinPheCoeff = s.sinPheCoeff
        sinHisCoeff = s.sinHisCoeff; aldermanCoeff = s.aldermanCoeff
        maffCoeff = s.maffCoeff; ccCoeff = s.ccCoeff
        ecNFECoeff = s.ecNFECoeff; ecCoeff = s.ecCoeff; cobbCoeff = s.cobbCoeff
        dcap = s.dcap; peletRenk = s.peletRenk; peletKalite = s.peletKalite
        prestKapasite = s.prestKapasite; paf = s.paf
    }
}
