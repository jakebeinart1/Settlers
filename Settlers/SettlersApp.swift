import SwiftUI

@main
struct SettlersApp: App {

    // There used to be an `init()` here forcing `PacingSettingsStore.current`
    // to be read, because that lazy global trapped on a malformed bundled
    // `pacing.yml` and the case for trapping rested on failing at the earliest
    // possible moment. Pacing is now `PacingPreferences` - two named enums in
    // `UserDefaults` with no text form to get wrong and nothing to validate -
    // so there is no bad state left for a startup read to surface.

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
