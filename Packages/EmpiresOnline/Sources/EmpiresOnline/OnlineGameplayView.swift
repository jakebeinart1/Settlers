import CatanEngine
import Foundation

/// A player as seen from one authenticated seat. Exact opponent holdings and
/// hidden victory cards have no place in this public projection.
public struct OnlineGameplayPlayer: Codable, Sendable, Identifiable {
    public let id: PlayerID
    public let settlements: Set<VertexID>
    public let cities: Set<VertexID>
    public let roads: Set<EdgeID>
    public let playedKnights: Int
    public let resourceCount: Int
    public let devCardCount: Int
    public let armyCardCount: Int
    public let victoryPoints: Int
    public let colonyPoints: Int

    init(player: Player, in state: GameState, viewer: PlayerID) {
        id = player.id
        settlements = player.settlements
        cities = player.cities
        roads = player.roads
        playedKnights = player.playedKnights
        resourceCount = player.resources.values.reduce(0, +)
        devCardCount = player.devCards.count
        armyCardCount = state.armyHands[player.id, default: []].count
        victoryPoints = player.id == viewer
            ? state.victoryPoints(for: player.id) : state.publicVictoryPoints(for: player.id)
        colonyPoints = Naval.colonyPoints(for: player.id, in: state)
    }
}

/// The sole gameplay snapshot sent over the network. Public ownership and
/// counts are stored separately from the viewing seat's cards and actions.
public struct OnlineGameplayView: Codable, Sendable {
    public let board: Board
    public let mode: GameMode
    public let rules: GameVariant
    public let phase: GamePhase
    public let players: [OnlineGameplayPlayer]
    public let viewer: PlayerID
    public let turnOwner: PlayerID?
    public let legalMoves: [GameMove]
    /// Wire-compatible draft limits for the viewer's legal bank receipts.
    /// The authority alone knows actual stock and validates the submitted bundle.
    public let bank: [Resource: Int]
    public let lastDiceRoll: Int?
    public let devCardDeckCount: Int
    public let armyDeckCount: Int
    public let ships: [Ship]
    public let garrisons: [HexCoordinate: Garrison]
    public let resources: [Resource: Int]
    public let devCards: [DevCardType]
    public let armyCards: [Int]
    public let armyPrice: ArmyPrice
    public let devCardsBoughtThisTurn: [DevCardType]
    public let devCardPlayedThisTurn: Bool
    public let discardCount: Int?
    public let harvestRemaining: Int?
    public let tradeOffer: TradeOffer?
    public let canProposeTrade: Bool
    public let victoryPointTarget: Int
    public let longestRoadPlayer: PlayerID?
    public let largestArmyPlayer: PlayerID?

    public var winner: PlayerID? {
        if case .gameOver(let winner) = phase { return winner }
        return nil
    }

    init(state: GameState, viewer: PlayerID, turnOwner: PlayerID?, legalMoves: [GameMove],
         discardCount: Int?, tradeOffer: TradeOffer?, canProposeTrade: Bool) {
        let privatePlayer = state.players[viewer.index]
        board = Naval.visibleBoard(in: state)
        mode = state.mode
        rules = state.variant
        phase = state.phase
        players = state.players.map { OnlineGameplayPlayer(player: $0, in: state, viewer: viewer) }
        self.viewer = viewer
        self.turnOwner = turnOwner
        self.legalMoves = legalMoves
        bank = Self.bankDraftLimits(for: legalMoves, ceiling: state.rules.bankPerResource)
        lastDiceRoll = state.lastDiceRoll
        devCardDeckCount = state.devCardDeck.count
        armyDeckCount = state.armyDeck.count
        ships = state.naval?.ships ?? []
        garrisons = state.garrisons
        resources = privatePlayer.resources
        devCards = privatePlayer.devCards
        armyCards = state.armyHands[viewer, default: []]
        armyPrice = state.armyPrice
        devCardsBoughtThisTurn = state.devCardsBoughtThisTurn[viewer, default: []]
        devCardPlayedThisTurn = state.devCardPlayedThisTurn == viewer
        self.discardCount = discardCount
        harvestRemaining = Naval.harvestProgress(for: viewer, in: state)?.remaining
        self.tradeOffer = tradeOffer
        self.canProposeTrade = canProposeTrade
        victoryPointTarget = state.victoryPointTarget
        longestRoadPlayer = state.longestRoadPlayer
        largestArmyPlayer = state.largestArmyPlayer
    }

    private static func bankDraftLimits(for moves: [GameMove], ceiling: Int) -> [Resource: Int] {
        moves.reduce(into: [:]) { limits, move in
            guard case .bankTrade(_, let get) = move else { return }
            for resource in get.keys { limits[resource] = ceiling }
        }
    }

    /// Drawing-only input for the existing board renderer. Action availability
    /// comes from the service's legalMoves because this contains no hidden
    /// information and cannot be resumed or used to run the rules engine.
    public var boardPresentationState: GameState {
        GameState(board: board, players: presentationPlayers, phase: phase, bank: bank, devCardDeck: [],
                  lastDiceRoll: lastDiceRoll, longestRoadPlayer: longestRoadPlayer,
                  largestArmyPlayer: largestArmyPlayer, pendingTradeOffers: tradeOffer.map { [$0] } ?? [],
                  devCardsBoughtThisTurn: [viewer: devCardsBoughtThisTurn],
                  devCardPlayedThisTurn: devCardPlayedThisTurn ? viewer : nil,
                  rng: RandomSource(seed: 0), mode: mode, victoryPointTarget: victoryPointTarget,
                  variant: rules, garrisons: garrisons, armyHands: [viewer: armyCards],
                  armyPrice: armyPrice, naval: presentationNaval)
    }

    private var presentationPlayers: [Player] {
        players.map { player in
            Player(id: player.id, resources: player.id == viewer ? resources : [:],
                   devCards: player.id == viewer ? devCards : [], playedKnights: player.playedKnights,
                   settlements: player.settlements, cities: player.cities, roads: player.roads)
        }
    }

    private var presentationNaval: NavalState? {
        guard mode == .naval else { return nil }
        let visible = Set(board.tiles.lazy.filter { $0.kind != .fog }.map(\.coordinate))
        var naval = NavalState(revealed: visible, ships: ships)
        naval.colonyPoints = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.colonyPoints) })
        return naval
    }
}
