import Foundation
import CatanEngine

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
/// They used to be scattered `ProcessInfo.processInfo.arguments.contains`
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
    /// Plays every seat through the production session until a real winner.
    case playToEnd = "-qaPlayToEnd"
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
    /// Installs a main-turn position where every paid construction is legal.
    case paidBuildPosition = "-qaPaidBuildPosition"
    /// Opens a paid road/settlement/city decision directly for visual QA.
    case showPaidRoadDecision = "-qaShowPaidRoadDecision"
    case showPaidSettlementDecision = "-qaShowPaidSettlementDecision"
    case showPaidCityDecision = "-qaShowPaidCityDecision"
    /// Opens the monopoly resource picker.
    case showMonopolyPopup = "-qaShowMonopolyPopup"
    /// Installs a mixed five-type private hand and opens the real card shelf.
    case showDevCardHand = "-qaShowDevCardHand"
    /// Installs a legal purchase position with Monopoly fixed on top. The UI
    /// test must still tap Build and buy through the production path.
    case devCardPurchase = "-qaDevCardPurchase"
    /// Modifier for board-decision fixtures: build a supported three-player
    /// table instead of inheriting the default four-player table.
    case threePlayerTable = "-qaThreePlayerTable"
    /// Modifier for board-decision fixtures: make seat 2 the acting human, so
    /// UI coverage does not silently depend on the historical seat-0 default.
    case humanSeatTwo = "-qaHumanSeatTwo"
    /// Performs a real committed Year of Plenty purchase so the private reveal
    /// can be inspected without depending on a shuffled deck.
    case showDevCardReveal = "-qaShowDevCardReveal"
    /// Buys the tenth point through the real engine path. The reveal must own
    /// the screen before the end-game surface appears.
    case showWinningDevCardReveal = "-qaShowWinningDevCardReveal"
    /// Seeds a pending trade confirmation banner.
    case showPendingTradeConfirmation = "-qaShowPendingTradeConfirmation"
    /// Arms voluntary knight robber targeting.
    case showRobberTargeting = "-qaShowRobberTargeting"
    /// Starts a real two-road preview from a playable Road Building card.
    case showRoadBuildingDecision = "-qaShowRoadBuildingDecision"
    /// Starts the mandatory rolled-seven robber flow with three victims.
    case showMandatoryRobberDecision = "-qaShowMandatoryRobberDecision"
    /// Seeds a real pending offer with deterministic conserved hands.
    case showIncomingOffer = "-qaShowIncomingOffer"
    /// A Conquest main turn: the human holds one hex, a rival holds another, the
    /// rest are tribes; the human has army cards and resources. For photographing
    /// the ownership rings and exercising a deploy.
    case showConquest = "-qaShowConquest"
    /// `-qaShowConquest` with the Deploy Army board decision already begun.
    case showDeployArmy = "-qaShowDeployArmy"
    /// **Modifier** for `-qaAutoStart`: starts the game in `GameMode.vast`
    /// rather than Classic, so the 61-tile board can be photographed at real
    /// render size. Whether that board is legible on a phone is the one
    /// question about the mode that simulation cannot answer.
    case vastMode = "-qaVastMode"
    /// **Modifier** for `-qaShowIncomingOffer`: widens the offer to the widest
    /// bundle the engine permits, four give types against one want type.
    /// Expert composes multi-resource offers now (`maxComposedTradeGive = 5`,
    /// `maxComposedTradeWant = 3`), and the single-resource fixture could never
    /// show what that does to the card's fixed-height row.
    case bundleOffer = "-qaBundleOffer"
    /// Stages the mandatory robber fixture's three-victim destination, without
    /// selecting a victim or committing the move.
    case showRobberVictimPicker = "-qaShowRobberVictimPicker"
    /// Installs a conserved eight-card hand owing a four-card discard.
    case showDiscard = "-qaShowDiscard"
    /// Opens `GameHistoryView` over the main menu. Pair with
    /// `-qaSeedGameHistory`, or the screen correctly shows its empty state.
    case showGameHistory = "-qaShowGameHistory"
    /// Writes one short finished recording into the archive before the menu
    /// appears, so the history list and the replay screen have a deterministic
    /// game to open. Real recordings need a played-out match; this is the only
    /// way to reach the archive in a test that has not spent a minute playing
    /// one.
    case seedGameHistory = "-qaSeedGameHistory"
    /// Opens the newest recording's replay directly, so the board, the score
    /// strip and the transport controls can be photographed without a tap.
    /// Pair with `-qaSeedGameHistory`.
    case showReplay = "-qaShowReplay"
    /// Plays the human's setup placements and first roll, including discard and
    /// robber resolution when that roll is seven, until main-turn controls are
    /// enabled. Unlike the others this applies real moves, so it writes the save
    /// file and game log. Bot pacing means callers must wait for UI readiness.
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

/// Parameterized launch values that would otherwise require one Boolean flag
/// per fixture value. Keep parsing beside `QALaunchFlag` so Release retains the
/// same hard boundary: no QA argument can alter a player build.
enum QALaunchOption {
    private static let devCardPurchasePrefix = "-qaDevCardPurchase="

    static var devCardPurchase: DevCardType? {
        #if DEBUG
        if QALaunchFlag.devCardPurchase.isSet { return .monopoly }
        guard let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix(devCardPurchasePrefix)
        }) else { return nil }
        let rawValue = String(argument.dropFirst(devCardPurchasePrefix.count))
        guard let card = DevCardType(rawValue: rawValue) else {
            preconditionFailure("Unknown QA development card: \(rawValue)")
        }
        return card
        #else
        return nil
        #endif
    }
}
