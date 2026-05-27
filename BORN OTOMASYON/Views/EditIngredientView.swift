import SwiftUI
import SwiftData
import Observation

// Her property ayrı izlenir → sadece değişen alan view'ı yeniler.
@Observable
final class IngFormData {
    var name = "";  var code = "";  var price = ""

    var dryMatter = "";    var crudeProtein = "";  var crudeAsh = ""
    var crudeFiber = "";   var crudeFat = "";      var starch = ""
    var sugar = "";        var ndf = "";           var adf = ""
    var adl = "";          var nfc = "";           var nsc = ""
    var nfe = "";          var organicMatter = ""

    var nel = "";          var me1xNRC = "";       var tse9610 = ""
    var mePoultryFixed = ""; var meRuminantFixed = ""; var ufl = ""
    var ufv = "";          var negKazanc = "";     var maffME = ""

    var meRumAlderman = ""; var meRumMaff = "";    var mePoultryCC = ""
    var mePoultryECNFE = ""; var mePoultryEC = ""; var mePoultryCobb = ""

    var pdie = ""; var pdia = ""; var pdin = ""
    var rdp = "";  var rup = "";  var rupCP = ""
    var frakA = ""; var frakB = ""; var frakC = ""
    var degradationRateB = ""; var solProtein = ""
    var ndcip = ""; var adicp = ""

    var tdn = "";          var rdsStarch = "";     var solubleStarch = ""
    var slowStarch = "";   var solStarchPct = "";  var bypassStarch = ""

    var calcium = "";      var phosphorus = "";    var totalPhosphorus = ""
    var availP = "";       var availPChick = "";   var magnesium = ""
    var potassium = "";    var sodium = "";        var chlorine = ""
    var sulfur = "";       var caP = ""

    var zinc = "";     var manganese = ""; var copper = ""
    var cobalt = "";   var iron = "";      var selenium = ""; var iodine = ""

    var methionine = "";   var lysine = "";        var metCys = ""
    var cystine = "";      var tryptophan = "";    var arginine = ""
    var threonine = "";    var leucine = "";       var isoleucine = ""
    var valine = "";       var phenylalanin = "";  var phenyTyr = ""
    var glycine = "";      var histidine = "";     var tyrosine = ""
    var serine = "";       var proline = "";       var alanine = ""
    var asparticAcid = ""; var glutamicAcid = "";  var glySer = ""

    var sinMethionine = "";   var sinLysine = "";       var sinMetCys = ""
    var sinCystine = "";      var sinTryptophan = "";   var sinArginine = ""
    var sinThreonine = "";    var sinLeucine = "";      var sinIsoleucine = ""
    var sinValine = "";       var sinPhenylalanin = ""; var sinHistidine = ""

    var linoleicAcid = "";    var linolenicAcid = "";   var arachidonicAcid = ""
    var choline = "";         var lauricAcid = "";      var myristicAcid = ""
    var palmiticAcid = "";    var palmoleicAcid = "";   var stearicAcid = ""
    var oleicAcid = "";       var unsatFattyAcid = "";  var satFattyAcid = ""
    var freeFat = "";         var totalFattyAcid = ""

    var metLys = "";  var mCLys = "";  var argLys = ""
    var threLys = ""; var leuLys = ""; var valLys = ""; var trpLys = ""

    var sinMethCoeff = "";  var sinLysCoeff = "";  var sinCysCoeff = ""
    var sinArgCoeff = "";   var sinThrCoeff = "";  var sinLeuCoeff = ""
    var sinIsoCoeff = "";   var sinValCoeff = "";  var sinTryCoeff = ""
    var sinPheCoeff = "";   var sinHisCoeff = "";  var aldermanCoeff = ""
    var maffCoeff = "";     var ccCoeff = "";      var ecNFECoeff = ""
    var ecCoeff = "";       var cobbCoeff = ""

    var dcap = "";         var peletRenk = "";     var peletKalite = ""
    var prestKapasite = ""; var paf = ""

    var extras: [(key: String, value: String)] = []
    var showAddCriterion = false
    var newCriterionName = ""
    var validationError: String?
}

// MARK: - Row helpers (file-private)

private func nfRow(_ label: String, _ binding: Binding<String>) -> some View {
    HStack {
        Text(label).font(.callout).foregroundStyle(.secondary)
        TextField("—", text: binding)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
    }
}
private func tfRow(_ label: String, _ binding: Binding<String>) -> some View {
    HStack {
        Text(label).foregroundStyle(.secondary)
        TextField("", text: binding).multilineTextAlignment(.trailing)
    }
}

