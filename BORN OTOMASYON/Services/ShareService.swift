import UIKit

/// UIActivityViewController'ı mevcut en üst view controller'dan present eder.
/// SwiftUI'da .sheet() içine gömmek yerine bu fonksiyonu kullan — iç içe
/// presentation'dan kaynaklanan siyah ekran sorununu önler.
enum ShareService {

    /// `delay`: kapanan sheet animasyonunun bitmesini bekler.
    /// Bir sheet dismiss edildikten sonra çağrıldığında >= 0.55 kullan.
    static func share(items: [Any], delay: Double = 0.6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let topVC = topViewController() else { return }
            // VC hâlâ geçiş animasyonundaysa bir kez daha bekle
            if topVC.isBeingPresented || topVC.isBeingDismissed ||
               topVC.isMovingToParent || topVC.isMovingFromParent {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    presentActivity(items: items, from: topVC)
                }
            } else {
                presentActivity(items: items, from: topVC)
            }
        }
    }

    private static func presentActivity(items: [Any], from topVC: UIViewController) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = topVC.view
            pop.sourceRect = CGRect(
                x: topVC.view.bounds.midX,
                y: topVC.view.bounds.midY,
                width: 1, height: 1
            )
            pop.permittedArrowDirections = []
        }
        topVC.present(vc, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        guard let scene  = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              var top    = window.rootViewController
        else { return nil }

        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
