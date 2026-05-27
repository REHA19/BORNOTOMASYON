import Foundation
import UserNotifications

final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    static let lowStockThreshold: Double = 1000

    // MARK: - İzin İste

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            print("Bildirim izni:", granted ? "verildi" : "reddedildi")
        } catch {
            print("Bildirim izni hatası:", error)
        }
    }

    // MARK: - Satın Alma Uyarısı (Günlük 08:00)

    func schedulePurchaseAlerts(urgentItems: [MaterialMarketInfo]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["purchase-alert-daily"])

        guard !urgentItems.isEmpty else { return }

        let criticals = urgentItems.filter { $0.urgency == .critical }
        let warnings  = urgentItems.filter { $0.urgency == .warning  }

        let content = UNMutableNotificationContent()
        content.title = "Hammadde Satın Alma Uyarısı"

        if !criticals.isEmpty {
            let names = criticals.prefix(2).map { $0.material.materialName }.joined(separator: ", ")
            content.body = "🔴 Kritik: \(names)\(criticals.count > 2 ? " ve \(criticals.count - 2) diğer" : "")"
        } else {
            let names = warnings.prefix(2).map { $0.material.materialName }.joined(separator: ", ")
            content.body = "🟠 Bu hafta alınmalı: \(names)"
        }

        content.sound = .default
        content.badge = (criticals.count + warnings.count) as NSNumber

        var comps = DateComponents()
        comps.hour = 8; comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "purchase-alert-daily", content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Düşük Stok Bildirimleri

    func scheduleLowStockNotifications(for materials: [Material]) async {
        let center = UNUserNotificationCenter.current()

        // Önceki stok bildirimlerini temizle
        center.removePendingNotificationRequests(
            withIdentifiers: materials.map { "lowstock-\($0.id)" }
        )

        let lowStock = materials.filter {
            $0.netStock < Self.lowStockThreshold && $0.netStock >= 0
        }

        for material in lowStock {
            let content = UNMutableNotificationContent()
            content.title = "Düşük Stok Uyarısı"
            content.body = "\(material.materialName): \(formatted(material.netStock)) kg kaldı"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "lowstock-\(material.id)",
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }
    }

    // MARK: - Badge

    func clearBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Uygulama rozeti sayısını günceller: düşük stok + aktif formüllerde stokta olmayan.
    func updateBadge(lowStockCount: Int, outOfStockFormulaCount: Int) async {
        let total = lowStockCount + outOfStockFormulaCount
        try? await UNUserNotificationCenter.current().setBadgeCount(total)
    }

    // MARK: - Private

    private func formatted(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
