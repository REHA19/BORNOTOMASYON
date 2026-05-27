import SwiftUI

struct MaterialDetailView: View {
    @StateObject private var viewModel: MaterialDetailViewModel

    init(material: Material) {
        _viewModel = StateObject(wrappedValue: MaterialDetailViewModel(material: material))
    }

    var body: some View {
        List {
            Section("Malzeme Bilgileri") {
                infoRow(label: "Kod", value: viewModel.material.materialCode)
                infoRow(label: "Ad", value: viewModel.material.materialName)
                infoRow(label: "ID", value: "\(viewModel.material.id)")
            }

            Section("Stok Durumu") {
                HStack {
                    Text("Net Stok")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.formattedStock)
                        .fontWeight(.bold)
                }

                HStack {
                    Text("Durum")
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.stockStatus.color)
                            .frame(width: 8, height: 8)
                        Text(viewModel.stockStatus.label)
                            .fontWeight(.medium)
                    }
                }
            }

            Section("Tarih") {
                infoRow(label: "Geçerlilik", value: viewModel.formattedDate)
            }
        }
        .navigationTitle(viewModel.material.materialCode)
        .navigationBarTitleDisplayMode(.large)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}
