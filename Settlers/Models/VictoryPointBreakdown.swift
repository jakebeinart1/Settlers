import Foundation
import CatanEngine

/// Where one seat's victory points came from, at one position.
///
/// The replay's score strip answers "who is winning"; this answers the
/// question that actually follows it - a player holding six things on the
/// board and showing ten points has four points that are not visible
/// anywhere, and until you can name them the score reads as a mistake.
///
/// ## The total is the engine's, never a sum of these lines
/// `total` is `GameState.victoryPoints(for:)` verbatim. The lines are a
/// *description* of that number, not a second way to compute it - `GameState`
/// is explicit (see `publicVictoryPoints`'s doc comment) that a second
/// victory-point formula living in a view is a formula that drifts from the
/// engine's. `VictoryPointBreakdownTests` asserts the lines add up to `total`
/// across a whole replayed game, so a rules change that adds a new source of
/// points fails a test here rather than silently showing "10 VP" over lines
/// that add to eight.
///
/// ## Why hidden cards are shown at all
/// A live opponent's victory-point cards are hidden information and the HUD
/// is careful about it. A recording is a finished game: there is nothing left
/// to conceal, and hiding the cards would leave exactly the unexplained gap
/// this type exists to close.
struct VictoryPointBreakdown: Equatable {
    /// Every applicable source is present even at zero, so the card has one
    /// shape for every seat at every frame of a scrub in the same mode.
    enum Source: String, CaseIterable {
        case settlements, cities, victoryCards, longestRoad, largestArmy, colonies
    }

    struct Line: Identifiable, Equatable {
        let source: Source
        let icon: String
        let label: String
        /// What there is: settlements built, road length, knights played.
        /// Not the same as `points` - a five-long road that lost the bonus
        /// to a six-long one is still worth showing as the near miss it is.
        let quantity: Int
        let points: Int

        var id: String { source.rawValue }
        var isScoring: Bool { points > 0 }
    }

    let seat: PlayerID
    let total: Int
    let lines: [Line]

    private static let settlementPoints = 1
    private static let cityPoints = 2
    private static let victoryCardPoints = 1

    init(seat: PlayerID, state: GameState) {
        self.seat = seat
        total = state.victoryPoints(for: seat)

        guard let player = state.players.first(where: { $0.id == seat }) else {
            lines = []
            return
        }
        let cards = player.devCards.filter { $0 == .victoryPoint }.count
        let holdsRoad = state.longestRoadPlayer == seat
        let holdsArmy = state.largestArmyPlayer == seat

        var sources = [
            Line(source: .settlements, icon: "house.fill", label: "Settlements",
                 quantity: player.settlements.count,
                 points: player.settlements.count * Self.settlementPoints),
            Line(source: .cities, icon: "building.2.fill", label: "Cities",
                 quantity: player.cities.count,
                 points: player.cities.count * Self.cityPoints),
            Line(source: .victoryCards, icon: "sparkles.rectangle.stack.fill", label: "Victory cards",
                 quantity: cards, points: cards * Self.victoryCardPoints),
            // The quantity here is the longest continuous stretch the bonus is
            // judged on, not the number of segments built - a forked network
            // can hold far more roads than its longest run, and printing that
            // larger number next to "Longest Road: no" reads as a bug.
            Line(source: .longestRoad, icon: "road.lanes", label: "Longest road",
                 quantity: LongestRoad.length(for: player, in: state),
                 points: holdsRoad ? state.rules.longestRoadBonus : 0),
            Line(source: .largestArmy, icon: "shield.fill", label: "Largest army",
                 quantity: player.playedKnights,
                 points: holdsArmy ? state.rules.largestArmyBonus : 0)
        ]
        if state.mode == .naval {
            let colonyPoints = Naval.colonyPoints(for: seat, in: state)
            sources.append(Line(source: .colonies, icon: "flag.fill", label: "Overseas colonies",
                                quantity: colonyPoints, points: colonyPoints))
        }
        lines = sources
    }

    /// True while this seat holds the bonus, for the two badges the score
    /// strip shows without needing the card open.
    func holds(_ source: Source) -> Bool {
        lines.first { $0.source == source }?.isScoring ?? false
    }
}