// MARK: - Section structs (her biri bağımsız body hesaplar)

private struct EIIdentitySection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Kimlik") {
            tfRow("İsim *",        $fd.name)
            tfRow("Kod (TXT KOD)", $fd.code)
            nfRow("Fiyat (₺/ton)", $fd.price)
        }
    }
}

private struct EIBasicSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Temel Bileşim") {
            nfRow("1  – Kuru Madde (%)",    $fd.dryMatter)
            nfRow("2  – Ham Protein (%)",   $fd.crudeProtein)
            nfRow("7  – Ham Kül (%)",       $fd.crudeAsh)
            nfRow("6  – Ham Selüloz (%)",   $fd.crudeFiber)
            nfRow("5  – Ham Yağ (%)",       $fd.crudeFat)
            nfRow("54 – Nişasta (%)",       $fd.starch)
            nfRow("53 – Şeker (%)",         $fd.sugar)
            nfRow("111– NDF (%)",           $fd.ndf)
            nfRow("112– ADF (%)",           $fd.adf)
            nfRow("113– ADL (%)",           $fd.adl)
            nfRow("119– NFC (%)",           $fd.nfc)
            nfRow("120– NSC (%)",           $fd.nsc)
            nfRow("85 – NFE (%)",           $fd.nfe)
            nfRow("160– Organik Madde (%)", $fd.organicMatter)
        }
    }
}

private struct EIEnergySection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Enerji") {
            nfRow("114– NEL 3x NRC (KCal/Kg)",        $fd.nel)
            nfRow("115– ME 1x NRC (KCal/Kg)",         $fd.me1xNRC)
            nfRow("116– TSE 9610 (KCal/Kg)",           $fd.tse9610)
            nfRow("4  – ME Kanatlı Sabit (KCal/Kg)",  $fd.mePoultryFixed)
            nfRow("3  – ME Ruminant Sabit (KCal/Kg)", $fd.meRuminantFixed)
            nfRow("117– UFL INRA",                    $fd.ufl)
            nfRow("118– UFV INRA",                    $fd.ufv)
            nfRow("146– Neg Kazanç (KCal/Kg)",        $fd.negKazanc)
            nfRow("161– MAFF ME (KCal/Kg)",           $fd.maffME)
        }
    }
}

private struct EIEnergyFormulSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Formüllü Enerji (KCal/Kg)") {
            nfRow("90 – ME Rum. Alderman",  $fd.meRumAlderman)
            nfRow("92 – ME Rum. MAFF",      $fd.meRumMaff)
            nfRow("104– ME Kanatli C&C",    $fd.mePoultryCC)
            nfRow("105– ME Kanatli EC-NFE", $fd.mePoultryECNFE)
            nfRow("106– ME Kanatli EC",     $fd.mePoultryEC)
            nfRow("107– ME Kanatli COBB",   $fd.mePoultryCobb)
        }
    }
}

private struct EIProteinSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Protein Parçalanabilirliği") {
            nfRow("155– PDIE (Gr/Kg)",           $fd.pdie)
            nfRow("156– PDIA (Gr/Kg)",           $fd.pdia)
            nfRow("154– PDIN (Gr/Kg)",           $fd.pdin)
            nfRow("132– RDP (%)",                $fd.rdp)
            nfRow("133– RUP (%)",                $fd.rup)
            nfRow("134– RUP %CP",                $fd.rupCP)
            nfRow("135– Frak. A (%)",            $fd.frakA)
            nfRow("136– Frak. B (%)",            $fd.frakB)
            nfRow("137– Frak. C (%)",            $fd.frakC)
            nfRow("138– Parçalanma Hızı-B (%)",  $fd.degradationRateB)
            nfRow("139– SP Soluble Protein (%)", $fd.solProtein)
            nfRow("147– NDCIP (%)",              $fd.ndcip)
            nfRow("148– ADICP (%)",              $fd.adicp)
        }
    }
}

private struct EICarbSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Karbonhidrat Detay") {
            nfRow("140– TDN (%)",              $fd.tdn)
            nfRow("141– RDS Rumen Starch (%)", $fd.rdsStarch)
            nfRow("142– Soluble Starch (%)",   $fd.solubleStarch)
            nfRow("157– Yavaş Nişasta (%)",    $fd.slowStarch)
            nfRow("158– Çözülebilir Niş. (%)", $fd.solStarchPct)
            nfRow("159– By Pass Nişasta (%)",  $fd.bypassStarch)
        }
    }
}

