import Foundation

// MARK: - Solver Input/Output

struct SolverIngredient {
    let code:         String
    let name:         String
    let priceTLPerTon: Double   // ₺/ton
    let minPct:       Double    // ≥ 0
    let maxPct:       Double    // ≤ 100
    let nutrients:    [String: Double]  // key → as-fed value
}

struct SolverConstraint {
    let key:      String  // nutrient key
    let minValue: Double? // nil = unconstrained
    let maxValue: Double? // nil = unconstrained
}

struct SolverCombination {
    let ingredientCodes: [String]  // bu gruba dahil hammadde kodları
    let minPct: Double?            // toplam min % (nil = kısıtsız)
    let maxPct: Double?            // toplam max % (nil = kısıtsız)
}

struct SolverResult {
    let isFeasible:        Bool
    let percentagesByCode: [String: Double]
    let costPerTon:        Double
    let nutrientValues:    [String: Double]
    let message:           String
}

// MARK: - Revised Simplex (minimisation, equality form via Big-M)

enum RationSolver {
    static func solve(ingredients: [SolverIngredient],
                      constraints: [SolverConstraint],
                      combinations: [SolverCombination] = []) -> SolverResult {
        // maxPct=0 means "no upper limit" → treat as 100
        let active = ingredients.map { ing -> SolverIngredient in
            let max = ing.maxPct > 0 ? ing.maxPct : 100.0
            return SolverIngredient(code: ing.code, name: ing.name,
                                    priceTLPerTon: ing.priceTLPerTon,
                                    minPct: ing.minPct, maxPct: max,
                                    nutrients: ing.nutrients)
        }
        guard !active.isEmpty else {
            return infeasible("Aktif hammadde yok.")
        }

        // Basic feasibility check: sum of mins ≤ 100 ≤ sum of maxes
        let sumMin = active.reduce(0) { $0 + $1.minPct }
        let sumMax = active.reduce(0) { $0 + $1.maxPct }
        if sumMin > 100 + 1e-6 {
            return infeasible(String(format: "Alt sınırların toplamı %.1f%% > 100%% — hammadde sınırlarını kontrol edin.", sumMin))
        }
        if sumMax < 100 - 1e-6 {
            return infeasible(String(format: "Üst sınırların toplamı %.1f%% < 100%% — hammadde sınırlarını genişletin.", sumMax))
        }

        let n = active.count   // decision variables x[0..n-1] = % of ingredient i

        // Build LP in standard form:
        //
        // Variables:   x[0..n-1]  (ingredient %)
        //              s[0..n-1]  slacks for per-ingredient max bound: x[i] + s[i] = max[i]
        //              e[0..n-1]  excess for per-ingredient min bound: x[i] - e[i] = min[i]  (e≥0 when feasible)
        //              sum equality: Σx[i] = 100
        //              nutritional min/max as inequalities converted to equalities via slacks/surplus
        //
        // We use a Big-M two-phase-style approach via artificial variables.
        // For simplicity we use a direct simplex on the augmented tableau.

        // Number of structural constraint rows:
        // 1  → sum = 100
        // n  → x[i] ≤ max[i]   (x[i] + slack = max[i])
        // n  → x[i] ≥ min[i]   (x[i] - surplus + artificial = min[i])
        // For each active nutritional constraint (min or max):
        //   min: Σ(n_ij * x_j) ≥ min  → -Σ + surplus = -min  (flip to ≤ 0?)
        //        actually: Σ n_ij x_j - surplus + artificial = min_val  (surplus≥0,art≥0)
        //   max: Σ n_ij x_j ≤ max     → Σ + slack = max_val

        // Simpler approach: use revised big-M method with all constraints as equalities.
        // We convert every constraint to equality form and add artificial variables where needed.

        let nutKeys = constraints.filter { $0.minValue != nil || $0.maxValue != nil }

        // ── Collect all rows ──────────────────────────────────────────────────

        struct Row {
            var coeffs: [Double]   // length = n (ingredient percents)
            var rhs:    Double
            var needsArtificial: Bool
        }

        var rows: [Row] = []

        // 1. Sum = 100
        rows.append(Row(coeffs: Array(repeating: 1.0, count: n), rhs: 100.0, needsArtificial: true))

        // 2. x[i] ≤ max[i]  (slack added later)
        for i in 0..<n {
            var c = [Double](repeating: 0, count: n); c[i] = 1
            rows.append(Row(coeffs: c, rhs: active[i].maxPct, needsArtificial: false))
        }

        // 3. x[i] ≥ min[i]  (surplus + artificial)
        for i in 0..<n {
            guard active[i].minPct > 0 else { continue }
            var c = [Double](repeating: 0, count: n); c[i] = 1
            rows.append(Row(coeffs: c, rhs: active[i].minPct, needsArtificial: true))
        }

        // 4. Nutritional constraints
        // The LP variables x[i] are in % (0-100) and library nutrient values are also
        // in their original units (% for protein/fat/fiber, KCal/kg for energy, etc.).
        // So Σ(nutrient[i] * x[i]) = actual_mixture_value * 100.
        // To enforce actual_mixture_value ≥ minV, the LP RHS must be minV * 100.
        for con in nutKeys {
            let coeffs: [Double] = active.map { ing in ing.nutrients[con.key] ?? 0 }
            if let minV = con.minValue {
                rows.append(Row(coeffs: coeffs, rhs: minV * 100, needsArtificial: true))
            }
            if let maxV = con.maxValue {
                rows.append(Row(coeffs: coeffs, rhs: maxV * 100, needsArtificial: false))
            }
        }

        // 5. Combination constraints: Σ x[i ∈ group] ≤ maxPct  /  ≥ minPct
        for combo in combinations {
            let indices = combo.ingredientCodes.compactMap { code in
                active.firstIndex { $0.code == code }
            }
            guard !indices.isEmpty else { continue }
            var coeffs = [Double](repeating: 0, count: n)
            for idx in indices { coeffs[idx] = 1 }
            if let maxPct = combo.maxPct, maxPct >= 0 {
                rows.append(Row(coeffs: coeffs, rhs: maxPct, needsArtificial: false))
            }
            if let minPct = combo.minPct, minPct > 0 {
                rows.append(Row(coeffs: coeffs, rhs: minPct, needsArtificial: true))
            }
        }

        let m         = rows.count
        let artCount  = rows.filter { $0.needsArtificial }.count
        let cols      = n + m + artCount + 1
        let objRow    = m

        // ── Flat row-major tableau: cache-friendly tek [Double] ───────────────
        var T    = [Double](repeating: 0, count: (m + 1) * cols)
        var basis = [Int](repeating: -1, count: m)
        var artIdx = 0
        for (r, row) in rows.enumerated() {
            let base = r * cols
            for j in 0..<n { T[base + j] = row.coeffs[j] }
            let sCol = n + r
            if row.needsArtificial {
                T[base + sCol]       = -1
                T[base + n + m + artIdx] = 1
                basis[r]             = n + m + artIdx
                artIdx += 1
            } else {
                T[base + sCol] = 1
                basis[r]       = sCol
            }
            T[base + cols - 1] = row.rhs
        }

        let bigM    = 1_000_000.0
        let objBase = objRow * cols
        for i in 0..<n { T[objBase + i] = active[i].priceTLPerTon / 100.0 }
        for a in 0..<artCount { T[objBase + n + m + a] = bigM }
        for r in 0..<m where basis[r] >= n + m {
            let base = r * cols
            for j in 0..<cols { T[objBase + j] -= bigM * T[base + j] }
        }

        // ── Simplex iterations ────────────────────────────────────────────────
        let maxIter = 1500
        for _ in 0..<maxIter {
            var pivCol = -1; var minRC = -1e-9
            for j in 0..<(cols - 1) {
                let rc = T[objBase + j]; if rc < minRC { minRC = rc; pivCol = j }
            }
            guard pivCol >= 0 else { break }

            var pivRow = -1; var minRatio = Double.infinity
            for r in 0..<m {
                let e = T[r * cols + pivCol]; guard e > 1e-10 else { continue }
                let ratio = T[r * cols + cols - 1] / e
                if ratio < minRatio - 1e-12 { minRatio = ratio; pivRow = r }
            }
            guard pivRow >= 0 else { return infeasible("LP sınırsız.") }

            let pivBase = pivRow * cols
            let pivVal  = T[pivBase + pivCol]
            for j in 0..<cols { T[pivBase + j] /= pivVal }
            T.withUnsafeMutableBufferPointer { buf in
                for r in 0...m {
                    guard r != pivRow else { continue }
                    let fac = buf[r * cols + pivCol]; guard abs(fac) > 1e-15 else { continue }
                    let rb = r * cols
                    for j in 0..<cols { buf[rb + j] -= fac * buf[pivBase + j] }
                }
            }
            basis[pivRow] = pivCol
        }

        // ── Extract solution ──────────────────────────────────────────────────
        var x = [Double](repeating: 0, count: n)
        for r in 0..<m { let b = basis[r]; if b < n { x[b] = T[r * cols + cols - 1] } }

        for r in 0..<m {
            if basis[r] >= n + m, T[r * cols + cols - 1] > 1e-6 {
                return infeasible("Kısıtlar sağlanamadı.")
            }
        }

        // Clamp tiny negatives from floating point
        for i in 0..<n { x[i] = max(0, x[i]) }

        let sumX = x.reduce(0, +)
        guard sumX > 0.1 else { return infeasible("Çözüm sıfır. Kısıtları kontrol edin.") }

        // Build result
        var pctByCode: [String: Double] = [:]
        var costPerTon: Double = 0
        for i in 0..<n {
            pctByCode[active[i].code] = x[i]
            costPerTon += active[i].priceTLPerTon * x[i] / 100.0
        }

        // Compute nutrient values in result
        var nutValues: [String: Double] = [:]
        for con in nutKeys {
            var val = 0.0
            for i in 0..<n {
                val += (active[i].nutrients[con.key] ?? 0) * x[i] / 100.0
            }
            nutValues[con.key] = val
        }

        return SolverResult(
            isFeasible:        true,
            percentagesByCode: pctByCode,
            costPerTon:        costPerTon,
            nutrientValues:    nutValues,
            message:           "Çözüm başarılı. Toplam: \(String(format:"%.2f",sumX))%"
        )
    }

