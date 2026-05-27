import SwiftUI
import SwiftData

struct IngredientDetailView: View {
    var saved:     FeedIngredient?
    var candidate: FeedIngredientCandidate?

    @State private var showEdit  = false
    @State private var dmBasis   = false   // yaş → kuru madde bazı toggle

    private var item: FeedIngredientCandidate {
        saved.map { FeedIngredientCandidate(saved: $0) } ?? candidate!
    }

    // KM çarpanı: DM bazı açıksa değerleri (value / KM%) * 100 ile göster.
    // KM'nin kendisi, oranlar ve katsayılar dönüştürülmez.
    private var dmFactor: Double {
        guard dmBasis, let km = item.dryMatter, km > 0 else { return 1.0 }
        return 100.0 / km
    }

    var body: some View {
        List {
            priceSection
            basicSection
            energySection
            energyFormulSection
            proteinSection
            carbSection
            macroMineralSection
            microMineralSection
            aminoRealSection
            aminoDigSection
            fattyAcidSection
            ratioSection
            coeffSection
            qualitySection
            if let s = saved, !s.extras.isEmpty { extrasSection(s) }
            sourceSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // KM bazı toggle
                Button {
                    dmBasis.toggle()
                } label: {
                    Label(
                        dmBasis ? "Yaş Baz" : "KM Bazı",
                        systemImage: dmBasis ? "drop.fill" : "drop"
                    )
                    .font(.caption)
                }
                .tint(dmBasis ? .blue : .secondary)

                // Fiyat geçmişi (yalnızca kayıtlı hammadde)
                if let s = saved {
                    NavigationLink {
                        PriceHistoryView(ingredientName: s.name)
                    } label: {
                        Label("Fiyat Geçmişi", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }

                // Düzenle
                if saved != nil {
                    Button { showEdit = true } label: {
                        Label("Düzenle", systemImage: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let s = saved { EditIngredientView(ingredient: s) }
        }
    }

    // MARK: - Sections

    private var priceSection: some View {
        Section {
            if let p = item.priceTL {
                HStack {
                    Label("Fiyat", systemImage: "turkishlirasign.circle.fill").foregroundStyle(.orange)
                    Spacer()
                    Text(p.formatted(.number.locale(Locale(identifier: "tr_TR"))) + " ₺/ton")
                        .font(.title3.bold()).foregroundStyle(.orange)
                }
            }
            HStack {
                Text("Kod").foregroundStyle(.secondary)
                Spacer()
                Text(item.code.isEmpty ? "—" : "[\(item.code)]")
                    .bold().foregroundStyle(.orange)
            }
            if dmBasis {
                Label(
                    "Kuru Madde Bazında gösteriliyor (÷ KM%×100)",
                    systemImage: "info.circle"
                )
                .font(.caption2).foregroundStyle(.blue)
            }
        }
    }

    private var basicSection: some View {
        Section("Temel Bileşim") {
            // Kuru madde bazında KM kendisi = 100, dönüşüm uygulanmaz
            row("1  – Kuru Madde",    dmBasis ? 100.0 : item.dryMatter,    "%", raw: true)
            row("2  – Ham Protein",   item.crudeProtein, "%")
            row("7  – Ham Kül",       item.crudeAsh,     "%")
            row("6  – Ham Selüloz",   item.crudeFiber,   "%")
            row("5  – Ham Yağ",       item.crudeFat,     "%")
            row("54 – Nişasta",       item.starch,       "%")
            row("53 – Şeker",         item.sugar,        "%")
            row("111– NDF",           item.ndf,          "%")
            row("112– ADF",           item.adf,          "%")
            row("113– ADL",           item.adl,          "%")
            row("119– NFC",           item.nfc,          "%")
            row("120– NSC",           item.nsc,          "%")
            row("85 – NFE",           item.nfe,          "%")
            row("160– Organik Madde", item.organicMatter,"%")
        }
    }

    private var energySection: some View {
        Section("Enerji") {
            row("114– NEL 3x NRC",        item.nel,             "KCal/Kg")
            row("115– ME 1x NRC",         item.me1xNRC,         "KCal/Kg")
            row("116– TSE 9610",          item.tse9610,         "KCal/Kg")
            row("4  – ME Kanatlı (Sabit)",item.mePoultryFixed,  "KCal/Kg")
            row("3  – ME Ruminant(Sabit)",item.meRuminantFixed, "KCal/Kg")
            row("117– UFL INRA",          item.ufl,             "")
            row("118– UFV INRA",          item.ufv,             "")
            row("146– Neg Kazanç",        item.negKazanc,       "KCal/Kg")
            row("161– MAFF ME",           item.maffME,          "KCal/Kg")
        }
    }

    private var energyFormulSection: some View {
        Section("Formüllü Enerji") {
            row("90 – ME Rum. Alderman",  item.meRumAlderman,   "KCal/Kg")
            row("92 – ME Rum. MAFF",      item.meRumMaff,       "KCal/Kg")
            row("104– ME Kanatli C&C",    item.mePoultryCC,     "KCal/Kg")
            row("105– ME Kanatli EC-NFE", item.mePoultryECNFE,  "KCal/Kg")
            row("106– ME Kanatli EC",     item.mePoultryEC,     "KCal/Kg")
            row("107– ME Kanatli COBB",   item.mePoultryCobb,   "KCal/Kg")
        }
    }

    private var proteinSection: some View {
        Section("Protein Parçalanabilirliği") {
            row("155– PDIE",              item.pdie,            "Gr/Kg")
            row("156– PDIA",              item.pdia,            "Gr/Kg")
            row("154– PDIN",              item.pdin,            "Gr/Kg")
            row("132– RDP",               item.rdp,             "%")
            row("133– RUP",               item.rup,             "%")
            row("134– RUP %CP",           item.rupCP,           "%")
            row("135– Frak. A",           item.frakA,           "%")
            row("136– Frak. B",           item.frakB,           "%")
            row("137– Frak. C",           item.frakC,           "%")
            row("138– Parçalanma Hızı-B", item.degradationRateB,"%")
            row("139– SP Soluble Protein",item.solProtein,      "%")
            row("147– NDCIP",             item.ndcip,           "%")
            row("148– ADICP",             item.adicp,           "%")
        }
    }

    private var carbSection: some View {
        Section("Karbonhidrat Detay") {
            row("140– TDN",               item.tdn,             "%")
            row("141– RDS Rumen Starch",  item.rdsStarch,       "%")
            row("142– Soluble Starch",    item.solubleStarch,   "%")
            row("157– Yavaş Nişasta",     item.slowStarch,      "%")
            row("158– Çözülebilir Niş.",  item.solStarchPct,    "%")
            row("159– By Pass Nişasta",   item.bypassStarch,    "%")
        }
    }

    private var macroMineralSection: some View {
        Section("Makro Mineraller") {
            row("16 – Kalsiyum (Ca)",     item.calcium,         "%")
            row("17 – Fosfor (P)",        item.phosphorus,      "%")
            row("18 – Toplam Fosfor",     item.totalPhosphorus, "%")
            row("152– Haz. Fosfor",       item.availP,          "%")
            row("153– Haz. Fosfor Civciv",item.availPChick,     "%")
            row("121– Magnezyum (Mg)",    item.magnesium,       "%")
            row("122– Potasyum (K)",      item.potassium,       "%")
            row("21 – Sodyum (Na)",       item.sodium,          "%")
            row("23 – Klor (Cl)",         item.chlorine,        "%")
            row("123– Kükürt (S)",        item.sulfur,          "%")
            // Ca/P oranı dönüştürülmez
            row("19 – Ca/P",              item.caP,             "", raw: true)
        }
    }

    private var microMineralSection: some View {
        Section("Mikro Mineraller") {
            row("124– Çinko (Zn)",        item.zinc,            "ppm")
            row("125– Mangan (Mn)",       item.manganese,       "ppm")
            row("126– Bakır (Cu)",        item.copper,          "ppm")
            row("127– Kobalt (Co)",       item.cobalt,          "ppm")
            row("128– Demir (Fe)",        item.iron,            "ppm")
            row("129– Selenyum (Se)",     item.selenium,        "ppm")
            row("130– İyot (I)",          item.iodine,          "ppm")
        }
    }

    private var aminoRealSection: some View {
        Section("Amino Asitler – Gerçek") {
            row("8  – Methionine",        item.methionine,      "%")
            row("10 – Lysine",            item.lysine,          "%")
            row("12 – Meth + Cys",        item.metCys,          "%")
            row("14 – Cystine",           item.cystine,         "%")
            row("34 – Tryptophan",        item.tryptophan,      "%")
            row("24 – Arginine",          item.arginine,        "%")
            row("26 – Threonine",         item.threonine,       "%")
            row("28 – Leucine",           item.leucine,         "%")
            row("30 – Isoleucine",        item.isoleucine,      "%")
            row("32 – Valine",            item.valine,          "%")
            row("36 – Phenylalanin",      item.phenylalanin,    "%")
            row("38 – Pheny+Tyr",         item.phenyTyr,        "%")
            row("39 – Glycine",           item.glycine,         "%")
            row("40 – Histidine",         item.histidine,       "%")
            row("42 – Tyrosine",          item.tyrosine,        "%")
            row("43 – Serine",            item.serine,          "%")
            row("44 – Proline",           item.proline,         "%")
            row("45 – Alanine",           item.alanine,         "%")
            row("46 – Aspartic Asit",     item.asparticAcid,    "%")
            row("47 – Glutamic Acid",     item.glutamicAcid,    "%")
            row("48 – Gly+Ser",           item.glySer,          "%")
        }
    }

    private var aminoDigSection: some View {
        Section("Amino Asitler – Sindirilebilir") {
            row("9  – Sin. Methionine",   item.sinMethionine,   "%")
            row("11 – Sin. Lysine",       item.sinLysine,       "%")
            row("13 – Sin. Met+Cys",      item.sinMetCys,       "%")
            row("15 – Sin. Cystine",      item.sinCystine,      "%")
            row("35 – Sin. Tryptophan",   item.sinTryptophan,   "%")
            row("25 – Sin. Arginine",     item.sinArginine,     "%")
            row("27 – Sin. Threonine",    item.sinThreonine,    "%")
            row("29 – Sin. Leucine",      item.sinLeucine,      "%")
            row("31 – Sin. Isoleucine",   item.sinIsoleucine,   "%")
            row("33 – Sin. Valine",       item.sinValine,       "%")
            row("37 – Sin. Phenylalanin", item.sinPhenylalanin, "%")
            row("41 – Sin. Histidine",    item.sinHistidine,    "%")
        }
    }

    private var fattyAcidSection: some View {
        Section("Yağ Asitleri") {
            row("49 – Linoleik Asit",     item.linoleicAcid,    "%")
            row("50 – Linolenik Asit",    item.linolenicAcid,   "%")
            row("51 – Arasidonik Asit",   item.arachidonicAcid, "%")
            row("52 – Kolin",             item.choline,         "")
            row("55 – Lauric Asit",       item.lauricAcid,      "%")
            row("56 – Myristic Asit",     item.myristicAcid,    "%")
            row("57 – Palmitic Asit",     item.palmiticAcid,    "%")
            row("58 – Palmoleic Asit",    item.palmoleicAcid,   "%")
            row("59 – Stearic Asit",      item.stearicAcid,     "%")
            row("60 – Oleic Asit",        item.oleicAcid,       "%")
            row("61 – Doymamış Yağ",      item.unsatFattyAcid,  "%")
            row("62 – Doymuş Yağ",        item.satFattyAcid,    "%")
            row("63 – Serbest Yağ",       item.freeFat,         "%")
            row("64 – Toplam Yağ Asiti",  item.totalFattyAcid,  "%")
        }
    }

    private var ratioSection: some View {
        Section("Oranlar") {
            // Oranlar dönüştürülmez
            row("65 – Met/Lys",           item.metLys,          "%", raw: true)
            row("66 – M+C/Lys",           item.mCLys,           "%", raw: true)
            row("67 – Arg/Lys",           item.argLys,          "%", raw: true)
            row("68 – Thre/Lys",          item.threLys,         "%", raw: true)
            row("69 – Leu/Lys",           item.leuLys,          "%", raw: true)
            row("71 – Val/Lys",           item.valLys,          "%", raw: true)
            row("72 – Trp/Lys",           item.trpLys,          "%", raw: true)
        }
    }

    private var coeffSection: some View {
        Section("Sindirim Katsayıları") {
            // Katsayılar dönüştürülmez
            row("74 – Katsayı SinMeth",   item.sinMethCoeff,    "%", raw: true)
            row("75 – Katsayı SinLys",    item.sinLysCoeff,     "%", raw: true)
            row("76 – Katsayı SinCys",    item.sinCysCoeff,     "%", raw: true)
            row("77 – Katsayı SinArg",    item.sinArgCoeff,     "%", raw: true)
            row("78 – Katsayı SinThr",    item.sinThrCoeff,     "%", raw: true)
            row("79 – Katsayı SinLeu",    item.sinLeuCoeff,     "%", raw: true)
            row("80 – Katsayı SinIso",    item.sinIsoCoeff,     "%", raw: true)
            row("81 – Katsayı SinVal",    item.sinValCoeff,     "%", raw: true)
            row("82 – Katsayı SinTry",    item.sinTryCoeff,     "%", raw: true)
            row("83 – Katsayı SinPhe",    item.sinPheCoeff,     "%", raw: true)
            row("84 – Katsayı SinHis",    item.sinHisCoeff,     "%", raw: true)
            row("88 – Katsayı Alderman",  item.aldermanCoeff,   "%", raw: true)
            row("91 – Katsayı MAFF",      item.maffCoeff,       "%", raw: true)
            row("96 – Katsayı C&C",       item.ccCoeff,         "%", raw: true)
            row("97 – Katsayı EC-NFE",    item.ecNFECoeff,      "%", raw: true)
            row("98 – Katsayı EC",        item.ecCoeff,         "%", raw: true)
            row("99 – Katsayı COBB",      item.cobbCoeff,       "%", raw: true)
        }
    }

    private var qualitySection: some View {
        Section("Kalite / Diğer") {
            row("131– DCAP",              item.dcap,            "mEq/Kg")
            row("143– Pelet Renk",        item.peletRenk,       "%", raw: true)
            row("144– Pelet Kalite",      item.peletKalite,     "%", raw: true)
            row("145– Prest Kapasite",    item.prestKapasite,   "%", raw: true)
            row("149– PAF",               item.paf,             "%", raw: true)
        }
    }

    private func extrasSection(_ s: FeedIngredient) -> some View {
        Section("Özel Kriterler") {
            ForEach(s.extras.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                row(kv.key, kv.value, "")
            }
        }
    }

    private var sourceSection: some View {
        Section {
            Label(item.sourceFile.isEmpty ? "Manuel" : item.sourceFile, systemImage: "doc.text")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Row helper
    // raw: true → DM dönüşümü uygulanmaz (oranlar, katsayılar, KM kendisi)

    private func row(_ label: String, _ value: Double?, _ unit: String, raw: Bool = false) -> some View {
        let display: Double? = (raw || dmFactor == 1.0) ? value : value.map { $0 * dmFactor }
        return HStack {
            Text(label).foregroundStyle(.primary).font(.callout)
            Spacer()
            if let v = display {
                HStack(spacing: 3) {
                    Text(String(format: "%.2f", v))
                        .font(.callout.monospacedDigit())
                    if !unit.isEmpty {
                        Text(unit).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }
}