private struct EIMacroMineralSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Makro Mineraller") {
            nfRow("16 – Kalsiyum Ca (%)",        $fd.calcium)
            nfRow("17 – Fosfor P (%)",           $fd.phosphorus)
            nfRow("18 – Toplam Fosfor (%)",      $fd.totalPhosphorus)
            nfRow("152– Haz. Fosfor (%)",        $fd.availP)
            nfRow("153– Haz. Fosfor Civciv (%)", $fd.availPChick)
            nfRow("121– Magnezyum Mg (%)",       $fd.magnesium)
            nfRow("122– Potasyum K (%)",         $fd.potassium)
            nfRow("21 – Sodyum Na (%)",          $fd.sodium)
            nfRow("23 – Klor Cl (%)",            $fd.chlorine)
            nfRow("123– Kükürt S (%)",           $fd.sulfur)
            nfRow("19 – Ca/P oranı",             $fd.caP)
        }
    }
}

private struct EIMicroMineralSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Mikro Mineraller (ppm)") {
            nfRow("124– Çinko Zn",    $fd.zinc)
            nfRow("125– Mangan Mn",   $fd.manganese)
            nfRow("126– Bakır Cu",    $fd.copper)
            nfRow("127– Kobalt Co",   $fd.cobalt)
            nfRow("128– Demir Fe",    $fd.iron)
            nfRow("129– Selenyum Se", $fd.selenium)
            nfRow("130– İyot I",      $fd.iodine)
        }
    }
}

private struct EIAminoRealSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Amino Asitler – Gerçek (%)") {
            nfRow("8  – Methionine",    $fd.methionine)
            nfRow("10 – Lysine",        $fd.lysine)
            nfRow("12 – Meth+Cys",      $fd.metCys)
            nfRow("14 – Cystine",       $fd.cystine)
            nfRow("34 – Tryptophan",    $fd.tryptophan)
            nfRow("24 – Arginine",      $fd.arginine)
            nfRow("26 – Threonine",     $fd.threonine)
            nfRow("28 – Leucine",       $fd.leucine)
            nfRow("30 – Isoleucine",    $fd.isoleucine)
            nfRow("32 – Valine",        $fd.valine)
            nfRow("36 – Phenylalanin",  $fd.phenylalanin)
            nfRow("38 – Pheny+Tyr",     $fd.phenyTyr)
            nfRow("39 – Glycine",       $fd.glycine)
            nfRow("40 – Histidine",     $fd.histidine)
            nfRow("42 – Tyrosine",      $fd.tyrosine)
            nfRow("43 – Serine",        $fd.serine)
            nfRow("44 – Proline",       $fd.proline)
            nfRow("45 – Alanine",       $fd.alanine)
            nfRow("46 – Aspartic Asit", $fd.asparticAcid)
            nfRow("47 – Glutamic Acid", $fd.glutamicAcid)
            nfRow("48 – Gly+Ser",       $fd.glySer)
        }
    }
}

private struct EIAminoDigSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Amino Asitler – Sindirilebilir (%)") {
            nfRow("9  – Sin. Methionine",   $fd.sinMethionine)
            nfRow("11 – Sin. Lysine",       $fd.sinLysine)
            nfRow("13 – Sin. Met+Cys",      $fd.sinMetCys)
            nfRow("15 – Sin. Cystine",      $fd.sinCystine)
            nfRow("35 – Sin. Tryptophan",   $fd.sinTryptophan)
            nfRow("25 – Sin. Arginine",     $fd.sinArginine)
            nfRow("27 – Sin. Threonine",    $fd.sinThreonine)
            nfRow("29 – Sin. Leucine",      $fd.sinLeucine)
            nfRow("31 – Sin. Isoleucine",   $fd.sinIsoleucine)
            nfRow("33 – Sin. Valine",       $fd.sinValine)
            nfRow("37 – Sin. Phenylalanin", $fd.sinPhenylalanin)
            nfRow("41 – Sin. Histidine",    $fd.sinHistidine)
        }
    }
}

private struct EIFattyAcidSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Yağ Asitleri (%)") {
            nfRow("49 – Linoleik Asit",    $fd.linoleicAcid)
            nfRow("50 – Linolenik Asit",   $fd.linolenicAcid)
            nfRow("51 – Arasidonik Asit",  $fd.arachidonicAcid)
            nfRow("52 – Kolin",            $fd.choline)
            nfRow("55 – Lauric Asit",      $fd.lauricAcid)
            nfRow("56 – Myristic Asit",    $fd.myristicAcid)
            nfRow("57 – Palmitic Asit",    $fd.palmiticAcid)
            nfRow("58 – Palmoleic Asit",   $fd.palmoleicAcid)
            nfRow("59 – Stearic Asit",     $fd.stearicAcid)
            nfRow("60 – Oleic Asit",       $fd.oleicAcid)
            nfRow("61 – Doymamış Yağ",     $fd.unsatFattyAcid)
            nfRow("62 – Doymuş Yağ",       $fd.satFattyAcid)
            nfRow("63 – Serbest Yağ",      $fd.freeFat)
            nfRow("64 – Toplam Yağ Asiti", $fd.totalFattyAcid)
        }
    }
}

