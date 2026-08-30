import SwiftUI

@main
struct SettlersApp: App {

    init() {
        // Forces the pacing config to be read and validated now.
        //
        // `PacingSettingsStore.current` is a lazy global that traps on a
        // malformed `pacing.yml`. Left to itself, its first read is whenever
        // the bot loop or the roll highlight happens to run - so a bad edit
        // would take the app down mid-game, after someone had started one.
        // The entire case for trapping rather than falling back to defaults is
        // that it fails at the earliest possible moment, and that is only true
        // if something reads it at the earliest possible moment.
        _ = PacingSettingsStore.current
    }

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
