import SwiftUI
import Combine

// MARK: - Ayarlanabilir sütun genişliği altyapısı
//
// Tablo görünümleri (MaliyetTablosu, Toplu Fiyat Güncelleme, Kombinasyonlar …)
// sütun genişliklerini sabit sayılarla yazıyordu. Bu dosya bu genişlikleri
// kullanıcı tarafından sürüklenerek ayarlanabilir ve UserDefaults'ta kalıcı
// hâle getirir.
//
// Kullanım:
//   @StateObject private var colWidths = ColumnWidthStore(tableID: "maliyetTablosu")
//   ...
//   Text(baslik)
//       .frame(width: colWidths.width("urun", default: 150))
//       .resizableColumn("urun", default: 150, store: colWidths)

@MainActor
final class ColumnWidthStore: ObservableObject {

    static let minWidth: CGFloat = 34
    static let maxWidth: CGFloat = 460

    private let storageKey: String
    private let ud = UserDefaults.standard

    /// Sadece kullanıcı tarafından değiştirilen sütunlar tutulur —
    /// dokunulmayan sütunlar her zaman kodda tanımlı varsayılanı kullanır.
    @Published private(set) var overrides: [String: CGFloat] = [:]

    init(tableID: String) {
        self.storageKey = "tbl.\(tableID).colWidths"
        if let raw = ud.string(forKey: storageKey),
           let data = raw.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            overrides = dict.mapValues { CGFloat($0) }
        }
    }

    // MARK: Okuma

    func width(_ column: String, default fallback: CGFloat) -> CGFloat {
        overrides[column] ?? fallback
    }

    func isCustom(_ column: String) -> Bool { overrides[column] != nil }

    var hasCustomWidths: Bool { !overrides.isEmpty }

    // MARK: Yazma

    func set(_ newWidth: CGFloat, for column: String) {
        let clamped = min(max(newWidth.rounded(), Self.minWidth), Self.maxWidth)
        guard overrides[column] != clamped else { return }
        overrides[column] = clamped
        persist()
    }

    /// `column` nil ise tablodaki tüm sütunlar varsayılana döner.
    func reset(_ column: String? = nil) {
        if let column {
            guard overrides[column] != nil else { return }
            overrides.removeValue(forKey: column)
        } else {
            guard !overrides.isEmpty else { return }
            overrides.removeAll()
        }
        persist()
    }

    private func persist() {
        let plain = overrides.mapValues { Double($0) }
        guard let data = try? JSONEncoder().encode(plain),
              let raw  = String(data: data, encoding: .utf8) else { return }
        ud.set(raw, forKey: storageKey)
    }
}

// MARK: - Sürükleme tutamacı

struct ColumnResizeHandle: View {
    let column:        String
    let defaultWidth:  CGFloat
    @ObservedObject var store: ColumnWidthStore

    @State private var startWidth: CGFloat? = nil

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 16)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                Capsule()
                    .fill(dragging ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: dragging ? 3 : 2)
                    .padding(.vertical, 3)
            }
            // ScrollView(.horizontal) içinde kaydırma yerine tutamacın kazanması için
            // highPriorityGesture — normal .gesture ScrollView tarafından yutuluyor.
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = startWidth ?? store.width(column, default: defaultWidth)
                        if startWidth == nil { startWidth = base }
                        store.set(base + value.translation.width, for: column)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            // Çift dokunuş → bu sütunu varsayılana döndür
            .onTapGesture(count: 2) { store.reset(column) }
            .accessibilityLabel("Sütun genişliğini ayarla")
    }

    private var dragging: Bool { startWidth != nil }
}

// MARK: - View yardımcıları

extension View {
    /// Başlık hücresinin sağ kenarına sürüklenebilir bir tutamaç yerleştirir.
    /// Hücrenin kendi genişliğini değiştirmez — tutamaç overlay olarak durur.
    func resizableColumn(_ column: String,
                         default defaultWidth: CGFloat,
                         store: ColumnWidthStore) -> some View {
        overlay(alignment: .trailing) {
            ColumnResizeHandle(column: column, defaultWidth: defaultWidth, store: store)
        }
    }
}

// MARK: - "Sütun genişliklerini sıfırla" menü öğesi

struct ColumnWidthResetButton: View {
    @ObservedObject var store: ColumnWidthStore

    var body: some View {
        Button(role: .destructive) {
            store.reset()
        } label: {
            Label("Sütun Genişliklerini Sıfırla", systemImage: "arrow.counterclockwise")
        }
        .disabled(!store.hasCustomWidths)
    }
}
