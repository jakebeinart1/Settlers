import SwiftUI

@main
struct SettlersApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // The whole app is a fixed dark-blue/water palette designed
                // around light text - it was never built to also support a
                // light system appearance. Without this, any `Text` that
                // relies on the system's implicit `.primary` color (rather
                // than an explicit white/`CatanTheme.onWaterText`) rendered
                // near-black on a phone set to Light mode, unreadable
                // against these backgrounds - forcing dark mode here pins
                // `.primary` to white everywhere, matching what every
                // explicitly-colored label already looked like.
                .preferredColorScheme(.dark)
        }
    }
}
