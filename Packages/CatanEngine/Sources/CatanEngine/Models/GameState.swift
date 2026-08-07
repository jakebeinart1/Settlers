public struct GameState: Codable, Sendable {
    public var board: Board
    public var players: [Player]
    public var phase: GamePhase
    public var bank: [Resource: Int]
    public var devCardDeck: [DevCardType]
    public var lastDiceRoll: Int?
    public var longestRoadPlayer: PlayerID?
    public var largestArmyPlayer: PlayerID?
    public var pendingTradeOffers: [TradeOffer]
    public var log: [String]

    public init(
        board: Board,
        players: [Player],
        phase: GamePhase,
        bank: [Resource: Int],
        devCardDeck: [DevCardType],
        lastDiceRoll: Int? = nil,
        longestRoadPlayer: PlayerID? = nil,
        largestArmyPlayer: PlayerID? = nil,
        pendingTradeOffers: [TradeOffer] = [],
        log: [String] = []
    ) {
        self.board = board
        self.players = players
        self.phase = phase
        self.bank = bank
        self.devCardDeck = devCardDeck
        self.lastDiceRoll = lastDiceRoll
        self.longestRoadPlayer = longestRoadPlayer
        self.largestArmyPlayer = largestArmyPlayer
        self.pendingTradeOffers = pendingTradeOffers
        self.log = log
    }

    /// Total victory points for `id`: building/dev-card VPs from `Player`,
    /// plus the +2 longest-road/largest-army bonuses tracked here since they
    /// depend on cross-player comparison.
    public func victoryPoints(for id: PlayerID) -> Int {
        guard let player = players.first(where: { $0.id == id }) else { return 0 }
        var total = player.victoryPoints
        if longestRoadPlayer == id { total += 2 }
        if largestArmyPlayer == id { total += 2 }
        return total
    }
}

public enum GameSetup {
    /// Creates a fresh 4-player game (human at index 0, bots at 1-3) on
    /// `board`, with a full standard bank and dev card deck, ready to begin
    /// the setup phase at player 0's first placement.
    public static func newGame(board: Board) -> GameState {
        let players = (0..<4).map { Player(id: PlayerID(index: $0)) }

        var bank: [Resource: Int] = [:]
        for resource in Resource.allCases {
            bank[resource] = 19
        }

        var devCardDeck: [DevCardType] = []
        devCardDeck.append(contentsOf: repeatElement(.knight, count: 14))
        devCardDeck.append(contentsOf: repeatElement(.victoryPoint, count: 5))
        devCardDeck.append(contentsOf: repeatElement(.roadBuilding, count: 2))
        devCardDeck.append(contentsOf: repeatElement(.yearOfPlenty, count: 2))
        devCardDeck.append(contentsOf: repeatElement(.monopoly, count: 2))

        return GameState(
            board: board,
            players: players,
            phase: .setupForward(playerIndex: 0),
            bank: bank,
            devCardDeck: devCardDeck
        )
    }
}
