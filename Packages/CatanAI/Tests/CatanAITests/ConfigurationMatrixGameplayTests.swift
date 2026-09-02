import CatanEngine
import Testing
@testable import CatanAI

/// Completion and legality coverage for every rules configuration exposed by
/// the New Game screen without depending on its app-layer seat metadata.
///
/// Two seeds per cell keep the routine suite bounded while ensuring each board
/// mode is exercised with different engine and policy random streams. Standard
/// boards keep their fixed terrain but still vary dice, development cards,
/// robber steals, and policy tie-breaks with the seed.
@Test(arguments: MatrixGame.cases)
private func everySupportedRulesConfigurationCompletesWithOnlyLegalMoves(game: MatrixGame) throws {
    try game.playToCompletion()
}

private enum MatrixBoardMode: String, CaseIterable {
    case standard
    case randomized

    func board(seed: UInt64) -> Board {
        switch self {
        case .standard: BoardGenerator.standard()
        case .randomized: BoardGenerator.randomized(seed: seed)
        }
    }
}

private struct MatrixGame {
    static let seeds: [UInt64] = [211, 977]
    static let moveLimit = 3_000
    static let cases = GameSetup.supportedPlayerCounts.flatMap { playerCount in
        [8, 10, 12].flatMap { target in
            MatrixBoardMode.allCases.flatMap { boardMode in
                seeds.map { seed in
                    MatrixGame(playerCount: playerCount, target: target,
                               boardMode: boardMode, seed: seed)
                }
            }
        }
    }

    let playerCount: Int
    let target: Int
    let boardMode: MatrixBoardMode
    let seed: UInt64

    private var label: String {
        "\(playerCount) seats, \(target) VP, \(boardMode.rawValue), seed \(seed)"
    }

    func playToCompletion() throws {
        var session = makeSession()
        var moves = 0

        while case .seat = session.nextActor(), moves < Self.moveLimit {
            guard let decision = session.decideNext() else {
                Issue.record("\(label): expected a policy decision")
                return
            }
            // `commit` is the authority on legality. A queued live-trade
            // response is intentionally narrower than the active seat's full
            // phase list, so recomputing `RulesEngine.legalMoves` here asks a
            // different question and falsely labels that response illegal.
            _ = try session.commit(seat: decision.seat, move: decision.move)
            moves += 1
        }

        guard case .gameOver(let winner) = session.nextActor() else {
            Issue.record("\(label): did not finish within \(Self.moveLimit) moves")
            return
        }
        #expect(winner.index < playerCount, "\(label): winner names a seat that does not exist")
        #expect(session.state.victoryPoints(for: winner) >= target,
                "\(label): winner finished below the configured target")
        assertResourceLedgerIsNonnegative(session.state)
    }

    private func makeSession() -> GameSession {
        let state = GameSetup.newGame(board: boardMode.board(seed: seed),
                                      seed: seed,
                                      playerCount: playerCount,
                                      victoryPointTarget: target)
        let personalities: [BotPersonality] = [.balanced, .aggressive, .cautious, .balanced]
        let policies = Dictionary(uniqueKeysWithValues: state.players.map { player in
            let personality = personalities[player.id.index]
            return (player.id, HeuristicPolicy(personality: personality,
                                               id: "matrix-\(personality)"))
        })
        return GameSession(state: state, policies: policies, policySeed: seed &* 31 &+ 7)
    }

    private func assertResourceLedgerIsNonnegative(_ state: GameState) {
        for player in state.players {
            for amount in player.resources.values {
                #expect(amount >= 0, "\(label): player \(player.id.index) has a negative resource count")
            }
        }
        for amount in state.bank.values {
            #expect(amount >= 0, "\(label): bank has a negative resource count")
        }
    }
}