    private static func infeasible(_ msg: String) -> SolverResult {
        SolverResult(isFeasible: false, percentagesByCode: [:],
                     costPerTon: 0, nutrientValues: [:], message: msg)
    }
}

// MARK: - Nutrient key → FeedIngredient property

extension FeedIngredient {
    func nutrientValue(forKey key: String) -> Double? {
        switch key {
        case "dryMatter":        return dryMatter
        case "crudeProtein":     return crudeProtein
        case "crudeAsh":         return crudeAsh
        case "crudeFiber":       return crudeFiber
        case "crudeFat":         return crudeFat
        case "starch":           return starch
        case "sugar":            return sugar
        case "ndf":              return ndf
        case "adf":              return adf
        case "nel":              return nel
        case "me1xNRC":          return me1xNRC
        case "mePoultryFixed":   return mePoultryFixed
        case "meRuminantFixed":  return meRuminantFixed
        case "calcium":          return calcium
        case "phosphorus":       return phosphorus
        case "totalPhosphorus":  return totalPhosphorus
        case "magnesium":        return magnesium
        case "potassium":        return potassium
        case "sodium":           return sodium
        case "chlorine":         return chlorine
        case "methionine":       return methionine
        case "lysine":           return lysine
        case "metCys":           return metCys
        case "tryptophan":       return tryptophan
        case "threonine":        return threonine
        case "arginine":         return arginine
        case "sinLysine":        return sinLysine
        case "sinMethionine":    return sinMethionine
        case "sinMetCys":        return sinMetCys
        case "tdn":              return tdn
        case "pdie":             return pdie
        case "pdin":             return pdin
        case "rdp":              return rdp
        case "rup":              return rup
        case "nfc":              return nfc
        case "nsc":              return nsc
        case "nfe":              return nfe
        case "organicMatter":    return organicMatter
        case "adl":              return adl
        case "ufl":              return ufl
        case "ufv":              return ufv
        case "tse9610":          return tse9610
        case "maffME":           return maffME
        case "pdia":             return pdia
        case "rupCP":            return rupCP
        case "solProtein":       return solProtein
        case "rdsStarch":        return rdsStarch
        case "dcap":             return dcap
        case "peletRenk":        return peletRenk
        case "peletKalite":      return peletKalite
        case "prestKapasite":    return prestKapasite
        case "caP":              return caP
        case "sinTryptophan":    return sinTryptophan
        case "sinArginine":      return sinArginine
        case "sinThreonine":     return sinThreonine
        case "sinLeucine":       return sinLeucine
        case "sinIsoleucine":    return sinIsoleucine
        case "sinValine":        return sinValine
        case "sinCystine":       return sinCystine
        case "sinHistidine":     return sinHistidine
        case "sinPhenylalanin":  return sinPhenylalanin
        case "cystine":          return cystine
        case "leucine":          return leucine
        case "isoleucine":       return isoleucine
        case "valine":           return valine
        case "phenylalanin":     return phenylalanin
        case "histidine":        return histidine
        default:                 return nil
        }
    }
}

