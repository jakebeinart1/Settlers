public struct GameState: Codable, Sendable, Equatable {
    /// Wire-format version of a persisted state. Bump this whenever a change
    /// to the stored shape needs `init(from:)` below to do something other
    /// than fall back to a default, and branch on it there. Saves written
    /// before versioning existed decode as `0`.
    /// Bumped to 3 when `declinedTradeOffersThisTurn` was added.
    /// Bumped to 4 when `mode` was added.
    /// Bumped to 5 when the Conquest fields were added.
    ///
    /// The field decodes with `decodeIfPresent ?? Ruleset.forMode(mode).defaultVictoryPointTarget`,
    /// so a v1 save still loads and plays to ten - which is what it was
    /// started at. The version is here so a future reader can tell the
    /// difference between "this game chose ten" and "this game predates the
    /// choice", not because the decoder needs it.
    public static let currentSchemaVersion = 5

    /// The schema version this value was decoded from (or
    /// `currentSchemaVersion` for a freshly created game). Persisted so a
    /// future decoder can tell what it is looking at instead of guessing.
    public var schemaVersion: Int

    /// Victory points needed to win THIS game.
    ///
    /// Lives beside the position rather than in a preference store because it
    /// is a rule the engine owns: `WinCondition` reads it, and a resumed or
    /// replayed game has to end where the original did. A global would make
    /// `checkForWinner` depend on process state rather than on the position -
    /// the same class of defect as the four `Set`-ordering bugs - and a
    /// twelve-point game resumed after a relaunch would silently revert to
    /// ten.
    public var victoryPointTarget: Int

    /// Which rule set THIS game is played under.
    ///
    /// Beside the position for the same reason `victoryPointTarget` is: the
    /// rules are a property of the game, not of the process. A global would
    /// make every rule read depend on which screen was last opened, and a
    /// resumed Expanded game would silently revert to classic's quantities
    /// while keeping its 37-tile board - the rules and the board disagreeing
    /// mid-game.
    public var mode: GameMode

    /// The quantities this game is played with. Derived, never stored, so a
    /// save cannot carry a rule set that disagrees with its own mode.
    public var rules: Ruleset { Ruleset.forMode(mode) }

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
    /// Every trade offer `PlayerID` has proposed and had declined so far this
    /// turn - reset for everyone on `.endTurn`, same lifecycle as
    /// `tradesAcceptedThisTurn`. Lets `TradeHeuristics.proposeTrades` retry with
    /// a genuinely different offer instead of recomposing the one that was just
    /// turned down (which, being a pure function of otherwise-unchanged state,
    /// it would otherwise reproduce exactly), and caps how many attempts a
    /// player gets per turn without needing separate session-local bookkeeping.
    public var declinedTradeOffersThisTurn: [PlayerID: [TradeOffer]]
    /// The rule layer. `.standard` for every game that is not Conquest.
    public var variant: GameVariant
    /// Conquest only: who holds each hex. No entry means unoccupied (or the desert).
    public var garrisons: [HexCoordinate: Garrison]
    /// Conquest only: undealt army cards, top first.
    public var armyDeck: [Int]
    /// Conquest only: each seat's hidden army cards, by strength. Kept here
    /// rather than on `Player` because `Player` decodes synthesized, and a new
    /// non-optional field there would reject every existing save.
    public var armyHands: [PlayerID: [Int]]
    /// Army cards bought this turn, not yet playable. Cleared on `.endTurn`.
    public var armyCardsBoughtThisTurn: [PlayerID: [Int]]
    /// Conquest only: what an army card costs in this game. Any three cards
    /// (Jake, 2026-09-24): a trained Expert found armies dead at one-of-each
    /// and mandatory at any-one; see `docs/AI_summaries/2026-09-23-conquest-expert-price.md`.
    public var armyPrice: ArmyPrice

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
        declinedTradeOffersThisTurn: [PlayerID: [TradeOffer]] = [:],
        rng: RandomSource = RandomSource(seed: UInt64.random(in: .min ... .max)),
        schemaVersion: Int = GameState.currentSchemaVersion,
        mode: GameMode = .classic,
        victoryPointTarget: Int = Ruleset.forMode(.classic).defaultVictoryPointTarget,
        variant: GameVariant = .standard,
        garrisons: [HexCoordinate: Garrison] = [:],
        armyDeck: [Int] = [],
        armyHands: [PlayerID: [Int]] = [:],
        armyCardsBoughtThisTurn: [PlayerID: [Int]] = [:],
        armyPrice: ArmyPrice = .anyThree
    ) {
        self.rng = rng
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.victoryPointTarget = victoryPointTarget
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
        self.declinedTradeOffersThisTurn = declinedTradeOffersThisTurn
        self.variant = variant
        self.garrisons = garrisons
        self.armyDeck = armyDeck
        self.armyHands = armyHands
        self.armyCardsBoughtThisTurn = armyCardsBoughtThisTurn
        self.armyPrice = armyPrice
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

        // Absent in every save written before modes existed. Those games were
        // played under the only rules there were.
        mode = try container.decodeIfPresent(GameMode.self, forKey: .mode) ?? .classic

        // Absent in every v1 save. Those games were started under the fixed
        // ten-point rule, so ten is not merely a safe default - it is the
        // value they actually played to.
        let decodedTarget = try container.decodeIfPresent(Int.self, forKey: .victoryPointTarget)
            ?? Ruleset.forMode(mode).defaultVictoryPointTarget
        // Range-checked on the way in, not only at construction. A save
        // carrying 0 - corruption, or a future version widening the range -
        // would otherwise make the very next build declare seat 0 the winner.
        //
        // Decode order is load-bearing: `mode` is read above, because
        // validating the target against a range not yet known would reject
        // every Expanded save as corrupt.
        guard Ruleset.forMode(mode).victoryPointTargets.contains(decodedTarget) else {
            throw DecodingError.dataCorruptedError(
                forKey: .victoryPointTarget,
                in: container,
                debugDescription: "Target \(decodedTarget) is outside \(mode.displayName)'s range"
            )
        }
        victoryPointTarget = decodedTarget
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
        declinedTradeOffersThisTurn = try container
            .decodeIfPresent([PlayerID: [TradeOffer]].self, forKey: .declinedTradeOffersThisTurn) ?? [:]
        // Absent in every save written before Conquest (schema < 5).
        variant = try container.decodeIfPresent(GameVariant.self, forKey: .variant) ?? .standard
        garrisons = try container.decodeIfPresent([HexCoordinate: Garrison].self, forKey: .garrisons) ?? [:]
        armyDeck = try container.decodeIfPresent([Int].self, forKey: .armyDeck) ?? []
        armyHands = try container.decodeIfPresent([PlayerID: [Int]].self, forKey: .armyHands) ?? [:]
        armyCardsBoughtThisTurn = try container
            .decodeIfPresent([PlayerID: [Int]].self, forKey: .armyCardsBoughtThisTurn) ?? [:]
        armyPrice = try container.decodeIfPresent(ArmyPrice.self, forKey: .armyPrice) ?? .anyThree
    }

    /// Victory points that are public knowledge for `id`: buildings plus the
    /// longest-road and largest-army bonuses, all of them visible on the
    /// board. Deliberately excludes held-but-unplayed victory-point cards,
    /// which are hidden information exactly like the rest of a hand.
    ///
    /// This lives here rather than in the HUD that displays it. A second
    /// victory-point formula in a view is a formula that can drift from the
    /// engine's - and the two differ only by the term that decides whether
    /// hidden information leaks, which is the worst possible thing to
    /// maintain in two places.
    public func publicVictoryPoints(for id: PlayerID) -> Int {
        guard let player = players.first(where: { $0.id == id }) else { return 0 }
        var total = buildingPoints(for: player)
        if longestRoadPlayer == id { total += rules.longestRoadBonus }
        if largestArmyPlayer == id { total += rules.largestArmyBonus }
        return total
    }

    /// Total victory points for `id`, INCLUDING hidden victory-point cards.
    /// Correct for a player's own total; use `publicVictoryPoints(for:)` for
    /// anything an opponent can see.
    public func victoryPoints(for id: PlayerID) -> Int {
        guard let player = players.first(where: { $0.id == id }) else { return 0 }
        var total = buildingAndCardPoints(for: player)
        if longestRoadPlayer == id { total += rules.longestRoadBonus }
        if largestArmyPlayer == id { total += rules.largestArmyBonus }
        return total
    }

    /// Buildings scored at this mode's rates. Driven off `BuildingKind.allCases`
    /// so a new building tier is a `Ruleset` entry rather than an edit here.
    private func buildingPoints(for player: Player) -> Int {
        BuildingKind.allCases.reduce(0) { total, kind in
            let count: Int
            switch kind {
            case .settlement: count = player.settlements.count
            case .city: count = player.cities.count
            }
            return total + count * rules.victoryPoints(for: kind)
        }
    }

    /// Buildings scored at this mode's rates, plus VP dev cards.
    private func buildingAndCardPoints(for player: Player) -> Int {
        buildingPoints(for: player) + player.devCards.filter { $0 == .victoryPoint }.count
    }
}

