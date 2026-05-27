import Foundation

/// Import önizlemesi için geçici struct — SwiftData yok.
/// rptBesinMaddeleri.txt sıralamasıyla tam eşleşme.
struct FeedIngredientCandidate: Identifiable {
    var id: String { name }

    // Kimlik
    var name:       String
    var code:       String
    var priceTL:    Double?
    var sourceFile: String = ""

    // ── 1. Temel Bileşim ──
    var dryMatter:    Double?   // 1  - KURU MADDE
    var crudeProtein: Double?   // 2  - HAM PROTEİN
    var crudeAsh:     Double?   // 7  - HAM KÜL
    var crudeFiber:   Double?   // 6  - HAM SELÜLOZ
    var crudeFat:     Double?   // 5  - HAM YAĞ
    var starch:       Double?   // 54 - NİŞASTA
    var sugar:        Double?   // 53 - ŞEKER
    var ndf:          Double?   // 111- NDF
    var adf:          Double?   // 112- ADF
    var adl:          Double?   // 113- ADL
    var nfc:          Double?   // 119- NFC
    var nsc:          Double?   // 120- NSC
    var nfe:          Double?   // 85 - NFE
    var organicMatter:Double?   // 160- ORGANİK MADDE

    // ── 2. Enerji ──
    var nel:             Double?  // 114- NEL 3x Hesap NRC   (KCal/Kg)
    var me1xNRC:         Double?  // 115- ME 1x Hesap NRC    (KCal/Kg)
    var tse9610:         Double?  // 116- TSE 9610           (KCal/Kg)
    var mePoultryFixed:  Double?  // 4  - ME KANATLI (Sabit) (KCal/Kg)
    var meRuminantFixed: Double?  // 3  - ME RUMINANT (Sabit)(KCal/Kg)
    var ufl:             Double?  // 117- UFL INRA
    var ufv:             Double?  // 118- UFV INRA
    var negKazanc:       Double?  // 146- Neg Kazanç         (KCal/Kg)
    var maffME:          Double?  // 161- MAFF ME            (KCal/Kg)

    // ── 3. Formüllü Enerji ──
    var meRumAlderman:  Double?   // 90 - ME RUM ALDERMAN
    var meRumMaff:      Double?   // 92 - ME RUM MAFF
    var mePoultryCC:    Double?   // 104- ME KANATLI C&C
    var mePoultryECNFE: Double?   // 105- ME KANATLI EC-NFE
    var mePoultryEC:    Double?   // 106- ME KANATLI EC
    var mePoultryCobb:  Double?   // 107- ME KANATLI COBB

    // ── 4. Protein Parçalanabilirliği ──
    var pdie:            Double?  // 155- PDIE (Gr/Kg)
    var pdia:            Double?  // 156- PDIA (Gr/Kg)
    var pdin:            Double?  // 154- PDIN (Gr/Kg)
    var rdp:             Double?  // 132- RDP
    var rup:             Double?  // 133- RUP
    var rupCP:           Double?  // 134- RUP %CP
    var frakA:           Double?  // 135- Frak. A
    var frakB:           Double?  // 136- Frak. B
    var frakC:           Double?  // 137- Frak. C
    var degradationRateB:Double?  // 138- Parçalanma Hızı-B
    var solProtein:      Double?  // 139- SP Soluble Protein
    var ndcip:           Double?  // 147- NDCIP
    var adicp:           Double?  // 148- ADICP

    // ── 5. Karbonhidrat Detay ──
    var tdn:           Double?    // 140- TDN
    var rdsStarch:     Double?    // 141- RDS Rumen Degrede Starch
    var solubleStarch: Double?    // 142- Soluble Starch
    var slowStarch:    Double?    // 157- YAVAŞ NİŞASTA
    var solStarchPct:  Double?    // 158- ÇÖZÜLEBİLİR NİŞASTA
    var bypassStarch:  Double?    // 159- BY PASS NİŞASTA

    // ── 6. Makro Mineraller ──
    var calcium:         Double?  // 16 - Ca (%)
    var phosphorus:      Double?  // 17 - P  (%)
    var totalPhosphorus: Double?  // 18 - TOPLAM FOSFOR (%)
    var availP:          Double?  // 152- HAZ. FOSFOR (%)
    var availPChick:     Double?  // 153- HAZ. FOSFOR CİVCİV (%)
    var magnesium:       Double?  // 121- Mg (%)
    var potassium:       Double?  // 122- K  (%)
    var sodium:          Double?  // 21 - Na (%)
    var chlorine:        Double?  // 23 - Cl (%)
    var sulfur:          Double?  // 123- S  (%)
    var caP:             Double?  // 19 - Ca/P oranı

    // ── 7. Mikro Mineraller (ppm) ──
    var zinc:      Double?        // 124- Zn
    var manganese: Double?        // 125- Mn
    var copper:    Double?        // 126- Cu
    var cobalt:    Double?        // 127- Co
    var iron:      Double?        // 128- Fe
    var selenium:  Double?        // 129- Se
    var iodine:    Double?        // 130- I

