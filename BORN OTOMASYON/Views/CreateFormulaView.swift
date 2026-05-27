import SwiftUI

struct CreateFormulaView: View {
    @StateObject private var viewModel = CreateFormulaViewModel()
    @Environment(\.dismiss) private var dismiss

    // Mevcut formülden klonlama için opsiyonel ön doldurucu
    var prefillName:  String?
    var prefillItems: [FormulaDetailItem]?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Ürün Bilgileri
                Section {
                    field("Ürün Kodu *",  text: $viewModel.productCode)
                    field("Ürün Adı *",   text: $viewModel.productName)
                    field("Özel Ad",      text: $viewModel.customName)
                    field("Versiyon",     text: $viewModel.customVersion)
                } header: { Text("Ürün Bilgileri") }

                // MARK: Tarih & Miktar
                Section {
                    Toggle("Geçerlilik Tarihi", isOn: $viewModel.hasValidDate)
                    if viewModel.hasValidDate {
                        DatePicker("Tarih", selection: $viewModel.validDate, displayedComponents: .date)
                    }
                    HStack {
                        Text("Toplam Miktar (kg) *")
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("0,0", text: $viewModel.totalAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    Toggle("Aktif", isOn: $viewModel.activate)
                } header: { Text("Miktar & Durum") }

                // MARK: Yorum
                Section {
                    TextField("İsteğe bağlı...", text: $viewModel.comment, axis: .vertical)
                        .lineLimit(3...6)
                } header: { Text("Yorum") }

                // MARK: Hammadde Satırları
                Section {
                    ForEach(viewModel.details.indices, id: \.self) { idx in
                        DetailRowView(detail: $viewModel.details[idx], rowIndex: idx)
                    }
                    .onDelete(perform: viewModel.removeDetails)

                    Button {
                        viewModel.addDetail()
                    } label: {
                        Label("Hammadde Ekle", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Hammadde İçeriği (\(viewModel.details.count) kalem)")
                        Spacer()
                        EditButton()
                            .font(.caption)
                    }
                }

                // MARK: Özet miktar kontrolü
                if !viewModel.details.isEmpty {
                    Section {
                        HStack {
                            Text("Satır toplamı")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(fmtKg(detailRowTotal))
                                .fontWeight(.semibold)
                                .foregroundColor(detailDiff < 0.1 ? .green : .orange)
                        }
                    } header: { Text("Kontrol") }
                }
            }
            .navigationTitle("Yeni Formül")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button("Kaydet") {
                            Task { await viewModel.submit() }
                        }
                        .fontWeight(.bold)
                    }
                }
            }
            .alert("Başarılı", isPresented: Binding(
                get: { viewModel.successMessage != nil },
                set: { if !$0 { viewModel.successMessage = nil } }
            )) {
                Button("Tamam") { dismiss() }
            } message: {
                Text(viewModel.successMessage ?? "")
            }
            .alert("Hata", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                if let name = prefillName, let items = prefillItems {
                    viewModel.prefill(formulaName: name, items: items)
                }
            }
        }
    }

    // MARK: - Computed

    private var detailRowTotal: Double {
        viewModel.details.reduce(0.0) { $0 + $1.amount }
    }

    private var detailDiff: Double {
        let declared = Double(viewModel.totalAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return abs(detailRowTotal - declared)
    }

    // MARK: - Yardımcılar

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(placeholder).foregroundColor(.secondary)
            Spacer()
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func fmtKg(_ v: Double) -> String { v.kgString }
}

// MARK: - DetailRowView

private struct DetailRowView: View {
    @Binding var detail: FormulaCreateDetailAppModel
    let rowIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Satır \(detail.rowNo)")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.8))
                    .cornerRadius(4)
                if detail.isAdditive {
                    Text("Katkı")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            HStack {
                Text("Kod").foregroundColor(.secondary).frame(width: 40, alignment: .leading)
                TextField("Malzeme kodu", text: $detail.materialCode)
                    .autocorrectionDisabled()
            }
            HStack {
                Text("Ad").foregroundColor(.secondary).frame(width: 40, alignment: .leading)
                TextField("Malzeme adı", text: $detail.materialName)
            }
            HStack {
                Text("Miktar").foregroundColor(.secondary).frame(width: 55, alignment: .leading)
                TextField("0,0", value: $detail.amount, format: .number)
                    .keyboardType(.decimalPad)
                Text("kg").foregroundColor(.secondary)
                Spacer()
                Toggle("Katkı", isOn: $detail.isAdditive)
                    .labelsHidden()
                Text("Katkı").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .font(.subheadline)
    }
}
