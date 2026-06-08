import SwiftData
import Foundation

// Monthly tonnage limit for a single ingredient across the whole group
struct MonthlyIngLimit: Codable, Equatable {
    var maxTons: Double?
    var minTons: Double?
}

@Model
final class MultiBlendGroup {
    var name:                    String = ""
    var createdAt:               Date   = Date()
    var orderIndex:              Int    = 0
    var formulaCodesJSON:        String = "[]"
    var productionTonsJSON:      String = "{}"   // [formulaCode: Double] — tons/month
    var monthlyIngLimitsJSON:    String = "{}"   // [ingCode: MonthlyIngLimit]
    var productionSnapshotJSON:     String = "{}"   // [formulaCode: Double] — locked production costPerTon
    var productionSnapshotTonsJSON: String = "{}"   // [formulaCode: Double] — locked production tons
    var productionSnapshotAt:       Date   = Date(timeIntervalSinceReferenceDate: 0)
    // Ingredient codes manually marked "STOK YOK" — persist in list even if removed from formulas
    var stokYokCodesJSON:        String = "[]"

    init(name: String, orderIndex: Int = 0) {
        self.name                   = name
        self.createdAt              = Date()
        self.orderIndex             = orderIndex
        self.formulaCodesJSON       = "[]"
        self.productionTonsJSON     = "{}"
        self.monthlyIngLimitsJSON   = "{}"
        self.productionSnapshotJSON     = "{}"
        self.productionSnapshotTonsJSON = "{}"
        self.productionSnapshotAt       = Date(timeIntervalSinceReferenceDate: 0)
        self.stokYokCodesJSON       = "[]"
    }

    // MARK: - formulaCodes

    var formulaCodes: [String] {
        get {
            guard let data = formulaCodesJSON.data(using: .utf8),
                  let arr  = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            var seen = Set<String>()
            let unique = arr.filter { seen.insert($0).inserted }
            // Mükerrer varsa kalıcı olarak düzelt — CloudKit yeniden kirletse bile her okumada temizlenir
            if unique.count < arr.count {
                formulaCodesJSON = (try? String(data: JSONEncoder().encode(unique), encoding: .utf8)) ?? "[]"
            }
            return unique
        }
        set {
            var seen = Set<String>()
            let unique = newValue.filter { seen.insert($0).inserted }
            formulaCodesJSON = (try? String(data: JSONEncoder().encode(unique), encoding: .utf8)) ?? "[]"
        }
    }

    // MARK: - productionTons

    var productionTons: [String: Double] {
        get {
            guard let data = productionTonsJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: Double].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            productionTonsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}"
        }
    }

    // MARK: - monthlyIngLimits

    var monthlyIngLimits: [String: MonthlyIngLimit] {
        get {
            guard let data = monthlyIngLimitsJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: MonthlyIngLimit].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            monthlyIngLimitsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}"
        }
    }

    // MARK: - productionSnapshot ([formulaCode: costPerTon])

    var productionSnapshot: [String: Double] {
        get {
            guard let data = productionSnapshotJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: Double].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            productionSnapshotJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}"
        }
    }

    // MARK: - productionSnapshotTons ([formulaCode: tons at lock time])

    var productionSnapshotTons: [String: Double] {
        get {
            guard let data = productionSnapshotTonsJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: Double].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            productionSnapshotTonsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}"
        }
    }

    var hasProductionSnapshot: Bool {
        productionSnapshotAt > Date(timeIntervalSinceReferenceDate: 1)
    }

    // MARK: - stokYokCodes

    var stokYokCodes: Set<String> {
        get {
            guard let data = stokYokCodesJSON.data(using: .utf8),
                  let arr  = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(arr)
        }
        set {
            stokYokCodesJSON = (try? String(
                data: JSONEncoder().encode(Array(newValue)), encoding: .utf8
            )) ?? "[]"
        }
    }

    func markStokYok(_ code: String) {
        var s = stokYokCodes; s.insert(code); stokYokCodes = s
    }

    func clearStokYok(_ code: String) {
        var s = stokYokCodes; s.remove(code); stokYokCodes = s
    }

    // MARK: - Helpers

    func addFormula(code: String) {
        var codes = formulaCodes
        guard !codes.contains(code) else { return }
        codes.append(code)
        formulaCodes = codes
    }

    func removeFormula(code: String) {
        formulaCodes = formulaCodes.filter { $0 != code }
    }

    /// `formulaCodesJSON` içindeki mükerrer kodları kalıcı olarak temizler.
    /// Düzeltme yapıldıysa `true` döner — çağıran taraf `context.save()` yapmalıdır.
    @discardableResult
    func deduplicateFormulaCodes() -> Bool {
        guard let data = formulaCodesJSON.data(using: .utf8),
              let arr  = try? JSONDecoder().decode([String].self, from: data)
        else { return false }
        var seen = Set<String>()
        let unique = arr.filter { seen.insert($0).inserted }
        guard unique.count < arr.count else { return false }   // zaten temiz
        formulaCodesJSON = (try? String(data: JSONEncoder().encode(unique), encoding: .utf8)) ?? "[]"
        return true
    }
}
