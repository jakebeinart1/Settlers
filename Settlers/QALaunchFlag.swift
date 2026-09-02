import Foundation

/// The launch arguments that put the app straight into a particular screen or
/// state, so visual QA can reach expensive or nondeterministic situations
/// without playing hundreds of moves first.
///
/// ## Why launch arguments at all
/// `simctl` has no touch injection, while synthetic mouse coordinates are
/// unreliable. Native XCUITests drive ordinary accessible controls and prove
/// the core player journeys. These flags complement them by constructing rare
/// states such as a finished game or a specific trade card deterministically.
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
    /// Opens `NewGameSetupView` over the main menu, on a fixture with two human
    /// seats and two AI seats - a startable configuration, so the screen shows
    /// its green ready plaque and an enabled Start.
    case showNewGame = "-qaShowNewGame"
    /// Starts a two-human hot-seat game so the handoff cover can be
    /// photographed. Combine with `-qaAutoStart`.
    case twoHumans = "-qaTwoHumans"
    /// Same screen, on a fixture whose second human seat has a whitespace-only
    /// name - so the amber problem plaque and the disabled Start can be
    /// photographed too. Without this the invalid state is unreachable, because
    /// nothing can type into the field.
    case showNewGameInvalid = "-qaShowNewGameInvalid"
    /// Same screen and fixture as `showNewGame`, with the "this replaces your
    /// saved game" confirmation already raised.
    case showNewGameOverwrite = "-qaShowNewGameOverwrite"
    /// Same screen and fixture as `showNewGame`, with seat 2's civilization
    /// picker open - the only way to photograph a taken civilization showing as
    /// unavailable (A3.3) and the whole eight-empire grid fitting without
    /// scrolling (A3.4).
    case showNewGameCivilizationPicker = "-qaShowNewGameCivilizationPicker"
    /// Combines with any of the above: shrinks the fixture to a three-player
    /// table through `MatchSetup.resize`, so the missing fourth seat and the
    /// note explaining it can be photographed.
    case newGameThreeSeats = "-qaNewGameThreeSeats"
    /// Combines with the New Game flags and opens a tall-device layout at its
    /// bottom for focused screenshots. Short devices use the compact layout,
    /// where the complete configuration and Start action fit at once.
    case scrollNewGameToBottom = "-qaScrollNewGameToBottom"
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