    // ── 8. Amino Asitler – Gerçek (%) ──
    var methionine:  Double?      // 8  - METHIONINE
    var lysine:      Double?      // 10 - LYSINE
    var metCys:      Double?      // 12 - METH + CYS
    var cystine:     Double?      // 14 - CYSTINE
    var tryptophan:  Double?      // 34 - TRYPTOPHAN
    var arginine:    Double?      // 24 - ARGININE
    var threonine:   Double?      // 26 - THREONINE
    var leucine:     Double?      // 28 - LEUCINE
    var isoleucine:  Double?      // 30 - ISOLEUCINE
    var valine:      Double?      // 32 - VALINE
    var phenylalanin:Double?      // 36 - PHENYLALANIN
    var phenyTyr:    Double?      // 38 - PHENY+TYR
    var glycine:     Double?      // 39 - GLYCINE
    var histidine:   Double?      // 40 - HISTIDINE
    var tyrosine:    Double?      // 42 - TYROSINE
    var serine:      Double?      // 43 - SERINE
    var proline:     Double?      // 44 - PROLINE
    var alanine:     Double?      // 45 - ALANINE
    var asparticAcid:Double?      // 46 - ASPARTIC ASIT
    var glutamicAcid:Double?      // 47 - GLUTAMIC ACID
    var glySer:      Double?      // 48 - GLY + SER

    // ── 9. Amino Asitler – Sindirilebilir (%) ──
    var sinMethionine:  Double?   // 9  - SIN. METHIONINE
    var sinLysine:      Double?   // 11 - SIN. LYSINE
    var sinMetCys:      Double?   // 13 - SIN. MET + CYS
    var sinCystine:     Double?   // 15 - SIN. CYSTINE
    var sinTryptophan:  Double?   // 35 - SIN. TRYPTOPHAN
    var sinArginine:    Double?   // 25 - SIN. ARGININE
    var sinThreonine:   Double?   // 27 - SIN. THREONINE
    var sinLeucine:     Double?   // 29 - SIN. LEUCINE
    var sinIsoleucine:  Double?   // 31 - SIN. ISOLEUCINE
    var sinValine:      Double?   // 33 - SIN. VALINE
    var sinPhenylalanin:Double?   // 37 - SIN. PHENYLALANIN
    var sinHistidine:   Double?   // 41 - SIN. HISTIDINE

    // ── 10. Yağ Asitleri (%) ──
    var linoleicAcid:    Double?  // 49 - LİNOLEİK ASIT
    var linolenicAcid:   Double?  // 50 - LİNOLENİK ASIT
    var arachidonicAcid: Double?  // 51 - ARASIDONIK ASIT
    var choline:         Double?  // 52 - KOLİN
    var lauricAcid:      Double?  // 55 - LAURIC ASIT
    var myristicAcid:    Double?  // 56 - MYRISTIC ASIT
    var palmiticAcid:    Double?  // 57 - PALMITIC ASIT
    var palmoleicAcid:   Double?  // 58 - PALMOLEIC ASIT
    var stearicAcid:     Double?  // 59 - STEARIC ASIT
    var oleicAcid:       Double?  // 60 - OLEIC ASIT
    var unsatFattyAcid:  Double?  // 61 - DOYMAMIŞ YAĞ ASİTİ
    var satFattyAcid:    Double?  // 62 - DOYMUŞ YAĞ ASİTİ
    var freeFat:         Double?  // 63 - SERBEST YAĞ
    var totalFattyAcid:  Double?  // 64 - TOPLAM YAĞ ASİTİ

    // ── 11. Oranlar ──
    var metLys:  Double?          // 65 - MET/LYS
    var mCLys:   Double?          // 66 - M+C/LYS
    var argLys:  Double?          // 67 - ARG/LYS
    var threLys: Double?          // 68 - THRE/LYS
    var leuLys:  Double?          // 69 - LEU/LYS
    var valLys:  Double?          // 71 - VAL/LYS
    var trpLys:  Double?          // 72 - TRP/LYS

    // ── 12. Sindirim Katsayıları ──
    var sinMethCoeff: Double?     // 74 - KATSAYI SINMETH
    var sinLysCoeff:  Double?     // 75 - KATSAYI SINLYS
    var sinCysCoeff:  Double?     // 76 - KATSAYI SINCYS
    var sinArgCoeff:  Double?     // 77 - KATSAYI SINARG
    var sinThrCoeff:  Double?     // 78 - KATSAYI SINTHR
    var sinLeuCoeff:  Double?     // 79 - KATSAYI SINLEU
    var sinIsoCoeff:  Double?     // 80 - KATSAYI SINISO
    var sinValCoeff:  Double?     // 81 - KATSAYI SINVAL
    var sinTryCoeff:  Double?     // 82 - KATSAYI SINTRY
    var sinPheCoeff:  Double?     // 83 - KATSAYI SINPHE
    var sinHisCoeff:  Double?     // 84 - KATSAYI SINHIS
    var aldermanCoeff:Double?     // 88 - KATSAYI ALDERMAN
    var maffCoeff:    Double?     // 91 - KATSAYI MAFF
    var ccCoeff:      Double?     // 96 - KATSAYI C&C
    var ecNFECoeff:   Double?     // 97 - KATSAYI EC-NFE
    var ecCoeff:      Double?     // 98 - KATSAYI EC
    var cobbCoeff:    Double?     // 99 - KATSAYI COBB

    // ── 13. Kalite / Diğer ──
    var dcap:         Double?     // 131- DCAP (mEq/Kg)
    var peletRenk:    Double?     // 143- Pelet Renk
    var peletKalite:  Double?     // 144- Pelet Kalite
    var prestKapasite:Double?     // 145- Prest Kapasite
    var paf:          Double?     // 149- PAF
}
