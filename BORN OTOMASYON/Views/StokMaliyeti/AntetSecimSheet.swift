import SwiftUI

/// PDF oluşturmadan önce hangi markanın antetinin arka planda kullanılacağını seçtirir.
struct AntetSecimSheet: View {
    let brands:    [BrandDefinition]
    let onSelect:  (BrandDefinition?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        onSelect(nil)
                    } label: {
                        Label("Antetsiz — Sade PDF", systemImage: "doc.text")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Antetli Markalar") {
                    ForEach(brands) { brand in
                        Button {
                            dismiss()
                            onSelect(brand)
                        } label: {
                            HStack(spacing: 12) {
                                if let img = brand.antetImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 72, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.1))
                                        .frame(width: 72, height: 36)
                                }
                                Text(brand.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Antet Seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
