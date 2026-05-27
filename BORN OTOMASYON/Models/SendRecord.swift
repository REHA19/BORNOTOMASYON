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

    init(formulaCode:          String,
         formulaName:          String,
         customName:           String,
         customVersion:        String = "",
         source:               String,
         isSuccess:            Bool,
         serverMessage:        String,
         ingredientCount:      Int,
         totalKg:              Double,
         ingredientsSnapshot:  String = "[]") {
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
    }

    var snapshotIngredients: [SentIngredientSnap] {
        guard let data = ingredientsSnapshot.data(using: .utf8),
              let arr  = try? JSONDecoder().decode([SentIngredientSnap].self, from: data)
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
