import CatanAI
import CatanEngine
import Foundation

/// `ghost shoes`: Expert in the person's shoes. At every choice the person
/// made where today's Expert would have done something else, play the game
/// out `rollouts` times from each of the two moves, every seat Expert from
/// there on, and count how often the person's seat wins.
///
/// Both branches share each rollout's dice and dev-card order (the same
/// reseed), so the difference is the move, not the luck. The deck is
/// reshuffled per rollout because the order the replay holds is the real
/// future, which neither the person nor Expert could see.
///
/// What it measures: the person's move followed by Expert play, against
/// Expert's move followed by Expert play. A move that only pays off inside
/// the person's own plan (a trade they meant to finish next) is undersold.
struct ShoesRecord: Encodable {
    let game: String
    let index: Int
    let rolls: Int
    let publicVP: Int
    let situations: [GhostFidelity.Situation]
    let person: String
    let expert: String
    let personKind: String
    let expertKind: String
    let personWins: Int
    let expertWins: Int
    let rollouts: Int
}

func shoes(_ game: LoggedGame, rollouts: Int, expert: ExpertRevision) throws -> [ShoesRecord] {
    let policy = expert.policy
    var experts: [PlayerID: any Policy] = [:]
    for player in game.initialState.players { experts[player.id] = policy }
    var records: [ShoesRecord] = []
    var session = GameSession(state: game.initialState, policies: [:], policySeed: 0)
    var rolls = 0
    for (index, event) in game.events.enumerated() {
        if event.isHumanDecision, game.humanSeats.contains(event.player) {
            let legal = DecisionExtractor.options(for: event, in: session.state, humanTrading: false)
            if legal.count > 1 {
                var rng = RandomSource(seed: 0)
                let observation = GameObservation(seat: event.player, state: session.state, legalMoves: legal)
                let choice = policy.decide(observation, ledger: session.ledger(for: event.player), rng: &rng)
                if !GhostFidelity.matches(choice, event.move) {
                    let record: ShoesRecord = try autoreleasepoolIfAvailable {
                        var personWins = 0, expertWins = 0
                        for rollout in 0..<rollouts {
                            let seed = UInt64(index) &* 1_000_003 &+ UInt64(rollout)
                            if try playOut(session, first: event.move, seat: event.player, seed: seed, policies: experts) {
                                personWins += 1
                            }
                            if try playOut(session, first: choice, seat: event.player, seed: seed, policies: experts) {
                                expertWins += 1
                            }
                        }
                        return ShoesRecord(
                            game: game.id, index: index, rolls: rolls,
                            publicVP: session.state.publicVictoryPoints(for: event.player),
                            situations: GhostFidelity.situations(session.state, legal: legal),
                            person: String(describing: event.move), expert: String(describing: choice),
                            personKind: GhostFidelity.kind(event.move), expertKind: GhostFidelity.kind(choice),
                            personWins: personWins, expertWins: expertWins, rollouts: rollouts)
                    }
                    records.append(record)
                }
            }
        }
        if event.move == .rollDice { rolls += 1 }
        _ = try session.applyExternal(event.move, by: event.player)
    }
    return records
}

/// `first` by `seat`, then `policies` to the end; did `seat` win?
func playOut(_ from: GameSession, first: GameMove, seat: PlayerID, seed: UInt64,
             policies: [PlayerID: any Policy]) throws -> Bool {
    var session = try reseeded(from, seed: seed)
    _ = try session.applyExternal(first, by: seat)
    session.policies = policies
    var moves = 0
    while moves < 3000, try session.step() != nil { moves += 1 }
    if case .gameOver(let winner) = session.state.phase { return winner == seat }
    return false
}

/// The same session, ledgers and all, with fresh dice and a reshuffled deck.
/// `Checkpoint.state` is read-only, so the state is swapped through its JSON.
func reseeded(_ session: GameSession, seed: UInt64) throws -> GameSession {
    var state = session.state
    var rng = RandomSource(seed: seed)
    state.devCardDeck.shuffle(using: &rng)
    state.rng = RandomSource(seed: rng.next())
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.checkpoint)) as? [String: Any] ?? [:]
    json["state"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
    let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self,
                                              from: JSONSerialization.data(withJSONObject: json))
    return try GameSession(checkpoint: checkpoint, policies: session.policies)
}