private struct EIRatioSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Oranlar") {
            nfRow("65 – Met/Lys",  $fd.metLys)
            nfRow("66 – M+C/Lys",  $fd.mCLys)
            nfRow("67 – Arg/Lys",  $fd.argLys)
            nfRow("68 – Thre/Lys", $fd.threLys)
            nfRow("69 – Leu/Lys",  $fd.leuLys)
            nfRow("71 – Val/Lys",  $fd.valLys)
            nfRow("72 – Trp/Lys",  $fd.trpLys)
        }
    }
}

private struct EICoeffSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Sindirim Katsayıları") {
            nfRow("74 – Katsayı SinMeth",  $fd.sinMethCoeff)
            nfRow("75 – Katsayı SinLys",   $fd.sinLysCoeff)
            nfRow("76 – Katsayı SinCys",   $fd.sinCysCoeff)
            nfRow("77 – Katsayı SinArg",   $fd.sinArgCoeff)
            nfRow("78 – Katsayı SinThr",   $fd.sinThrCoeff)
            nfRow("79 – Katsayı SinLeu",   $fd.sinLeuCoeff)
            nfRow("80 – Katsayı SinIso",   $fd.sinIsoCoeff)
            nfRow("81 – Katsayı SinVal",   $fd.sinValCoeff)
            nfRow("82 – Katsayı SinTry",   $fd.sinTryCoeff)
            nfRow("83 – Katsayı SinPhe",   $fd.sinPheCoeff)
            nfRow("84 – Katsayı SinHis",   $fd.sinHisCoeff)
            nfRow("88 – Katsayı Alderman", $fd.aldermanCoeff)
            nfRow("91 – Katsayı MAFF",     $fd.maffCoeff)
            nfRow("96 – Katsayı C&C",      $fd.ccCoeff)
            nfRow("97 – Katsayı EC-NFE",   $fd.ecNFECoeff)
            nfRow("98 – Katsayı EC",       $fd.ecCoeff)
            nfRow("99 – Katsayı COBB",     $fd.cobbCoeff)
        }
    }
}

private struct EIQualitySection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section("Kalite / Diğer") {
            nfRow("131– DCAP (mEq/Kg)",      $fd.dcap)
            nfRow("143– Pelet Renk (%)",     $fd.peletRenk)
            nfRow("144– Pelet Kalite (%)",   $fd.peletKalite)
            nfRow("145– Prest Kapasite (%)", $fd.prestKapasite)
            nfRow("149– PAF (%)",            $fd.paf)
        }
    }
}

private struct EIExtrasSection: View {
    @Bindable var fd: IngFormData
    var body: some View {
        Section {
            ForEach($fd.extras, id: \.key) { $pair in
                HStack {
                    Text(pair.key).frame(minWidth: 120, alignment: .leading)
                    TextField("değer", text: $pair.value)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            .onDelete { fd.extras.remove(atOffsets: $0) }
            Button { fd.showAddCriterion = true } label: {
                Label("Yeni Kriter Ekle", systemImage: "plus.circle")
            }
        } header: { Text("Özel Kriterler") }
        footer: { Text("LP solver için ek parametreler ekleyebilirsiniz.").font(.caption) }
    }
}

// MARK: - Main View

struct EditIngredientView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)       private var dismiss

    var ingredient: FeedIngredient?

    @Query private var allFormulas: [BlendFormula]   // fiyat senkronizasyonu için

    @State private var fd = IngFormData()

