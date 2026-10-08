#if DEBUG
import CatanEngine
import SwiftUI

extension GameViewModel {
    /// A conserved pre-roll Naval position, including a real purchased hull and
    /// an unplayed Knight. Native tests still tap the ordinary Roll Dice action;
    /// the fixture never installs the discard or its subsequent robber phase.
    func qaPrepareNavalSevenPosition() {
        guard let options = state.naval?.options else {
            preconditionFailure("Naval seven QA requires an actual Naval match")
        }
        let owner = QALaunchFlag.humanSeatTwo.isSet ? PlayerID(index: 1) : humanPlayer
        let difficulty: BotDifficulty = QALaunchFlag.navalExpert.isSet ? .expert : .classic
        do {
            var fixture = try NavalQAFixture.make(.voyage, options: options)
            _ = try NavalQAFixture.purchase(for: PlayerID(index: 0), in: &fixture)
            for player in fixture.players {
                NavalQAFixture.replaceHand([:], for: player.id, in: &fixture)
            }
            NavalQAFixture.replaceHand([.brick: 1, .lumber: 4, .ore: 1, .wool: 2], for: owner, in: &fixture)
            qaTransferNavalSevenKnight(to: owner, in: &fixture)
            fixture.phase = .rollDice(playerIndex: owner.index)
            fixture.rng = NavalQAFixture.rollSource(total: 7)
            qaValidateNavalSevenPosition(fixture)
            replaceStateForTesting(fixture, humanSeat: owner, difficulty: difficulty)
        } catch { preconditionFailure("Naval pre-roll seven QA is invalid: \(error)") }
    }

    private func qaTransferNavalSevenKnight(to owner: PlayerID, in state: inout GameState) {
        guard let index = state.devCardDeck.firstIndex(of: .knight) else {
            preconditionFailure("Naval seven QA has no Knight in its actual deck")
        }
        state.players[owner.index].devCards.append(state.devCardDeck.remove(at: index))
    }

    private func qaValidateNavalSevenPosition(_ state: GameState) {
        precondition(state.rules.discardThreshold == 7 && Naval.validationProblem(in: state) == nil)
        precondition(Resource.allCases.allSatisfy { resource in
            let held = state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
            return state.bank[resource, default: 0] + held == state.rules.bankPerResource
        }, "Naval seven QA changed a resource supply")
    }
}

extension GameView {
    /// A leaf reads committed quantities without becoming an accessibility
    /// ancestor of production controls. It changes neither state nor geometry.
    @ViewBuilder
    func qaNavalSevenAuditMarker() -> some View {
        if QALaunchFlag.navalSevenPosition.isSet {
            let state = viewModel.state
            let owner = viewModel.humanPlayer
            let bank = state.bank.values.reduce(0, +)
            let resources = state.players[owner.index].resources.values.reduce(0, +)
            let quantities = "bank=\(bank);resources=\(resources);human=\(owner.index);"
                + "threshold=\(state.rules.discardThreshold);phase=\(state.phase)"
            Color.white.opacity(0.001)
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("qa.naval-seven.state")
                .accessibilityLabel("Committed Naval seven QA quantities")
                .accessibilityValue(quantities)
                .accessibilityRespondsToUserInteraction(false)
                .allowsHitTesting(false)
        }
    }
}
#endif