public enum GameSetup {
    /// Creates a fresh 4-player game (human at index 0, bots at 1-3) on
    /// `board`, with a full standard bank and a shuffled dev card deck,
    /// ready to begin the setup phase at player 0's first placement. Uses
    /// the system RNG; see the `rng:` overload below for deterministic
    /// (e.g. test) callers.
    public static func newGame(board: Board, victoryPointTarget: Int? = nil,
                               mode: GameMode = .classic, variant: GameVariant = .standard) -> GameState {
        var rng = SystemRandomNumberGenerator()
        return newGame(board: board, rng: &rng,
                       victoryPointTarget: victoryPointTarget, mode: mode, variant: variant)
    }

    /// Creates a fully reproducible game: `seed` fixes both the dev card
    /// shuffle and every dice roll and robber steal the game will go on to
    /// produce. Two calls with the same board and seed, played by the same
    /// policies, yield an identical move sequence - which is what makes
    /// headless self-play, A/B comparison of bot changes, and bisecting a
    /// failing simulation possible at all.
    public static func newGame(board: Board, seed: UInt64,
                               playerCount: Int = GameSetup.standardPlayerCount,
                               victoryPointTarget: Int? = nil,
                               mode: GameMode = .classic,
                               variant: GameVariant = .standard) -> GameState {
        var rng = RandomSource(seed: seed)
        return newGame(board: board, rng: &rng, playerCount: playerCount,
                       victoryPointTarget: victoryPointTarget, mode: mode, variant: variant)
    }

