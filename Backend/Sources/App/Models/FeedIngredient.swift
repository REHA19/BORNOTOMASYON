import Fluent
import Vapor

/// Mirrors iOS Models/FeedIngredientModel.swift field-for-field — fully normalized
/// (not JSONB) because RationSolver reads each nutrient column individually (Plan §1).
final class FeedIngredient: Model, Content, @unchecked Sendable {
    static let schema = "feed_ingredients"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "code")
    var code: String

    @Field(key: "name")
    var name: String

    @OptionalField(key: "price_tl")
    var priceTL: Double?

    @Field(key: "is_available")
    var isAvailable: Bool

    @Field(key: "source_file")
    var sourceFile: String

    @Field(key: "version")
    var version: Int

    @Timestamp(key: "imported_at", on: .create)
    var importedAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalField(key: "dry_matter")
    var dryMatter: Double?

    @OptionalField(key: "crude_protein")
    var crudeProtein: Double?

    @OptionalField(key: "crude_ash")
    var crudeAsh: Double?

    @OptionalField(key: "crude_fiber")
    var crudeFiber: Double?

    @OptionalField(key: "crude_fat")
    var crudeFat: Double?

    @OptionalField(key: "starch")
    var starch: Double?

    @OptionalField(key: "sugar")
    var sugar: Double?

    @OptionalField(key: "ndf")
    var ndf: Double?

    @OptionalField(key: "adf")
    var adf: Double?

    @OptionalField(key: "adl")
    var adl: Double?

    @OptionalField(key: "nfc")
    var nfc: Double?

    @OptionalField(key: "nsc")
    var nsc: Double?

    @OptionalField(key: "nfe")
    var nfe: Double?

    @OptionalField(key: "organic_matter")
    var organicMatter: Double?

    @OptionalField(key: "nel")
    var nel: Double?

    @OptionalField(key: "me1x_n_r_c")
    var me1xNRC: Double?

    @OptionalField(key: "tse9610")
    var tse9610: Double?

    @OptionalField(key: "me_poultry_fixed")
    var mePoultryFixed: Double?

    @OptionalField(key: "me_ruminant_fixed")
    var meRuminantFixed: Double?

    @OptionalField(key: "ufl")
    var ufl: Double?

    @OptionalField(key: "ufv")
    var ufv: Double?

    @OptionalField(key: "neg_kazanc")
    var negKazanc: Double?

    @OptionalField(key: "maff_m_e")
    var maffME: Double?

    @OptionalField(key: "me_rum_alderman")
    var meRumAlderman: Double?

    @OptionalField(key: "me_rum_maff")
    var meRumMaff: Double?

    @OptionalField(key: "me_poultry_c_c")
    var mePoultryCC: Double?

    @OptionalField(key: "me_poultry_e_c_n_f_e")
    var mePoultryECNFE: Double?

    @OptionalField(key: "me_poultry_e_c")
    var mePoultryEC: Double?

    @OptionalField(key: "me_poultry_cobb")
    var mePoultryCobb: Double?

    @OptionalField(key: "pdie")
    var pdie: Double?

    @OptionalField(key: "pdia")
    var pdia: Double?

    @OptionalField(key: "pdin")
    var pdin: Double?

    @OptionalField(key: "rdp")
    var rdp: Double?

    @OptionalField(key: "rup")
    var rup: Double?

    @OptionalField(key: "rup_c_p")
    var rupCP: Double?

    @OptionalField(key: "frak_a")
    var frakA: Double?

    @OptionalField(key: "frak_b")
    var frakB: Double?

    @OptionalField(key: "frak_c")
    var frakC: Double?

    @OptionalField(key: "degradation_rate_b")
    var degradationRateB: Double?

    @OptionalField(key: "sol_protein")
    var solProtein: Double?

    @OptionalField(key: "ndcip")
    var ndcip: Double?

    @OptionalField(key: "adicp")
    var adicp: Double?

    @OptionalField(key: "tdn")
    var tdn: Double?

    @OptionalField(key: "rds_starch")
    var rdsStarch: Double?

    @OptionalField(key: "soluble_starch")
    var solubleStarch: Double?

    @OptionalField(key: "slow_starch")
    var slowStarch: Double?

    @OptionalField(key: "sol_starch_pct")
    var solStarchPct: Double?

    @OptionalField(key: "bypass_starch")
    var bypassStarch: Double?

    @OptionalField(key: "calcium")
    var calcium: Double?

    @OptionalField(key: "phosphorus")
    var phosphorus: Double?

    @OptionalField(key: "total_phosphorus")
    var totalPhosphorus: Double?

    @OptionalField(key: "avail_p")
    var availP: Double?

    @OptionalField(key: "avail_p_chick")
    var availPChick: Double?

    @OptionalField(key: "magnesium")
    var magnesium: Double?

    @OptionalField(key: "potassium")
    var potassium: Double?

    @OptionalField(key: "sodium")
    var sodium: Double?

    @OptionalField(key: "chlorine")
    var chlorine: Double?

    @OptionalField(key: "sulfur")
    var sulfur: Double?

    @OptionalField(key: "ca_p")
    var caP: Double?

    @OptionalField(key: "zinc")
    var zinc: Double?

    @OptionalField(key: "manganese")
    var manganese: Double?

    @OptionalField(key: "copper")
    var copper: Double?

    @OptionalField(key: "cobalt")
    var cobalt: Double?

    @OptionalField(key: "iron")
    var iron: Double?

    @OptionalField(key: "selenium")
    var selenium: Double?

    @OptionalField(key: "iodine")
    var iodine: Double?

    @OptionalField(key: "methionine")
    var methionine: Double?

    @OptionalField(key: "lysine")
    var lysine: Double?

    @OptionalField(key: "met_cys")
    var metCys: Double?

    @OptionalField(key: "cystine")
    var cystine: Double?

    @OptionalField(key: "tryptophan")
    var tryptophan: Double?

    @OptionalField(key: "arginine")
    var arginine: Double?

    @OptionalField(key: "threonine")
    var threonine: Double?

    @OptionalField(key: "leucine")
    var leucine: Double?

    @OptionalField(key: "isoleucine")
    var isoleucine: Double?

    @OptionalField(key: "valine")
    var valine: Double?

    @OptionalField(key: "phenylalanin")
    var phenylalanin: Double?

    @OptionalField(key: "pheny_tyr")
    var phenyTyr: Double?

    @OptionalField(key: "glycine")
    var glycine: Double?

    @OptionalField(key: "histidine")
    var histidine: Double?

    @OptionalField(key: "tyrosine")
    var tyrosine: Double?

    @OptionalField(key: "serine")
    var serine: Double?

    @OptionalField(key: "proline")
    var proline: Double?

    @OptionalField(key: "alanine")
    var alanine: Double?

    @OptionalField(key: "aspartic_acid")
    var asparticAcid: Double?

    @OptionalField(key: "glutamic_acid")
    var glutamicAcid: Double?

    @OptionalField(key: "gly_ser")
    var glySer: Double?

    @OptionalField(key: "sin_methionine")
    var sinMethionine: Double?

    @OptionalField(key: "sin_lysine")
    var sinLysine: Double?

    @OptionalField(key: "sin_met_cys")
    var sinMetCys: Double?

    @OptionalField(key: "sin_cystine")
    var sinCystine: Double?

    @OptionalField(key: "sin_tryptophan")
    var sinTryptophan: Double?

    @OptionalField(key: "sin_arginine")
    var sinArginine: Double?

    @OptionalField(key: "sin_threonine")
    var sinThreonine: Double?

    @OptionalField(key: "sin_leucine")
    var sinLeucine: Double?

    @OptionalField(key: "sin_isoleucine")
    var sinIsoleucine: Double?

    @OptionalField(key: "sin_valine")
    var sinValine: Double?

    @OptionalField(key: "sin_phenylalanin")
    var sinPhenylalanin: Double?

    @OptionalField(key: "sin_histidine")
    var sinHistidine: Double?

    @OptionalField(key: "linoleic_acid")
    var linoleicAcid: Double?

    @OptionalField(key: "linolenic_acid")
    var linolenicAcid: Double?

    @OptionalField(key: "arachidonic_acid")
    var arachidonicAcid: Double?

    @OptionalField(key: "choline")
    var choline: Double?

    @OptionalField(key: "lauric_acid")
    var lauricAcid: Double?

    @OptionalField(key: "myristic_acid")
    var myristicAcid: Double?

    @OptionalField(key: "palmitic_acid")
    var palmiticAcid: Double?

    @OptionalField(key: "palmoleic_acid")
    var palmoleicAcid: Double?

    @OptionalField(key: "stearic_acid")
    var stearicAcid: Double?

    @OptionalField(key: "oleic_acid")
    var oleicAcid: Double?

    @OptionalField(key: "unsat_fatty_acid")
    var unsatFattyAcid: Double?

    @OptionalField(key: "sat_fatty_acid")
    var satFattyAcid: Double?

    @OptionalField(key: "free_fat")
    var freeFat: Double?

    @OptionalField(key: "total_fatty_acid")
    var totalFattyAcid: Double?

    @OptionalField(key: "met_lys")
    var metLys: Double?

    @OptionalField(key: "m_c_lys")
    var mCLys: Double?

    @OptionalField(key: "arg_lys")
    var argLys: Double?

    @OptionalField(key: "thre_lys")
    var threLys: Double?

    @OptionalField(key: "leu_lys")
    var leuLys: Double?

    @OptionalField(key: "val_lys")
    var valLys: Double?

    @OptionalField(key: "trp_lys")
    var trpLys: Double?

    @OptionalField(key: "sin_meth_coeff")
    var sinMethCoeff: Double?

    @OptionalField(key: "sin_lys_coeff")
    var sinLysCoeff: Double?

    @OptionalField(key: "sin_cys_coeff")
    var sinCysCoeff: Double?

    @OptionalField(key: "sin_arg_coeff")
    var sinArgCoeff: Double?

    @OptionalField(key: "sin_thr_coeff")
    var sinThrCoeff: Double?

    @OptionalField(key: "sin_leu_coeff")
    var sinLeuCoeff: Double?

    @OptionalField(key: "sin_iso_coeff")
    var sinIsoCoeff: Double?

    @OptionalField(key: "sin_val_coeff")
    var sinValCoeff: Double?

    @OptionalField(key: "sin_try_coeff")
    var sinTryCoeff: Double?

    @OptionalField(key: "sin_phe_coeff")
    var sinPheCoeff: Double?

    @OptionalField(key: "sin_his_coeff")
    var sinHisCoeff: Double?

    @OptionalField(key: "alderman_coeff")
    var aldermanCoeff: Double?

    @OptionalField(key: "maff_coeff")
    var maffCoeff: Double?

    @OptionalField(key: "cc_coeff")
    var ccCoeff: Double?

    @OptionalField(key: "ec_n_f_e_coeff")
    var ecNFECoeff: Double?

    @OptionalField(key: "ec_coeff")
    var ecCoeff: Double?

    @OptionalField(key: "cobb_coeff")
    var cobbCoeff: Double?

    @OptionalField(key: "dcap")
    var dcap: Double?

    @OptionalField(key: "pelet_renk")
    var peletRenk: Double?

    @OptionalField(key: "pelet_kalite")
    var peletKalite: Double?

    @OptionalField(key: "prest_kapasite")
    var prestKapasite: Double?

    @OptionalField(key: "paf")
    var paf: Double?


    init() {}

    init(id: UUID? = nil, code: String, name: String, priceTL: Double? = nil, isAvailable: Bool = true, sourceFile: String = "") {
        self.id = id
        self.code = code
        self.name = name
        self.priceTL = priceTL
        self.isAvailable = isAvailable
        self.sourceFile = sourceFile
        self.version = 1
    }
}
