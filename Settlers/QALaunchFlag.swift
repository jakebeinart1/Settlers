import Foundation

/// The launch arguments that put the app straight into a particular screen or
/// state, so it can be screenshotted without simulating taps.
///
/// ## Why launch arguments at all
/// There is no way to drive a SwiftUI app on the simulator from outside it.
/// `simctl` has no touch injection; SwiftUI renders as one opaque canvas to
/// the accessibility APIs, so there is no element tree to click into by name;
/// and driving the Simulator window with synthetic mouse events is both
/// unreliable (window coordinates do not map onto device points) and dangerous
/// (a click can land on whatever Mac window happens to be frontmost). So the
/// app puts itself into the state instead, and the tooling only photographs.
///
/// ## Why these are collected here rather than read inline
/// They used to be twelve separate `ProcessInfo.processInfo.arguments.contains`
/// calls spread across four files, none of them behind a compilation guard, so
/// test scaffolding shipped in release builds and there was no single place to
/// find out what hooks existed. `isSet` is hard-wired to `false` outside DEBUG,
/// which keeps every call site compiling unchanged while making the flags
/// unreachable in a build a player could run.
///
/// Practical exposure was always low - an app launched from SpringBoard gets no
/// extra `argv` - but "the attacker cannot reach it" is a weaker guarantee than
/// "the code is not in the binary".
enum QALaunchFlag: String, CaseIterable {
    /// Skips `MainMenuView` and lands on the board.
    case autoStart = "-qaAutoStart"
    /// Forces a human win and shows `EndGameView`.
    case showEndGame = "-qaShowEndGame"
    /// Opens the settings sheet over the main menu.
    case showSettings = "-qaShowSettings"
    /// Opens `InGameSettingsView`, which absorbed the old pause menu. The flag
    /// keeps its original spelling so the run-settlers skill's documented list
    /// of hooks stays accurate.
    case showPauseMenu = "-qaShowPauseMenu"
    /// Opens the trade popup.
    case showTradePopup = "-qaShowTradePopup"
    /// Opens the build popup.
    case showBuildPopup = "-qaShowBuildPopup"
    /// Opens the monopoly resource picker.
    case showMonopolyPopup = "-qaShowMonopolyPopup"
    /// Seeds a pending trade confirmation banner.
    case showPendingTradeConfirmation = "-qaShowPendingTradeConfirmation"
    /// Arms voluntary knight robber targeting.
    case showRobberTargeting = "-qaShowRobberTargeting"
    /// Seeds a fake incoming offer card.
    case showIncomingOffer = "-qaShowIncomingOffer"
    /// Arms a robber tile that has an eligible victim, to reach the victim picker.
    case showRobberVictimPicker = "-qaShowRobberVictimPicker"
    /// Plays the human's own setup placements so the `.rollDice` action row can
    /// be reached. Unlike the others this applies real moves, so it writes the
    /// save file and the game log. It also needs real wall-clock time - bot
    /// turns sleep between actions - so wait 10-12s before screenshotting.
    case fastForwardToRollDice = "-qaFastForwardToRollDice"

    /// Whether this flag was passed on launch. Always `false` in a release
    /// build, whatever the arguments say.
    var isSet: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(rawValue)
        #else
        return false
        #endif
    }
}
