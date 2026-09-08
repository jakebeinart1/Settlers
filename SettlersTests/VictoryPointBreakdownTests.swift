import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

/// The breakdown card makes a claim of arithmetic - "this is where those ten
/// points came from" - about a number the engine computes somewhere else. The
/// first test is the one that matters: it holds the two together.
@Suite struct VictoryPointBreakdownTests {
    /// The drift guard. `GameState` warns that a second victory-point formula
    /// in a view is a formula that diverges from the engine's; this asserts
    /// the description adds up to the engine's total at every position of a
    /// real game, so a new source of points (or a changed value for an old
    /// one) fails here instead of shipping a card whose rows sum to eight
    /// under a heading that says ten.
    @Test func everyLineTogetherAccountsForTheEnginesTotal() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 41)

        for _ in 0..<120 {
            for player in state.players {
                let breakdown = VictoryPointBreakdown(seat: player.id, state: state)
                #expect(breakdown.lines.reduce(0) { $0 + $1.points } == breakdown.total)
                #expect(breakdown.total == state.victoryPoints(for: player.id))
            }
            guard let seat = state.phase.awaitingSeatIndex.map({ PlayerID(index: $0) }),
                  let move = RulesEngine.legalMoves(for: state, seat: seat).first else { break }
            try RulesEngine.apply(move, by: seat, to: &state)
        }
    }

    /// The card draws one row per source whether or not it scores. A row that
    /// appeared the moment a player bought their first victory card would
    /// resize the card under a scrubbing finger.
    @Test func allFiveSourcesArePresentEvenOnAnEmptyOpeningPosition() {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)

        let breakdown = VictoryPointBreakdown(seat: PlayerID(index: 0), state: state)

        #expect(breakdown.lines.map(\.source) == VictoryPointBreakdown.Source.allCases)
        #expect(breakdown.total == 0)
        #expect(breakdown.lines.allSatisfy { !$0.isScoring })
    }

    @Test func buildingsScoreOnePerSettlementAndTwoPerCity() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        let vertices = state.board.onBoardVertices.sorted()
        state.players[0].settlements = Set(vertices.prefix(3))
        state.players[0].cities = Set(vertices.suffix(2))

        let breakdown = VictoryPointBreakdown(seat: PlayerID(index: 0), state: state)

        #expect(try line(breakdown, .settlements).points == 3)
        #expect(try line(breakdown, .cities).quantity == 2)
        #expect(try line(breakdown, .cities).points == 4)
        #expect(breakdown.total == 7)
    }

    /// A recording is a finished game, so the victory-point cards an opponent
    /// never revealed are shown here - they are exactly the points the board
    /// cannot explain, which is what the card exists for.
    @Test func heldVictoryPointCardsAreCountedAndNotHidden() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.players[2].devCards = [.victoryPoint, .knight, .victoryPoint]

        let breakdown = VictoryPointBreakdown(seat: PlayerID(index: 2), state: state)

        #expect(try line(breakdown, .victoryCards).quantity == 2)
        #expect(try line(breakdown, .victoryCards).points == 2)
        #expect(breakdown.total == 2)
    }

    @Test func eachBonusIsWorthTwoPointsOnlyToTheSeatHoldingIt() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.players[1].playedKnights = 3
        state.longestRoadPlayer = PlayerID(index: 1)
        state.largestArmyPlayer = PlayerID(index: 1)

        let holder = VictoryPointBreakdown(seat: PlayerID(index: 1), state: state)
        let other = VictoryPointBreakdown(seat: PlayerID(index: 0), state: state)

        #expect(holder.total == 4)
        #expect(holder.holds(.longestRoad))
        #expect(holder.holds(.largestArmy))
        #expect(try line(holder, .largestArmy).quantity == 3)
        #expect(!other.holds(.longestRoad))
        #expect(try line(other, .longestRoad).points == 0)
    }

    /// The number beside "Longest road" is the longest continuous stretch the
    /// bonus is judged on, not the pile of segments built. Two disconnected
    /// roads are two segments and a stretch of one.
    @Test func longestRoadCountsTheStretchAndNotTheSegments() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        let edges = state.board.onBoardEdges.sorted()
        let first = try #require(edges.first)
        let apart = try #require(edges.first { $0.a != first.a && $0.a != first.b
            && $0.b != first.a && $0.b != first.b })
        state.players[0].roads = [first, apart]

        let breakdown = VictoryPointBreakdown(seat: PlayerID(index: 0), state: state)

        #expect(state.players[0].roads.count == 2)
        #expect(try line(breakdown, .longestRoad).quantity == 1)
        #expect(try line(breakdown, .longestRoad).points == 0)
    }

    private func line(_ breakdown: VictoryPointBreakdown,
                      _ source: VictoryPointBreakdown.Source) throws -> VictoryPointBreakdown.Line {
        try #require(breakdown.lines.first { $0.source == source })
    }
}
