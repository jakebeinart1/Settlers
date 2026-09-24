#if DEBUG
import CatanEngine

extension GameViewModel {
    /// Starts a four-seat game on the 61-tile `GameMode.vast` board.
    ///
    /// The mode's rules were settled by simulation - 24 of 24 games decisive,
    /// no piece limit reached, the deck never emptied - but simulation cannot
    /// answer whether 61 hexes are legible and tappable on a phone, and that is
    /// the question that decides whether the mode is any fun. This exists so
    /// that screen can be photographed at real render size.
    func qaStartVastGame(variant: GameVariant = .standard) {
        let settings = CivilizationSettingsStore.shared.load()
        var setup = MatchSetup.default(
            preferredName: PlayerNameStore.shared.load().isEmpty ? "You" : PlayerNameStore.shared.load(),
            preferredCivilization: settings.yourCivilization
        )
        setup.mode = .vast
        setup.variant = variant
        setup.victoryPointTarget = Ruleset.forMode(.vast).defaultVictoryPointTarget
        setup.randomizedBoard = true
        setup.randomizeSeatOrder = false
        precondition(setup.isStartable, "vast QA setup invalid: \(setup.validationProblem ?? "")")
        startNewGame(setup: setup)
    }

    /// A Classic-board Conquest game, the same way: through a real `MatchSetup`.
    func qaStartClassicConquestGame() {
        let settings = CivilizationSettingsStore.shared.load()
        var setup = MatchSetup.default(
            preferredName: PlayerNameStore.shared.load().isEmpty ? "You" : PlayerNameStore.shared.load(),
            preferredCivilization: settings.yourCivilization
        )
        setup.variant = .conquest
        setup.randomizedBoard = false
        setup.randomizeSeatOrder = false
        precondition(setup.isStartable, "conquest QA setup invalid: \(setup.validationProblem ?? "")")
        startNewGame(setup: setup)
    }
}
#endif
