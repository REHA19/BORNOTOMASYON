import SwiftData
import Foundation

@Model
final class SendRecord {
    var formulaCode:     String = ""
    var formulaName:     String = ""
    var customName:      String = ""
    var customVersion:   String = ""   // dosya adı / versiyon
    var source:          String = ""   // "SingleBlend" veya "MultiBlend"
    var sentAt:          Date   = Date()
    var isSuccess:       Bool   = false
    var serverMessage:   String = ""
    var ingredientCount:      Int    = 0
    var totalKg:              Double = 0
    var ingredientsSnapshot:  String = "[]"   // JSON: [SentIngredientSnap]
    var costPerTon:           Double = 0      // gönderim anındaki ₺/ton maliyeti
    var nutrientsSnapshot:    String = "[]"   // JSON: [SentNutrientSnap]

    init(formulaCode:          String,
         formulaName:          String,
         customName:           String,
         customVersion:        String = "",
         source:               String,
         isSuccess:            Bool,
         serverMessage:        String,
         ingredientCount:      Int,
         totalKg:              Double,
         ingredientsSnapshot:  String = "[]",
         costPerTon:           Double = 0,
         nutrientsSnapshot:    String = "[]") {
        self.formulaCode          = formulaCode
        self.formulaName          = formulaName
        self.customName           = customName
        self.customVersion        = customVersion
        self.source               = source
        self.sentAt               = Date()
        self.isSuccess            = isSuccess
        self.serverMessage        = serverMessage
        self.ingredientCount      = ingredientCount
        self.totalKg              = totalKg
        self.ingredientsSnapshot  = ingredientsSnapshot
        self.costPerTon           = costPerTon
        self.nutrientsSnapshot    = nutrientsSnapshot
    }

    var snapshotIngredients: [SentIngredientSnap] {
        guard let data = ingredientsSnapshot.data(using: .utf8),
              let arr  = try? JSONDecoder().decode([SentIngredientSnap].self, from: data)
        else { return [] }
        return arr
    }

    var snapshotNutrients: [SentNutrientSnap] {
        guard let data = nutrientsSnapshot.data(using: .utf8),
              let arr  = try? JSONDecoder().decode([SentNutrientSnap].self, from: data)
        else { return [] }
        return arr
    }
}

// MARK: - Gönderim anında dondurulan hammadde verisi

struct SentIngredientSnap: Codable, Identifiable {
    var id:          UUID   = UUID()
    var code:        String
    var name:        String
    var amountKg:    Double  // mixPct / 100 * totalKg
    var mixPct:      Double
}

// MARK: - Gönderim anında dondurulan besin değeri

struct SentNutrientSnap: Codable, Identifiable {
    var id:          UUID    = UUID()
    var key:         String
    var displayName: String
    var unit:        String
    var value:       Double
    var minValue:    Double?
    var maxValue:    Double?
}

// MARK: - Besin snapshot'ı formülden üret

extension SendRecord {
    static func buildNutrientSnaps(from formula: BlendFormula) -> String {
        let snaps: [SentNutrientSnap] = formula.constraints
            .filter { $0.isActive && $0.showInResult && $0.currentValue != nil }
            .compactMap { con in
                guard let val = con.currentValue else { return nil }
                return SentNutrientSnap(
                    key:         con.nutrientKey,
                    displayName: con.resolvedDisplayName,
                    unit:        con.unit,
                    value:       val,
                    minValue:    con.minValue,
                    maxValue:    con.maxValue
                )
            }
        return (try? String(data: JSONEncoder().encode(snaps), encoding: .utf8)) ?? "[]"
    }
}
