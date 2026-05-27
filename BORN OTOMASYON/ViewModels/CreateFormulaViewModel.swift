import SwiftUI
import Combine

@MainActor
class CreateFormulaViewModel: ObservableObject {

    // MARK: - Form alanları
    @Published var productCode    = ""
    @Published var productName    = ""
    @Published var customName     = ""
    @Published var customVersion  = ""
    @Published var hasValidDate   = false
    @Published var validDate      = Date()
    @Published var totalAmount    = ""
    @Published var comment        = ""
    @Published var details:       [FormulaCreateDetailAppModel] = []
    @Published var activate       = true

    // MARK: - UI durumu
    @Published var isLoading      = false
    @Published var successMessage: String?
    @Published var errorMessage:   String?

    private let service = CreateFormulaService()

    // MARK: - Detail yönetimi

    func addDetail() {
        let next = (details.last?.rowNo ?? 0) + 1
        details.append(FormulaCreateDetailAppModel(
            materialCode: "",
            materialName: "",
            rowNo: next,
            amount: 0,
            isAdditive: false
        ))
    }

    func removeDetails(at offsets: IndexSet) {
        details.remove(atOffsets: offsets)
        for i in details.indices { details[i].rowNo = i + 1 }
    }

    // MARK: - Mevcut formülden ön doldur (klonla)

    func prefill(formulaName: String, items: [FormulaDetailItem]) {
        customName   = formulaName
        totalAmount  = String(format: "%.1f", items.reduce(0.0) { $0 + $1.amount })
        details = items.map { item in
            FormulaCreateDetailAppModel(
                materialCode: item.materialCode,
                materialName: item.materialName,
                rowNo: item.rowNo,
                amount: item.amount,
                isAdditive: item.isAdditive
            )
        }
    }

    // MARK: - Gönder

    func submit() async {
        guard !productCode.trimmingCharacters(in: .whitespaces).isEmpty,
              !productName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Ürün kodu ve ürün adı zorunludur."
            return
        }
        let amountStr = totalAmount.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(amountStr), amount > 0 else {
            errorMessage = "Toplam miktar geçerli bir sayı olmalıdır."
            return
        }
        guard !details.isEmpty else {
            errorMessage = "En az bir hammadde satırı ekleyin."
            return
        }

        let model = FormulaCreateAppModel(
            productCode:   productCode.trimmingCharacters(in: .whitespaces),
            productName:   productName.trimmingCharacters(in: .whitespaces),
            customName:    customName.trimmingCharacters(in: .whitespaces),
            customVersion: customVersion.trimmingCharacters(in: .whitespaces),
            validDate:     hasValidDate ? validDate : nil,
            totalAmount:   amount,
            comment:       comment.trimmingCharacters(in: .whitespaces),
            details:       details,
            activate:      activate
        )

        isLoading      = true
        errorMessage   = nil
        successMessage = nil

        do {
            let result = try await service.create(model: model)
            if result.success {
                successMessage = result.message ?? "Formül başarıyla oluşturuldu."
            } else {
                errorMessage = result.message ?? "Formül oluşturulamadı."
            }
        } catch {
            errorMessage = "Hata: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