    /// Seats a standard game. Three and four are the sizes this board's
    /// resource and development-card counts are balanced for; the bank and
    /// the deck are unchanged between them, exactly as in the physical game.
    public static let standardPlayerCount = 4
    public static let supportedPlayerCounts = 3...4

    /// Table sizes a *new* game may be started at.
    ///
    /// Four only (Jake, 2026-09-16): "that's how these games are designed".
    ///
    /// Deliberately narrower than `supportedPlayerCounts`, which stays 3...4 so
    /// that a three-player game already on disk still loads, still replays, and
    /// still passes `GameSession`'s own guard. Narrowing the engine instead
    /// would turn every saved three-player game into a precondition failure on
    /// resume, and the simulator would lose a table size the strength harness
    /// still measures at.
    public static let newGameTableSizes = [4]

    /// Same as `newGame(board:)` but with an injectable RNG, so the dev card
    /// shuffle can be made deterministic (e.g. for tests). The in-game
    /// generator is seeded *from* `rng`, so a deterministic caller gets a
    /// deterministic game and not merely a deterministic opening deck.
    public static func newGame(board: Board, rng: inout some RandomNumberGenerator,
                               playerCount: Int = GameSetup.standardPlayerCount,
                               victoryPointTarget: Int? = nil,
                               mode: GameMode = .classic,
                               variant: GameVariant = .standard) -> GameState {
        precondition(supportedPlayerCounts.contains(playerCount),
                     "playerCount \(playerCount) is outside \(supportedPlayerCounts)")
        let rules = Ruleset.forMode(mode)
        let target = victoryPointTarget ?? rules.defaultVictoryPointTarget
        precondition(rules.victoryPointTargets.contains(target),
                     "victoryPointTarget \(target) is outside \(mode.displayName)'s \(rules.victoryPointTargets)")
        precondition(board.tiles.count == rules.board.tileCount,
                     "a \(board.tiles.count)-tile board cannot host \(mode.displayName), "
                     + "which is played on \(rules.board.tileCount) tiles")
        let players = (0..<playerCount).map { Player(id: PlayerID(index: $0)) }

        var bank: [Resource: Int] = [:]
        for resource in Resource.allCases {
            bank[resource] = rules.bankPerResource
        }

        // Driven off `DevCardType.allCases` sorted by `deckBuildOrder`, not off
        // the dictionary directly, so the deck is built in a stable order
        // before it is shuffled. Dictionary iteration order is seeded per
        // process; shuffling an unstably-ordered array gives a different deck
        // per launch for the same seed, which is the determinism bug this
        // repo has paid for four times. `deckBuildOrder` (rather than
        // `allCases`' own order) is what keeps this the historical stacking
        // order, so a seeded Classic game still deals the deck it always has.
        var devCardDeck: [DevCardType] = []
        for type in DevCardType.allCases.sorted(by: { $0.deckBuildOrder < $1.deckBuildOrder }) {
            devCardDeck.append(contentsOf: repeatElement(type, count: rules.devCardDeck[type, default: 0]))
        }
        devCardDeck.shuffle(using: &rng)

        // The state's seed is drawn BEFORE the army deck is shuffled, in the
        // same position it always was, so a standard game - which draws
        // nothing further - consumes exactly the sequence it did before
        // Conquest existed, and `SeededGameFingerprintTests` stays green.
        let stateSeed = rng.next()
        var armyDeck: [Int] = []
        var garrisons: [HexCoordinate: Garrison] = [:]
        if variant == .conquest {
            armyDeck = Conquest.buildArmyDeck(rules.armyDeck)
            armyDeck.shuffle(using: &rng)
            garrisons = Conquest.initialGarrisons(board: board)
        }

        return GameState(
            board: board,
            players: players,
            phase: .setupForward(playerIndex: 0),
            bank: bank,
            devCardDeck: devCardDeck,
            rng: RandomSource(seed: stateSeed),
            mode: mode,
            victoryPointTarget: target,
            variant: variant,
            garrisons: garrisons,
            armyDeck: armyDeck
        )
    }
}
