import CatanAI
import CatanEngine
import Foundation

/// `ghost candidates`: every option a seated ghost weighs at each of the
/// person's decisions, with Expert's score, for studying what predicts the
/// person's choice. The pre-roll choice is included: rolling scores as the
/// position as it stands, since the dice are not the seat's to pick.
private struct DumpLine: Encodable {
    struct Option: Encodable {
        let move: GameMove
        let expert: Double
    }
    let game: String
    let seat: PlayerID
    let state: GameState
    let situations: [GhostFidelity.Situation]
    let person: GameMove
    let options: [Option]
}

func dumpCandidates(_ games: [LoggedGame], to path: String) throws {
    let ghost = GhostPolicy(person: .anchored(at: anchor), lambda: 0)
    var data = Data()
    for game in games {
        try GhostFidelity.forEachDecision(in: game) { observation, ledger, move in
            var options = ghost.expertOptions(observation, ledger: ledger).map { DumpLine.Option(move: $0.move, expert: $0.score) }
            if observation.legalMoves.contains(.rollDice) {
                let still = PositionEvaluator(seat: observation.seat, weights: anchor).evaluate(observation.state, ledger: ledger)
                options.insert(.init(move: .rollDice, expert: still), at: 0)
            }
            let line = DumpLine(game: game.id, seat: observation.seat, state: observation.state,
                                situations: GhostFidelity.situations(observation.state, legal: observation.legalMoves),
                                person: move, options: options)
            data.append(try JSONEncoder().encode(line))
            data.append(0x0A)
        }
    }
    try data.write(to: URL(fileURLWithPath: path))
}