// MARK: - Available nutrient definitions for the constraint picker

struct NutrientDef: Identifiable {
    let key:         String
    let displayName: String
    let unit:        String
    var id: String { key }
}

/// Tüm FeedIngredient besin alanları — Hammadde Kütüphanesi ile birebir eşleşir.
let allNutrientDefs: [NutrientDef] = [
    // ── 1. Temel Bileşim ─────────────────────────────────────────────────────
    NutrientDef(key: "dryMatter",        displayName: "Kuru Madde",                unit: "%"),
    NutrientDef(key: "crudeProtein",     displayName: "Ham Protein",               unit: "%"),
    NutrientDef(key: "crudeFat",         displayName: "Ham Yağ",                   unit: "%"),
    NutrientDef(key: "crudeFiber",       displayName: "Ham Selüloz",               unit: "%"),
    NutrientDef(key: "crudeAsh",         displayName: "Ham Kül",                   unit: "%"),
    NutrientDef(key: "starch",           displayName: "Nişasta",                   unit: "%"),
    NutrientDef(key: "sugar",            displayName: "Şeker",                     unit: "%"),
    NutrientDef(key: "ndf",              displayName: "NDF",                       unit: "%"),
    NutrientDef(key: "adf",              displayName: "ADF",                       unit: "%"),
    NutrientDef(key: "adl",              displayName: "ADL",                       unit: "%"),
    NutrientDef(key: "nfc",              displayName: "NFC",                       unit: "%"),
    NutrientDef(key: "nsc",              displayName: "NSC",                       unit: "%"),
    NutrientDef(key: "nfe",              displayName: "NFE",                       unit: "%"),
    NutrientDef(key: "organicMatter",    displayName: "Organik Madde",             unit: "%"),
    // ── 2. Enerji ─────────────────────────────────────────────────────────────
    NutrientDef(key: "nel",              displayName: "NEL 3x Hesap NRC",          unit: "KCal/Kg"),
    NutrientDef(key: "me1xNRC",          displayName: "ME 1x Hesap NRC",           unit: "KCal/Kg"),
    NutrientDef(key: "tse9610",          displayName: "TSE 9610",                  unit: "KCal/Kg"),
    NutrientDef(key: "mePoultryFixed",   displayName: "ME Kanatlı (Sabit)",        unit: "KCal/Kg"),
    NutrientDef(key: "meRuminantFixed",  displayName: "ME Ruminant (Sabit)",       unit: "KCal/Kg"),
    NutrientDef(key: "ufl",              displayName: "UFL INRA",                  unit: ""),
    NutrientDef(key: "ufv",              displayName: "UFV INRA",                  unit: ""),
    NutrientDef(key: "negKazanc",        displayName: "Neg Kazanç",               unit: "KCal/Kg"),
    NutrientDef(key: "maffME",           displayName: "MAFF ME",                   unit: "KCal/Kg"),
    // ── 3. Formüllü Enerji ───────────────────────────────────────────────────
    NutrientDef(key: "meRumAlderman",    displayName: "ME Rum Alderman",           unit: "KCal/Kg"),
    NutrientDef(key: "meRumMaff",        displayName: "ME Rum MAFF",               unit: "KCal/Kg"),
    NutrientDef(key: "mePoultryCC",      displayName: "ME Kanatlı C&C",            unit: "KCal/Kg"),
    NutrientDef(key: "mePoultryECNFE",   displayName: "ME Kanatlı EC-NFE",         unit: "KCal/Kg"),
    NutrientDef(key: "mePoultryEC",      displayName: "ME Kanatlı EC",             unit: "KCal/Kg"),
    NutrientDef(key: "mePoultryCobb",    displayName: "ME Kanatlı COBB",           unit: "KCal/Kg"),
    // ── 4. Protein Parçalanabilirliği ────────────────────────────────────────
    NutrientDef(key: "pdie",             displayName: "PDIE",                      unit: "Gr/Kg"),
    NutrientDef(key: "pdia",             displayName: "PDIA",                      unit: "Gr/Kg"),
    NutrientDef(key: "pdin",             displayName: "PDIN",                      unit: "Gr/Kg"),
    NutrientDef(key: "rdp",              displayName: "RDP",                       unit: "%"),
    NutrientDef(key: "rup",              displayName: "RUP",                       unit: "%"),
    NutrientDef(key: "rupCP",            displayName: "RUP %CP",                   unit: "%"),
    NutrientDef(key: "solProtein",       displayName: "SP Soluble Protein",        unit: "%"),
    NutrientDef(key: "ndcip",            displayName: "NDCIP",                     unit: "%"),
    NutrientDef(key: "adicp",            displayName: "ADICP",                     unit: "%"),
    // ── 5. Karbonhidrat Detay ────────────────────────────────────────────────
    NutrientDef(key: "tdn",              displayName: "TDN",                       unit: "%"),
    NutrientDef(key: "rdsStarch",        displayName: "RDS Rumen Degrede Starch",  unit: "%"),
    NutrientDef(key: "solubleStarch",    displayName: "Soluble Starch",            unit: "%"),
    NutrientDef(key: "slowStarch",       displayName: "Yavaş Nişasta",             unit: "%"),
    NutrientDef(key: "solStarchPct",     displayName: "Çözülebilir Nişasta",       unit: "%"),
    NutrientDef(key: "bypassStarch",     displayName: "By Pass Nişasta",           unit: "%"),
    // ── 6. Makro Mineraller ──────────────────────────────────────────────────
    NutrientDef(key: "calcium",          displayName: "Kalsiyum (Ca)",             unit: "%"),
    NutrientDef(key: "phosphorus",       displayName: "Fosfor (P)",                unit: "%"),
    NutrientDef(key: "totalPhosphorus",  displayName: "Toplam Fosfor",             unit: "%"),
    NutrientDef(key: "availP",           displayName: "Hazır Fosfor",              unit: "%"),
    NutrientDef(key: "availPChick",      displayName: "Hazır Fosfor Civciv",       unit: "%"),
    NutrientDef(key: "magnesium",        displayName: "Magnezyum (Mg)",            unit: "%"),
    NutrientDef(key: "potassium",        displayName: "Potasyum (K)",              unit: "%"),
    NutrientDef(key: "sodium",           displayName: "Sodyum (Na)",               unit: "%"),
    NutrientDef(key: "chlorine",         displayName: "Klor (Cl)",                 unit: "%"),
    NutrientDef(key: "sulfur",           displayName: "Kükürt (S)",                unit: "%"),
    NutrientDef(key: "dcap",             displayName: "DCAP",                      unit: "mEq/Kg"),
    // ── 7. Mikro Mineraller ──────────────────────────────────────────────────
    NutrientDef(key: "zinc",             displayName: "Çinko (Zn)",               unit: "ppm"),
    NutrientDef(key: "manganese",        displayName: "Mangan (Mn)",               unit: "ppm"),
    NutrientDef(key: "copper",           displayName: "Bakır (Cu)",                unit: "ppm"),
    NutrientDef(key: "cobalt",           displayName: "Kobalt (Co)",               unit: "ppm"),
    NutrientDef(key: "iron",             displayName: "Demir (Fe)",                unit: "ppm"),
    NutrientDef(key: "selenium",         displayName: "Selenyum (Se)",             unit: "ppm"),
    NutrientDef(key: "iodine",           displayName: "İyot (I)",                  unit: "ppm"),
    // ── 8. Amino Asitler – Gerçek ────────────────────────────────────────────
    NutrientDef(key: "methionine",       displayName: "Metiyonin",                 unit: "%"),
    NutrientDef(key: "lysine",           displayName: "Lizin",                     unit: "%"),
    NutrientDef(key: "metCys",           displayName: "Met+Cys",                   unit: "%"),
    NutrientDef(key: "cystine",          displayName: "Sistin",                    unit: "%"),
    NutrientDef(key: "tryptophan",       displayName: "Triptofan",                 unit: "%"),
    NutrientDef(key: "arginine",         displayName: "Arjinin",                   unit: "%"),
    NutrientDef(key: "threonine",        displayName: "Treonin",                   unit: "%"),
    NutrientDef(key: "leucine",          displayName: "Lösin",                     unit: "%"),
    NutrientDef(key: "isoleucine",       displayName: "İzolösin",                  unit: "%"),
    NutrientDef(key: "valine",           displayName: "Valin",                     unit: "%"),
    NutrientDef(key: "phenylalanin",     displayName: "Fenilalanin",               unit: "%"),
    NutrientDef(key: "phenyTyr",         displayName: "Pheny+Tyr",                 unit: "%"),
    NutrientDef(key: "histidine",        displayName: "Histidin",                  unit: "%"),
    NutrientDef(key: "tyrosine",         displayName: "Tirozin",                   unit: "%"),
    NutrientDef(key: "glycine",          displayName: "Glisin",                    unit: "%"),
    NutrientDef(key: "serine",           displayName: "Serin",                     unit: "%"),
    NutrientDef(key: "proline",          displayName: "Prolin",                    unit: "%"),
    NutrientDef(key: "alanine",          displayName: "Alanin",                    unit: "%"),
    NutrientDef(key: "asparticAcid",     displayName: "Aspartik Asit",             unit: "%"),
    NutrientDef(key: "glutamicAcid",     displayName: "Glutamik Asit",             unit: "%"),
    NutrientDef(key: "glySer",           displayName: "Gly+Ser",                   unit: "%"),
    // ── 9. Amino Asitler – Sindirilebilir ────────────────────────────────────
    NutrientDef(key: "sinMethionine",    displayName: "Sin. Metiyonin",            unit: "%"),
    NutrientDef(key: "sinLysine",        displayName: "Sin. Lizin",                unit: "%"),
    NutrientDef(key: "sinMetCys",        displayName: "Sin. Met+Cys",              unit: "%"),
    NutrientDef(key: "sinCystine",       displayName: "Sin. Sistin",               unit: "%"),
    NutrientDef(key: "sinTryptophan",    displayName: "Sin. Triptofan",            unit: "%"),
    NutrientDef(key: "sinArginine",      displayName: "Sin. Arjinin",              unit: "%"),
    NutrientDef(key: "sinThreonine",     displayName: "Sin. Treonin",              unit: "%"),
    NutrientDef(key: "sinLeucine",       displayName: "Sin. Lösin",                unit: "%"),
    NutrientDef(key: "sinIsoleucine",    displayName: "Sin. İzolösin",             unit: "%"),
    NutrientDef(key: "sinValine",        displayName: "Sin. Valin",                unit: "%"),
    NutrientDef(key: "sinPhenylalanin",  displayName: "Sin. Fenilalanin",          unit: "%"),
    NutrientDef(key: "sinHistidine",     displayName: "Sin. Histidin",             unit: "%"),
    // ── 10. Yağ Asitleri ─────────────────────────────────────────────────────
    NutrientDef(key: "linoleicAcid",     displayName: "Linoleik Asit",             unit: "%"),
    NutrientDef(key: "linolenicAcid",    displayName: "Linolenik Asit",            unit: "%"),
    NutrientDef(key: "arachidonicAcid",  displayName: "Araşidonik Asit",           unit: "%"),
    NutrientDef(key: "choline",          displayName: "Kolin",                     unit: "%"),
    NutrientDef(key: "lauricAcid",       displayName: "Laurik Asit",               unit: "%"),
    NutrientDef(key: "myristicAcid",     displayName: "Miristik Asit",             unit: "%"),
    NutrientDef(key: "palmiticAcid",     displayName: "Palmitik Asit",             unit: "%"),
    NutrientDef(key: "palmoleicAcid",    displayName: "Palmoleik Asit",            unit: "%"),
    NutrientDef(key: "stearicAcid",      displayName: "Stearik Asit",              unit: "%"),
    NutrientDef(key: "oleicAcid",        displayName: "Oleik Asit",                unit: "%"),
    NutrientDef(key: "unsatFattyAcid",   displayName: "Doymamış Yağ Asiti",       unit: "%"),
    NutrientDef(key: "satFattyAcid",     displayName: "Doymuş Yağ Asiti",         unit: "%"),
    NutrientDef(key: "freeFat",          displayName: "Serbest Yağ",               unit: "%"),
    NutrientDef(key: "totalFattyAcid",   displayName: "Toplam Yağ Asiti",         unit: "%"),
    // ── 11. Kalite / Diğer ───────────────────────────────────────────────────
    NutrientDef(key: "peletRenk",        displayName: "Pelet Renk",                unit: ""),
    NutrientDef(key: "peletKalite",      displayName: "Pelet Kalite",              unit: ""),
    NutrientDef(key: "prestKapasite",    displayName: "Prest Kapasite",            unit: ""),
    NutrientDef(key: "paf",              displayName: "PAF",                       unit: ""),
]
