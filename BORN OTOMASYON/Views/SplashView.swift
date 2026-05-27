import SwiftUI

struct SplashView: View {
    @State private var splashComplete = false
    @State private var logoScale:    CGFloat = 0.3
    @State private var logoOpacity:  Double  = 0

    var body: some View {
        if splashComplete {
            MainTabView()
        } else {
            ZStack {
                Color(red: 0.02, green: 0.04, blue: 0.13)
                    .ignoresSafeArea()

                Image("BornLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 40)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
            }
            .ignoresSafeArea()
            .task { await runSplash() }
        }
    }

    @MainActor
    private func runSplash() async {
        // Logo büyüyerek yaklaşır
        withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) {
            logoScale   = 1.0
            logoOpacity = 1.0
        }
        // Belli süre bekle, sonra ana menüye geç
        try? await Task.sleep(for: .milliseconds(2800))
        withAnimation(.easeIn(duration: 0.4)) {
            splashComplete = true
        }
    }
}
