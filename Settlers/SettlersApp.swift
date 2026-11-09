import OSLog
import SwiftUI

@main
struct SettlersApp: App {
    @UIApplicationDelegateAdaptor(OnlineAppDelegate.self) private var onlineAppDelegate
    /// One process owns one checkpoint revision cursor. Constructing this in a
    /// SwiftUI child view created competing models when SwiftUI rebuilt that
    /// view, and the second writer correctly failed as stale.
    private let viewModel: GameViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        CheckpointProcessProbe.runIfRequested()
        #endif
        UITestBootstrap.resetPersistentStateIfRequested()
        // After the reset, which clears the archive: seeding first would write
        // a recording and then delete it.
        #if DEBUG
        QAGameHistoryFixture.seedIfRequested()
        QAGhostFixture.seedIfRequested()
        QAPlayerRatingsFixture.seedIfRequested()
        #endif
        viewModel = GameViewModel()
        viewModel.migrateLegacyPlayerNames()
        // Restore known checkpoints first, then retire any older public
        // shared recordings whose checkpoints are no longer available.
        Task.detached(priority: .utility) {
            do {
                try GameLogStore.shared.migrateLegacyUnfinishedSharedRecordings()
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "Empires", category: "GameHistory")
                    .error("Could not move older shared recordings: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    // Startup used to force-read the retired YAML pacing configuration. The
    // initializer now has one Debug-only purpose: establish a clean process
    // boundary before native UI tests construct ContentView.

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
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
        // Launch and every return to the app check the online ladder, at most
        // once per `LiveSync.refreshInterval`; a finished game syncs at once.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await OnlineDeviceRegistrar.shared.resume() }
            if let sync = LiveSync.shared { Task { await sync.refreshIfDue() } }
        }
    }
}
