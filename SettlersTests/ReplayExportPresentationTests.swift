import CatanEngine
import Foundation
import Testing
@testable import Settlers

@Suite struct ReplayExportPresentationTests {
    @Test func publicProjectionCannotCarryPrivateHandsDecksOrRandomness() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42)
        state.players[0].resources = [.ore: 7, .wool: 2]
        state.players[0].devCards = [.victoryPoint, .monopoly]
        state.devCardsBoughtThisTurn = [PlayerID(index: 0): [.monopoly]]
        state.variant = .conquest
        state.armyHands = [PlayerID(index: 1): [5, 4]]
        state.armyDeck = [5, 3, 1]
        let detail = ReplayExportFixtures.detail(initial: state)
        var sequence = try ReplayExportSequence(detail: detail)

        let frame = try #require(try sequence.next())

        #expect(frame.boardState.board == state.board)
        #expect(frame.boardState.players.allSatisfy { $0.resources.isEmpty && $0.devCards.isEmpty })
        #expect(frame.boardState.devCardDeck.isEmpty)
        #expect(frame.boardState.armyDeck.isEmpty)
        #expect(frame.boardState.armyHands.isEmpty)
        #expect(frame.boardState.devCardsBoughtThisTurn.isEmpty)
        #expect(frame.boardState.pendingTradeOffers.isEmpty)
        #expect(frame.boardState.rng == RandomSource(seed: 0))
        #expect(frame.publicScores[0] == state.publicVictoryPoints(for: PlayerID(index: 0)))
        #expect(frame.publicScores[0] < state.victoryPoints(for: PlayerID(index: 0)))
        #expect(frame.identities.map(\.displayName) == ["Player 1", "Player 2", "Player 3", "Player 4"])
        #expect(detail.initialState == state, "Projection must not redact the replay source itself")
    }

    @Test func namesRequireExplicitOptInAndNeverComeFromCurrentAssignment() throws {
        let detail = try ReplayExportFixtures.recording()
        let anonymous = ReplayExportPresentation(roster: detail.roster, players: detail.initialState.players, includeNames: false)
        let named = ReplayExportPresentation(roster: detail.roster, players: detail.initialState.players, includeNames: true)

        #expect(anonymous.identities[0].displayName == "Player 1")
        #expect(anonymous.identities[1].displayName == "Player 2")
        #expect(named.identities[0].displayName == "PRIVATE_NAME_0")
        #expect(named.identities[1].displayName == "PRIVATE_NAME_1")
    }

    @Test func thiefAndVictimResourcesAreRedactedFromEveryMovieCaption() throws {
        let detail = try ReplayExportFixtures.recording()
        let presentation = ReplayExportPresentation(roster: detail.roster, players: detail.initialState.players, includeNames: false)
        let actor = PlayerID(index: 0)
        let victim = PlayerID(index: 1)
        let entry = GameLogEvent(timestamp: Date(), player: actor,
                                 move: .moveRobber(HexCoordinate(q: 0, r: 0), stealFrom: victim))
        let events: [GameEvent] = [.movedRobber(actor, from: victim, stealing: .wool),
                                   .playedKnight(actor, from: victim, stealing: .ore)]

        let caption = presentation.caption(events: events, entry: entry)

        #expect(caption.contains("Player 1"))
        #expect(caption.contains("Player 2"))
        #expect(!caption.contains("wool"))
        #expect(!caption.contains("ore"))
        #expect(!caption.contains("PRIVATE_"))
    }

    @Test func publicBoardPiecesAndConquestGarrisonsSurviveProjection() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 43)
        let hex = try #require(state.board.tiles.first?.coordinate)
        let vertex = try #require(state.board.onBoardVertices.sorted().first)
        let edge = try #require(state.board.onBoardEdges.sorted().first)
        state.players[0].cities.insert(vertex)
        state.players[0].roads.insert(edge)
        state.variant = .conquest
        state.garrisons[hex] = Garrison(owner: PlayerID(index: 0), strength: 3)
        var sequence = try ReplayExportSequence(detail: ReplayExportFixtures.detail(initial: state))

        let frame = try #require(try sequence.next())

        #expect(frame.boardState.garrisons == state.garrisons)
        #expect(frame.boardState.players[0].cities == state.players[0].cities)
        #expect(frame.boardState.players[0].roads == state.players[0].roads)
        #expect(frame.publicScores[0] == state.publicVictoryPoints(for: PlayerID(index: 0)))
    }
}
