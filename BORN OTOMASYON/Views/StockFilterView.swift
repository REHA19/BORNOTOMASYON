import SwiftUI

struct StockFilterView: View {
    @Environment(\.dismiss) private var dismiss

    var onApply: (StockRequest) -> Void

    @State private var warehouseCode: String = ""
    @State private var materialCodesText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Depo") {
                    TextField("Depo kodu (boş = tümü)", text: $warehouseCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section("Malzeme Kodları") {
                    TextField("Virgülle ayır: KEPEK 14, MELAS 10", text: $materialCodesText)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Filtrele")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Uygula") {
                        onApply(buildRequest())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func buildRequest() -> StockRequest {
        var request = StockRequest()

        let trimmed = warehouseCode.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { request.warehouseCode = trimmed }

        let codes = materialCodesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !codes.isEmpty { request.materialCodes = codes }

        return request
    }
}
