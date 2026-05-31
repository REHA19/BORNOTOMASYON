import Foundation
import SwiftData

@Model final class FormulaCostEntry {
    var formulaCode: String
    var formulaName: String
    var groupName:   String
    var costPerTon:  Double
    var tons:        Double
    var recordedAt:  Date

    init(formulaCode: String, formulaName: String, groupName: String,
         costPerTon: Double, tons: Double) {
        self.formulaCode = formulaCode
        self.formulaName = formulaName
        self.groupName   = groupName
        self.costPerTon  = costPerTon
        self.tons        = tons
        self.recordedAt  = Date()
    }
}
