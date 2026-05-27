import SwiftUI
import UserNotifications

struct SettingsView: View {

    // MARK: - Server
    @AppStorage("serverIP")         private var serverIP: String = "192.168.2.77"
    @State private var threshold: Double = {
        let v = UserDefaults.standard.double(forKey: "lowStockThreshold")
        return v == 0 ? 1000 : v
    }()

    // MARK: - Theme
    @AppStorage("appColorScheme")   private var colorSchemeStr: String = "system"

    // MARK: - Yazı Boyutu
    @AppStorage("textSizeStep") private var textSizeStep: Int = 1   // 0-4, maks = 4

    // MARK: - Notifications data
    @StateObject private var notifVM = NotificationsViewModel()

    // MARK: - UI
    @State private var showSaved    = false
    @State private var notifExpanded = true

    var body: some View {
        NavigationStack {
            Form {
                notificationsSection
                themeSection
                fontSizeSection
                serverSection
                thresholdSection
                comingSoonSection
                infoSection
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") {
                        UserDefaults.standard.set(threshold, forKey: "lowStockThreshold")
                        showSaved = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Kaydedildi", isPresented: $showSaved) {
                Button("Tamam", role: .cancel) {}
            }
        }
        .task { await notifVM.onAppear() }
        .onAppear { clearBadge() }
    }

    // MARK: - Bildirimler

    private var notificationsSection: some View {
        Section {
            if notifVM.isLoading {
                HStack {
                    ProgressView()
                    Text("Kontrol ediliyor…").foregroundStyle(.secondary)
                }
            } else if let err = notifVM.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if notifVM.lowStockMaterials.isEmpty {
                Label("Kritik stok uyarısı yok", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(notifVM.lowStockMaterials) { mat in
                    NotifRow(material: mat, threshold: threshold)
                }
                Button {
                    Task { await notifVM.refresh() }
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .foregroundStyle(Color.accentColor)
            }
        } header: {
            HStack {
                Label("Bildirimler", systemImage: "bell.badge.fill")
                    .foregroundStyle(.red)
                Spacer()
                if !notifVM.lowStockMaterials.isEmpty {
                    Text("\(notifVM.lowStockMaterials.count) uyarı")
                        .font(.caption2)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
        } footer: {
            Text("Düşük stok eşiğinin altındaki hammaddeler burada listelenir.")
        }
    }

    // MARK: - Tema

    private var themeSection: some View {
        Section {
            Picker("Tema", selection: $colorSchemeStr) {
                Label("Sistem",  systemImage: "circle.lefthalf.filled").tag("system")
                Label("Açık",    systemImage: "sun.max.fill")           .tag("light")
                Label("Koyu",    systemImage: "moon.fill")              .tag("dark")
            }
            .pickerStyle(.menu)
        } header: {
            Label("Uygulama Teması", systemImage: "paintbrush.fill")
        }
    }

    // MARK: - Yazı & Rakam Boyutu

    private static let sizeLabels = ["Küçük", "Normal", "Büyük", "Çok Büyük", "En Büyük"]
    // Maksimum adım = 4 (.xxxLarge) — erişilebilirlik boyutları kasıtlı olarak hariç

    private var fontSizeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Mevcut boyut etiketi
                HStack {
                    Text("Seçili Boyut")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.sizeLabels[textSizeStep])
                        .font(.callout.bold())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }

                // Slider  (min 0, max 4)
                HStack(spacing: 10) {
                    Image(systemName: "textformat.size.smaller")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(textSizeStep) },
                            set: { textSizeStep = Int($0.rounded()) }
                        ),
                        in: 0...4,
                        step: 1
                    )
                    .tint(.blue)
                    Image(systemName: "textformat.size.larger")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Canlı önizleme
                HStack(spacing: 6) {
                    Text("Önizleme:")
                        .foregroundStyle(.secondary)
                    Text("Hammadde")
                        .bold()
                    Text("1.234,56 ₺")
                        .bold()
                        .foregroundStyle(.orange)
                }
                .font(.body)
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
        } header: {
            Label("Yazı & Rakam Boyutu", systemImage: "textformat.size")
        } footer: {
            Text("Uygulama genelinde tüm metin ve rakamlara uygulanır. Maksimum: En Büyük.")
                .font(.caption2)
        }
    }

    // MARK: - Sunucu

    private var serverSection: some View {
        Section {
            LabeledContent("IP Adresi") {
                TextField("192.168.x.x", text: $serverIP)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
            }
            LabeledContent("Port", value: "5001")
                .foregroundStyle(.secondary)
        } header: {
            Label("Sunucu", systemImage: "server.rack")
        }
    }

    // MARK: - Bildirim Eşiği

    private var thresholdSection: some View {
        Section {
            LabeledContent("Uyarı Limiti") {
                HStack {
                    TextField("1000", value: $threshold, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                    Text("kg").foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Bildirim Eşiği", systemImage: "slider.horizontal.3")
        } footer: {
            Text("Bu değerin altındaki malzemeler bildirim gönderir.")
        }
    }

    // MARK: - Yakında

    private var comingSoonSection: some View {
        Section {
            comingSoonRow("Dil / Bölge",          icon: "globe",               note: "Yakında")
            comingSoonRow("Dışa Aktar (Excel)",    icon: "tablecells",          note: "Yakında")
            comingSoonRow("Yedekleme & Geri Yükle",icon: "arrow.trianglehead.clockwise.rotate.90", note: "Yakında")
            comingSoonRow("Kullanıcı Hesabı",      icon: "person.crop.circle",  note: "Yakında")
        } header: {
            Label("Gelecek Özellikler", systemImage: "sparkles")
        }
    }

    private func comingSoonRow(_ title: String, icon: String, note: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(.systemFill), in: Capsule())
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Uygulama Bilgisi

    private var infoSection: some View {
        Section {
            LabeledContent("Versiyon", value: "1.0.0")
            LabeledContent("API Endpoint", value: "/api/FactoryNetStockOut")
        } header: {
            Label("Uygulama", systemImage: "info.circle")
        }
    }

    // MARK: - Badge sıfırla

    private func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }
}

// MARK: - Bildirim satırı

private struct NotifRow: View {
    let material:  Material
    let threshold: Double

    private var stockColor: Color {
        material.netStock <= 0 ? .red : material.netStock < 500 ? .orange : .yellow
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(stockColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(stockColor)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(material.materialName)
                    .font(.subheadline).fontWeight(.medium)
                Text(material.materialCode)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(material.netStock.decimalString + " kg")
                    .font(.subheadline).bold()
                    .foregroundStyle(stockColor)
                Text("Eşik: \(Int(threshold).formatted()) kg")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