    var body: some View {
        NavigationStack {
            Form {
                EIIdentitySection(fd: fd)
                EIBasicSection(fd: fd)
                EIEnergySection(fd: fd)
                EIEnergyFormulSection(fd: fd)
                EIProteinSection(fd: fd)
                EICarbSection(fd: fd)
                EIMacroMineralSection(fd: fd)
                EIMicroMineralSection(fd: fd)
                EIAminoRealSection(fd: fd)
                EIAminoDigSection(fd: fd)
                EIFattyAcidSection(fd: fd)
                EIRatioSection(fd: fd)
                EICoeffSection(fd: fd)
                EIQualitySection(fd: fd)
                EIExtrasSection(fd: fd)
                if let err = fd.validationError {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(ingredient == nil ? "Yeni Hammadde" : "Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { save() }.bold() }
            }
            .onAppear { populate() }
            .alert("Yeni Kriter", isPresented: $fd.showAddCriterion) {
                TextField("Kriter adı (örn: Vitamin E)", text: $fd.newCriterionName)
                Button("Ekle") {
                    let key = fd.newCriterionName.trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty && !fd.extras.contains(where: { $0.key == key }) {
                        fd.extras.append((key: key, value: ""))
                    }
                    fd.newCriterionName = ""
                }
                Button("İptal", role: .cancel) { fd.newCriterionName = "" }
            }
        }
    }

    // MARK: - Populate

    private func populate() {
        guard let i = ingredient else { return }
        fd.name = i.name; fd.code = i.code; fd.price = fv(i.priceTL)

        fd.dryMatter = fv(i.dryMatter);       fd.crudeProtein = fv(i.crudeProtein)
        fd.crudeAsh = fv(i.crudeAsh);         fd.crudeFiber = fv(i.crudeFiber)
        fd.crudeFat = fv(i.crudeFat);         fd.starch = fv(i.starch)
        fd.sugar = fv(i.sugar);               fd.ndf = fv(i.ndf)
        fd.adf = fv(i.adf);                   fd.adl = fv(i.adl)
        fd.nfc = fv(i.nfc);                   fd.nsc = fv(i.nsc)
        fd.nfe = fv(i.nfe);                   fd.organicMatter = fv(i.organicMatter)

        fd.nel = fv(i.nel);                   fd.me1xNRC = fv(i.me1xNRC)
        fd.tse9610 = fv(i.tse9610);           fd.mePoultryFixed = fv(i.mePoultryFixed)
        fd.meRuminantFixed = fv(i.meRuminantFixed)
        fd.ufl = fv(i.ufl);                   fd.ufv = fv(i.ufv)
        fd.negKazanc = fv(i.negKazanc);       fd.maffME = fv(i.maffME)

        fd.meRumAlderman = fv(i.meRumAlderman); fd.meRumMaff = fv(i.meRumMaff)
        fd.mePoultryCC = fv(i.mePoultryCC);     fd.mePoultryECNFE = fv(i.mePoultryECNFE)
        fd.mePoultryEC = fv(i.mePoultryEC);     fd.mePoultryCobb = fv(i.mePoultryCobb)

        fd.pdie = fv(i.pdie); fd.pdia = fv(i.pdia); fd.pdin = fv(i.pdin)
        fd.rdp = fv(i.rdp);   fd.rup = fv(i.rup);   fd.rupCP = fv(i.rupCP)
        fd.frakA = fv(i.frakA); fd.frakB = fv(i.frakB); fd.frakC = fv(i.frakC)
        fd.degradationRateB = fv(i.degradationRateB); fd.solProtein = fv(i.solProtein)
        fd.ndcip = fv(i.ndcip); fd.adicp = fv(i.adicp)

        fd.tdn = fv(i.tdn); fd.rdsStarch = fv(i.rdsStarch); fd.solubleStarch = fv(i.solubleStarch)
        fd.slowStarch = fv(i.slowStarch); fd.solStarchPct = fv(i.solStarchPct)
        fd.bypassStarch = fv(i.bypassStarch)

        fd.calcium = fv(i.calcium);               fd.phosphorus = fv(i.phosphorus)
        fd.totalPhosphorus = fv(i.totalPhosphorus); fd.availP = fv(i.availP)
        fd.availPChick = fv(i.availPChick);        fd.magnesium = fv(i.magnesium)
        fd.potassium = fv(i.potassium);            fd.sodium = fv(i.sodium)
        fd.chlorine = fv(i.chlorine);              fd.sulfur = fv(i.sulfur); fd.caP = fv(i.caP)

        fd.zinc = fv(i.zinc); fd.manganese = fv(i.manganese); fd.copper = fv(i.copper)
        fd.cobalt = fv(i.cobalt); fd.iron = fv(i.iron)
        fd.selenium = fv(i.selenium); fd.iodine = fv(i.iodine)

        fd.methionine = fv(i.methionine); fd.lysine = fv(i.lysine); fd.metCys = fv(i.metCys)
        fd.cystine = fv(i.cystine);       fd.tryptophan = fv(i.tryptophan)
        fd.arginine = fv(i.arginine);     fd.threonine = fv(i.threonine)
        fd.leucine = fv(i.leucine);       fd.isoleucine = fv(i.isoleucine)
        fd.valine = fv(i.valine);         fd.phenylalanin = fv(i.phenylalanin)
        fd.phenyTyr = fv(i.phenyTyr);     fd.glycine = fv(i.glycine)
        fd.histidine = fv(i.histidine);   fd.tyrosine = fv(i.tyrosine)
        fd.serine = fv(i.serine);         fd.proline = fv(i.proline)
        fd.alanine = fv(i.alanine);       fd.asparticAcid = fv(i.asparticAcid)
        fd.glutamicAcid = fv(i.glutamicAcid); fd.glySer = fv(i.glySer)

        fd.sinMethionine = fv(i.sinMethionine); fd.sinLysine = fv(i.sinLysine)
        fd.sinMetCys = fv(i.sinMetCys);         fd.sinCystine = fv(i.sinCystine)
        fd.sinTryptophan = fv(i.sinTryptophan); fd.sinArginine = fv(i.sinArginine)
        fd.sinThreonine = fv(i.sinThreonine);   fd.sinLeucine = fv(i.sinLeucine)
        fd.sinIsoleucine = fv(i.sinIsoleucine); fd.sinValine = fv(i.sinValine)
        fd.sinPhenylalanin = fv(i.sinPhenylalanin); fd.sinHistidine = fv(i.sinHistidine)

        fd.linoleicAcid = fv(i.linoleicAcid);    fd.linolenicAcid = fv(i.linolenicAcid)
        fd.arachidonicAcid = fv(i.arachidonicAcid); fd.choline = fv(i.choline)
        fd.lauricAcid = fv(i.lauricAcid);        fd.myristicAcid = fv(i.myristicAcid)
        fd.palmiticAcid = fv(i.palmiticAcid);    fd.palmoleicAcid = fv(i.palmoleicAcid)
        fd.stearicAcid = fv(i.stearicAcid);      fd.oleicAcid = fv(i.oleicAcid)
        fd.unsatFattyAcid = fv(i.unsatFattyAcid); fd.satFattyAcid = fv(i.satFattyAcid)
        fd.freeFat = fv(i.freeFat);              fd.totalFattyAcid = fv(i.totalFattyAcid)

        fd.metLys = fv(i.metLys); fd.mCLys = fv(i.mCLys); fd.argLys = fv(i.argLys)
        fd.threLys = fv(i.threLys); fd.leuLys = fv(i.leuLys)
        fd.valLys = fv(i.valLys); fd.trpLys = fv(i.trpLys)

        fd.sinMethCoeff = fv(i.sinMethCoeff); fd.sinLysCoeff = fv(i.sinLysCoeff)
        fd.sinCysCoeff = fv(i.sinCysCoeff);   fd.sinArgCoeff = fv(i.sinArgCoeff)
        fd.sinThrCoeff = fv(i.sinThrCoeff);   fd.sinLeuCoeff = fv(i.sinLeuCoeff)
        fd.sinIsoCoeff = fv(i.sinIsoCoeff);   fd.sinValCoeff = fv(i.sinValCoeff)
        fd.sinTryCoeff = fv(i.sinTryCoeff);   fd.sinPheCoeff = fv(i.sinPheCoeff)
        fd.sinHisCoeff = fv(i.sinHisCoeff);   fd.aldermanCoeff = fv(i.aldermanCoeff)
        fd.maffCoeff = fv(i.maffCoeff);       fd.ccCoeff = fv(i.ccCoeff)
        fd.ecNFECoeff = fv(i.ecNFECoeff);     fd.ecCoeff = fv(i.ecCoeff)
        fd.cobbCoeff = fv(i.cobbCoeff)

        fd.dcap = fv(i.dcap);               fd.peletRenk = fv(i.peletRenk)
        fd.peletKalite = fv(i.peletKalite); fd.prestKapasite = fv(i.prestKapasite)
        fd.paf = fv(i.paf)

        fd.extras = i.extras.sorted { $0.key < $1.key }.map { (key: $0.key, value: fv($0.value)) }
    }

    // MARK: - Save

    private func save() {
        let trimmed = fd.name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { fd.validationError = "İsim boş olamaz."; return }

        let target = ingredient ?? {
            let n = FeedIngredient(name: trimmed, code: fd.code.trimmingCharacters(in: .whitespaces), priceTL: dv(fd.price))
            modelContext.insert(n)
            return n
        }()

        target.name = trimmed
        target.code = fd.code.trimmingCharacters(in: .whitespaces)
        target.priceTL = dv(fd.price)

        target.dryMatter = dv(fd.dryMatter);       target.crudeProtein = dv(fd.crudeProtein)
        target.crudeAsh = dv(fd.crudeAsh);         target.crudeFiber = dv(fd.crudeFiber)
        target.crudeFat = dv(fd.crudeFat);         target.starch = dv(fd.starch)
        target.sugar = dv(fd.sugar);               target.ndf = dv(fd.ndf)
        target.adf = dv(fd.adf);                   target.adl = dv(fd.adl)
        target.nfc = dv(fd.nfc);                   target.nsc = dv(fd.nsc)
        target.nfe = dv(fd.nfe);                   target.organicMatter = dv(fd.organicMatter)

        target.nel = dv(fd.nel);                   target.me1xNRC = dv(fd.me1xNRC)
        target.tse9610 = dv(fd.tse9610);           target.mePoultryFixed = dv(fd.mePoultryFixed)
        target.meRuminantFixed = dv(fd.meRuminantFixed)
        target.ufl = dv(fd.ufl);                   target.ufv = dv(fd.ufv)
        target.negKazanc = dv(fd.negKazanc);       target.maffME = dv(fd.maffME)

        target.meRumAlderman = dv(fd.meRumAlderman); target.meRumMaff = dv(fd.meRumMaff)
        target.mePoultryCC = dv(fd.mePoultryCC);     target.mePoultryECNFE = dv(fd.mePoultryECNFE)
        target.mePoultryEC = dv(fd.mePoultryEC);     target.mePoultryCobb = dv(fd.mePoultryCobb)

        target.pdie = dv(fd.pdie); target.pdia = dv(fd.pdia); target.pdin = dv(fd.pdin)
        target.rdp = dv(fd.rdp);   target.rup = dv(fd.rup);   target.rupCP = dv(fd.rupCP)
        target.frakA = dv(fd.frakA); target.frakB = dv(fd.frakB); target.frakC = dv(fd.frakC)
        target.degradationRateB = dv(fd.degradationRateB); target.solProtein = dv(fd.solProtein)
        target.ndcip = dv(fd.ndcip); target.adicp = dv(fd.adicp)

        target.tdn = dv(fd.tdn); target.rdsStarch = dv(fd.rdsStarch)
        target.solubleStarch = dv(fd.solubleStarch); target.slowStarch = dv(fd.slowStarch)
        target.solStarchPct = dv(fd.solStarchPct);   target.bypassStarch = dv(fd.bypassStarch)

        target.calcium = dv(fd.calcium);               target.phosphorus = dv(fd.phosphorus)
        target.totalPhosphorus = dv(fd.totalPhosphorus); target.availP = dv(fd.availP)
        target.availPChick = dv(fd.availPChick);        target.magnesium = dv(fd.magnesium)
        target.potassium = dv(fd.potassium);            target.sodium = dv(fd.sodium)
        target.chlorine = dv(fd.chlorine);              target.sulfur = dv(fd.sulfur)
        target.caP = dv(fd.caP)

        target.zinc = dv(fd.zinc); target.manganese = dv(fd.manganese); target.copper = dv(fd.copper)
        target.cobalt = dv(fd.cobalt); target.iron = dv(fd.iron)
        target.selenium = dv(fd.selenium); target.iodine = dv(fd.iodine)

        target.methionine = dv(fd.methionine); target.lysine = dv(fd.lysine)
        target.metCys = dv(fd.metCys);         target.cystine = dv(fd.cystine)
        target.tryptophan = dv(fd.tryptophan); target.arginine = dv(fd.arginine)
        target.threonine = dv(fd.threonine);   target.leucine = dv(fd.leucine)
        target.isoleucine = dv(fd.isoleucine); target.valine = dv(fd.valine)
        target.phenylalanin = dv(fd.phenylalanin); target.phenyTyr = dv(fd.phenyTyr)
        target.glycine = dv(fd.glycine);       target.histidine = dv(fd.histidine)
        target.tyrosine = dv(fd.tyrosine);     target.serine = dv(fd.serine)
        target.proline = dv(fd.proline);       target.alanine = dv(fd.alanine)
        target.asparticAcid = dv(fd.asparticAcid); target.glutamicAcid = dv(fd.glutamicAcid)
        target.glySer = dv(fd.glySer)

        target.sinMethionine = dv(fd.sinMethionine); target.sinLysine = dv(fd.sinLysine)
        target.sinMetCys = dv(fd.sinMetCys);         target.sinCystine = dv(fd.sinCystine)
        target.sinTryptophan = dv(fd.sinTryptophan); target.sinArginine = dv(fd.sinArginine)
        target.sinThreonine = dv(fd.sinThreonine);   target.sinLeucine = dv(fd.sinLeucine)
        target.sinIsoleucine = dv(fd.sinIsoleucine); target.sinValine = dv(fd.sinValine)
        target.sinPhenylalanin = dv(fd.sinPhenylalanin); target.sinHistidine = dv(fd.sinHistidine)

        target.linoleicAcid = dv(fd.linoleicAcid);    target.linolenicAcid = dv(fd.linolenicAcid)
        target.arachidonicAcid = dv(fd.arachidonicAcid); target.choline = dv(fd.choline)
        target.lauricAcid = dv(fd.lauricAcid);        target.myristicAcid = dv(fd.myristicAcid)
        target.palmiticAcid = dv(fd.palmiticAcid);    target.palmoleicAcid = dv(fd.palmoleicAcid)
        target.stearicAcid = dv(fd.stearicAcid);      target.oleicAcid = dv(fd.oleicAcid)
        target.unsatFattyAcid = dv(fd.unsatFattyAcid); target.satFattyAcid = dv(fd.satFattyAcid)
        target.freeFat = dv(fd.freeFat);              target.totalFattyAcid = dv(fd.totalFattyAcid)

        target.metLys = dv(fd.metLys); target.mCLys = dv(fd.mCLys); target.argLys = dv(fd.argLys)
        target.threLys = dv(fd.threLys); target.leuLys = dv(fd.leuLys)
        target.valLys = dv(fd.valLys); target.trpLys = dv(fd.trpLys)

        target.sinMethCoeff = dv(fd.sinMethCoeff); target.sinLysCoeff = dv(fd.sinLysCoeff)
        target.sinCysCoeff = dv(fd.sinCysCoeff);   target.sinArgCoeff = dv(fd.sinArgCoeff)
        target.sinThrCoeff = dv(fd.sinThrCoeff);   target.sinLeuCoeff = dv(fd.sinLeuCoeff)
        target.sinIsoCoeff = dv(fd.sinIsoCoeff);   target.sinValCoeff = dv(fd.sinValCoeff)
        target.sinTryCoeff = dv(fd.sinTryCoeff);   target.sinPheCoeff = dv(fd.sinPheCoeff)
        target.sinHisCoeff = dv(fd.sinHisCoeff);   target.aldermanCoeff = dv(fd.aldermanCoeff)
        target.maffCoeff = dv(fd.maffCoeff);       target.ccCoeff = dv(fd.ccCoeff)
        target.ecNFECoeff = dv(fd.ecNFECoeff);     target.ecCoeff = dv(fd.ecCoeff)
        target.cobbCoeff = dv(fd.cobbCoeff)

        target.dcap = dv(fd.dcap);               target.peletRenk = dv(fd.peletRenk)
        target.peletKalite = dv(fd.peletKalite); target.prestKapasite = dv(fd.prestKapasite)
        target.paf = dv(fd.paf)

        target.extras = fd.extras.reduce(into: [:]) { dict, pair in
            if let v = dv(pair.value) { dict[pair.key] = v }
        }

        // Fiyat değişikliği → geçmişe kayıt + tüm formüllere yansıt
        let newPrice = dv(fd.price)
        let oldPrice = ingredient?.priceTL
        if let p = newPrice, p != oldPrice {
            modelContext.insert(PriceHistoryEntry(ingredientName: target.name, priceTL: p))
            syncPrice(newPrice: p, name: target.name, code: target.code)
        }

        try? modelContext.save()
        dismiss()
    }

    // Kütüphane fiyatı değişince SingleBlend formüllerindeki fiyatları da güncelle
    private func syncPrice(newPrice: Double, name: String, code: String) {
        for formula in allFormulas {
            var ings = formula.ingredients
            var changed = false
            for i in 0..<ings.count {
                let ing = ings[i]
                let codeMatch = !code.isEmpty && !ing.code.isEmpty && ing.code == code
                let nameMatch = ing.name.trimmingCharacters(in: .whitespaces)
                                       .uppercased() == name.uppercased()
                if codeMatch || nameMatch {
                    ings[i].overridePriceTLPerTon = newPrice
                    changed = true
                }
            }
            if changed {
                formula.ingredients = ings
                formula.updatedAt   = Date()
            }
        }
    }

    // MARK: - Converters

    private func fv(_ v: Double?) -> String {
        guard let v else { return "" }
        if v >= 100 { return String(format: "%.1f", v) }
        return String(format: "%.4f", v)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func dv(_ s: String) -> Double? {
        let c = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return c.isEmpty ? nil : Double(c)
    }
}
