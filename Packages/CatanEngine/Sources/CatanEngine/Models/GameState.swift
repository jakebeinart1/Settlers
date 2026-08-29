public struct GameState: Codable, Sendable {
    /// Wire-format version of a persisted state. Bump this whenever a change
    /// to the stored shape needs `init(from:)` below to do something other
    /// than fall back to a default, and branch on it there. Saves written
    /// before versioning existed decode as `0`.
    public static let currentSchemaVersion = 1

    /// The schema version this value was decoded from (or
    /// `currentSchemaVersion` for a freshly created game). Persisted so a
    /// future decoder can tell what it is looking at instead of guessing.
    public var schemaVersion: Int

    /// Seeded generator for every random outcome the rules produce - dice
    /// rolls and robber steals. Stored here rather than passed in so that a
    /// resumed save continues the same sequence and a recorded move list
    /// replays exactly. See `RandomSource`.
    public var rng: RandomSource

    public var board: Board
    public var players: [Player]
    public var phase: GamePhase
    public var bank: [Resource: Int]
    public var devCardDeck: [DevCardType]
    public var lastDiceRoll: Int?
    public var longestRoadPlayer: PlayerID?
    public var largestArmyPlayer: PlayerID?
    public var pendingTradeOffers: [TradeOffer]
    // NOTE: `log: [String]` used to live here. It was removed - see `GameEvent`.
    // It grew about one entry per move (roughly six thousand by the end of a
    // long game) inside a value type that search, simulation and every save
    // copy wholesale, and nothing in the engine ever read it back.
    /// The index of the player who rolled a 7, carried across an intervening
    /// `.discarding` phase so `.movingRobber(playerIndex:)` names the roller
    /// (not whichever player happened to discard last). `nil` outside that
    /// 7-roll sequence.
    public var robberMoverIndex: Int?
    /// Dev cards each player has bought during the *current* turn, keyed by
    /// owner. A card counted here cannot yet be played (standard rule: a
    /// card is only playable starting the turn after it's bought). Cleared
    /// for everyone on `.endTurn`.
    public var devCardsBoughtThisTurn: [PlayerID: [DevCardType]]
    /// The player who has already played a development card this turn, if
    /// any - standard rule: at most one development card may be played per
    /// turn (a knight played before rolling, in `.rollDice`, counts against
    /// the same turn's limit). `nil` once no card has been played yet this
    /// turn; cleared for everyone on `.endTurn`.
    public var devCardPlayedThisTurn: PlayerID?
    /// How many trades each proposer has had *accepted* (by anyone) since
    /// the current turn began, keyed by proposer. Lets trade evaluation
    /// notice a proposer who's already landed one deal this turn and is now
    /// shopping around for more - real players get suspicious of a partner
    /// who keeps coming back, bots previously had no way to. Cleared for
    /// everyone on `.endTurn`, same as `devCardsBoughtThisTurn`.
    public var tradesAcceptedThisTurn: [PlayerID: Int]

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
        robberMoverIndex: Int? = nil,
        devCardsBoughtThisTurn: [PlayerID: [DevCardType]] = [:],
        devCardPlayedThisTurn: PlayerID? = nil,
        tradesAcceptedThisTurn: [PlayerID: Int] = [:],
        rng: RandomSource = RandomSource(seed: UInt64.random(in: .min ... .max)),
        schemaVersion: Int = GameState.currentSchemaVersion
    ) {
        self.rng = rng
        self.schemaVersion = schemaVersion
        self.board = board
        self.players = players
        self.phase = phase
        self.bank = bank
        self.devCardDeck = devCardDeck
        self.lastDiceRoll = lastDiceRoll
        self.longestRoadPlayer = longestRoadPlayer
        self.largestArmyPlayer = largestArmyPlayer
        self.pendingTradeOffers = pendingTradeOffers
        self.robberMoverIndex = robberMoverIndex
        self.devCardsBoughtThisTurn = devCardsBoughtThisTurn
        self.devCardPlayedThisTurn = devCardPlayedThisTurn
        self.tradesAcceptedThisTurn = tradesAcceptedThisTurn
    }

    /// Decodes a saved game, tolerating fields that a *older* save predates.
    ///
    /// ## Why this is hand-written rather than synthesized
    /// Swift's synthesized `init(from:)` calls `decode` (not
    /// `decodeIfPresent`) for every non-optional property, so a save written
    /// before a property existed fails to decode entirely. `GameStore.load()`
    /// swallows that with `try?` and returns `nil`, and the app then starts a
    /// brand-new game with no message - i.e. **adding one field to this
    /// struct silently deleted every player's in-progress game.** That had
    /// already happened once in the field, when `tradesAcceptedThisTurn` was
    /// added.
    ///
    /// Every property that a game can meaningfully resume without is read
    /// with `decodeIfPresent` and a default, so adding the *next* field is a
    /// one-line change here instead of a data-loss event. Only `board`,
    /// `players` and `phase` are genuinely required: a save missing any of
    /// those describes no recoverable game, so it throws and the caller can
    /// report a corrupt save rather than pretending there was none.
    ///
    /// `encode(to:)` is deliberately left synthesized - it always writes the
    /// current shape, so only the read side needs to be permissive.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        board = try container.decode(Board.self, forKey: .board)
        players = try container.decode([Player].self, forKey: .players)
        phase = try container.decode(GamePhase.self, forKey: .phase)

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        // A pre-v1 save carries no generator. Seeding a fresh one keeps the
        // resumed game playable; it cannot make that game replayable, because
        // the moves already applied were rolled off the old global RNG.
        rng = try container.decodeIfPresent(RandomSource.self, forKey: .rng)
            ?? RandomSource(seed: UInt64.random(in: .min ... .max))

        bank = try container.decodeIfPresent([Resource: Int].self, forKey: .bank) ?? [:]
        devCardDeck = try container.decodeIfPresent([DevCardType].self, forKey: .devCardDeck) ?? []
        lastDiceRoll = try container.decodeIfPresent(Int.self, forKey: .lastDiceRoll)
        longestRoadPlayer = try container.decodeIfPresent(PlayerID.self, forKey: .longestRoadPlayer)
        largestArmyPlayer = try container.decodeIfPresent(PlayerID.self, forKey: .largestArmyPlayer)
        pendingTradeOffers = try container.decodeIfPresent([TradeOffer].self, forKey: .pendingTradeOffers) ?? []
        robberMoverIndex = try container.decodeIfPresent(Int.self, forKey: .robberMoverIndex)
        devCardsBoughtThisTurn = try container
            .decodeIfPresent([PlayerID: [DevCardType]].self, forKey: .devCardsBoughtThisTurn) ?? [:]
        devCardPlayedThisTurn = try container.decodeIfPresent(PlayerID.self, forKey: .devCardPlayedThisTurn)
        tradesAcceptedThisTurn = try container
            .decodeIfPresent([PlayerID: Int].self, forKey: .tradesAcceptedThisTurn) ?? [:]
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
    /// `board`, with a full standard bank and a shuffled dev card deck,
    /// ready to begin the setup phase at player 0's first placement. Uses
    /// the system RNG; see the `rng:` overload below for deterministic
    /// (e.g. test) callers.
    public static func newGame(board: Board) -> GameState {
        var rng = SystemRandomNumberGenerator()
        return newGame(board: board, rng: &rng)
    }

    /// Creates a fully reproducible game: `seed` fixes both the dev card
    /// shuffle and every dice roll and robber steal the game will go on to
    /// produce. Two calls with the same board and seed, played by the same
    /// policies, yield an identical move sequence - which is what makes
    /// headless self-play, A/B comparison of bot changes, and bisecting a
    /// failing simulation possible at all.
    public static func newGame(board: Board, seed: UInt64) -> GameState {
        var rng = RandomSource(seed: seed)
        return newGame(board: board, rng: &rng)
    }

    /// Same as `newGame(board:)` but with an injectable RNG, so the dev card
    /// shuffle can be made deterministic (e.g. for tests). The in-game
    /// generator is seeded *from* `rng`, so a deterministic caller gets a
    /// deterministic game and not merely a deterministic opening deck.
    public static func newGame(board: Board, rng: inout some RandomNumberGenerator) -> GameState {
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
        devCardDeck.shuffle(using: &rng)

        return GameState(
            board: board,
            players: players,
            phase: .setupForward(playerIndex: 0),
            bank: bank,
            devCardDeck: devCardDeck,
            rng: RandomSource(seed: rng.next())
        )
    }
}
