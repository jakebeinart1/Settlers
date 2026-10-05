import CatanEngine
import Foundation

/// Export views receive only a public projection. Removing private data here,
/// before rendering, prevents a future board decoration from revealing a hand.
/// This state is for drawing only and must never be applied to a live session.
struct ReplayExportFrame: Sendable {
    let boardState: GameState
    let identities: [PlayerIdentity]
    let publicScores: [Int]
    let caption: String
    let position: Int
    let status: String
    let isPartial: Bool
    let reconstructionLabel: String

    func identity(for seat: PlayerID) -> PlayerIdentity { identities[seat.index] }
}

struct ReplayExportPresentation: Sendable {
    let identities: [PlayerIdentity]
    private let captionRoster: GameLogStore.SeatRoster

    init(roster: GameLogStore.SeatRoster, players: [Player], includeNames: Bool) {
        identities = players.map { player in
            let genericName = "Player \(player.id.index + 1)"
            let recordedName = roster.displayName(for: player.id).trimmingCharacters(in: .whitespacesAndNewlines)
            return PlayerIdentity(seat: player.id,
                                  displayName: includeNames && !recordedName.isEmpty ? recordedName : genericName,
                                  civilization: roster.civilization(for: player.id)
                                    ?? Civilization.allCases[player.id.index % Civilization.allCases.count],
                                  controller: roster.humanSeats.contains(player.id) ? .human : .computer)
        }
        // The narrator resolves every name from this stripped roster. Ghost
        // profile names/ids and archived human names cannot slip into prose.
        captionRoster = GameLogStore.SeatRoster(
            humanSeats: Set(players.map(\.id)),
            humanNames: Dictionary(uniqueKeysWithValues: identities.map { ($0.seat.index, $0.displayName) }),
            botPersonalities: [:], civilizations: [:])
    }

    func caption(events: [GameEvent], entry: GameLogEvent) -> String {
        GameReplayNarrator.headline(for: events.map(Self.publicEvent), move: entry.move,
                                   actor: entry.player, roster: captionRoster)
    }

    func frame(state: GameState, position: Int, caption: String, analysis: ReplayExportAnalysis) -> ReplayExportFrame {
        ReplayExportFrame(boardState: Self.publicBoard(state), identities: identities,
                          publicScores: state.players.map { state.publicVictoryPoints(for: $0.id) },
                          caption: caption, position: position, status: analysis.status, isPartial: analysis.isPartial,
                          reconstructionLabel: analysis.reconstructionLabel)
    }

    /// Exhaustive allowlist: a new event requires a privacy decision here.
    /// Even the thief and victim's stolen resource is private to the movie.
    private static func publicEvent(_ event: GameEvent) -> GameEvent {
        switch event {
        case .movedRobber(let actor, let victim, _): return .movedRobber(actor, from: victim, stealing: nil)
        case .playedKnight(let actor, let victim, _): return .playedKnight(actor, from: victim, stealing: nil)
        case .placedInitialSettlement, .placedInitialRoad, .rolled, .discarded,
             .builtRoad, .builtSettlement, .builtCity, .boughtDevCard, .boughtArmyCard,
             .deployedArmy, .playedRoadBuilding, .playedYearOfPlenty, .playedMonopoly,
             .tradedWithBank, .proposedTrade, .acceptedTrade, .rejectedTrade, .endedTurn, .gameWon:
            return event
        }
    }

    private static func publicBoard(_ state: GameState) -> GameState {
        let players = state.players.map { player in
            Player(id: player.id, playedKnights: player.playedKnights, settlements: player.settlements,
                   cities: player.cities, roads: player.roads)
        }
        return GameState(board: state.board, players: players, phase: .mainTurn(playerIndex: 0),
                         bank: [:], devCardDeck: [], lastDiceRoll: state.lastDiceRoll,
                         longestRoadPlayer: state.longestRoadPlayer, largestArmyPlayer: state.largestArmyPlayer,
                         rng: RandomSource(seed: 0), mode: state.mode, victoryPointTarget: state.victoryPointTarget,
                         variant: state.variant, garrisons: state.garrisons)
    }
}
