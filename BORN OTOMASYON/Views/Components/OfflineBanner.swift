import SwiftUI

struct OfflineBanner: View {
    let cacheDate: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("Sunucu kapalı — önbellekten gösteriliyor")
                    .font(.system(size: 12, weight: .semibold))
                Text("Son kayıt: \(cacheDate.trClock)")
                    .font(.system(size: 11))
                    .opacity(0.85)
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange)
    }
}
