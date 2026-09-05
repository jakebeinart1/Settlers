import CatanEngine
import CatanAI

extension GameView {
    /// Autoplays setup and resolves the human's first roll until the ordinary
    /// main-turn controls are genuinely usable. A first roll of seven can add
    /// discard and robber decisions, so stopping immediately after `.rollDice`
    /// leaves visual and UI tests on a disabled action row intermittently.
    /// This remains a visual-QA route only; `QALaunchFlag.isSet` makes it
    /// unreachable in Release.
    func qaFastForwardToRollDiceIfRequested() async {
        #if DEBUG
        guard QALaunchFlag.fastForwardToRollDice.isSet else { return }
        let human = viewModel.humanPlayer
        let bot = Bot(personality: .balanced)
        for _ in 0..<20 {
            switch viewModel.state.phase {
            case .mainTurn(let playerIndex) where playerIndex == human.index:
                return
            case .rollDice(let playerIndex) where playerIndex == human.index:
                await applyQA(.rollDice)
            // Swift binds a `where` only to the pattern immediately before it,
            // so both snake-order cases need their own human-seat condition.
            case .setupForward(let playerIndex) where playerIndex == human.index,
                 .setupBackward(let playerIndex) where playerIndex == human.index:
                let move = bot.decide(for: viewModel.state, player: human)
                await applyQA(move)
            case .discarding(let pending) where pending.contains(human):
                let move = bot.decide(for: viewModel.state, player: human)
                await applyQA(move)
            case .movingRobber(let playerIndex) where playerIndex == human.index:
                let move = bot.decide(for: viewModel.state, player: human)
                await applyQA(move)
            default:
                await viewModel.runBotTurnIfNeeded()
            }
        }
        preconditionFailure("QA fast-forward did not reach the human's playable main turn")
        #endif
    }

    #if DEBUG
    private func applyQA(_ move: GameMove) async {
        do {
            try await viewModel.qaApplyAndAwaitAutomatedTurns(move)
        } catch {
            preconditionFailure("QA fast-forward rejected \(move): \(error)")
        }
    }
    #endif
}
