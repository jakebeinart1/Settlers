public enum RulesEngine {
    /// Stored beside every recorded move. Version 1 predates atomic Year of
    /// Plenty and mandatory robber-victim selection; new moves use version 2.
    public static let currentRulesVersion = 2
    public static let oldestSupportedRulesVersion = 1

    public static func legalMoves(for state: GameState) -> [GameMove] {
        switch state.phase {
        case .setupForward, .setupBackward:
            return SetupPhase.legalMoves(for: state)

        case .rollDice(let playerIndex):
            var moves: [GameMove] = [.rollDice]
            let player = state.players[playerIndex]
            moves += developmentCardMoves(for: player, in: state)
            return moves

        case .mainTurn(let playerIndex):
            let player = state.players[playerIndex]
            var moves: [GameMove] = [.endTurn]

            // Every enumeration below sorts before mapping. `onBoardEdges`,
            // `onBoardVertices` and `player.settlements` are all `Set`s, and
            // Swift seeds set iteration order per process - so without this,
            // `legalMoves` returns the same moves in a different order on
            // every launch, and any bot that breaks a tie by picking the
            // first-best candidate plays a different game from the same seed.
            if canAfford(Building.roadCost, player: player) {
                moves.append(contentsOf: state.board.onBoardEdges
                    .filter { Building.canBuildRoad($0, for: player.id, in: state) }
                    .sorted()
                    .map { .buildRoad($0) })
            }
            if canAfford(Building.settlementCost, player: player) {
                moves.append(contentsOf: state.board.onBoardVertices
                    .filter { Building.canBuildSettlement($0, for: player.id, in: state) }
                    .sorted()
                    .map { .buildSettlement($0) })
            }
            if canAfford(Building.cityCost, player: player) {
                moves.append(contentsOf: player.settlements
                    .filter { Building.canBuildCity($0, for: player.id, in: state) }
                    .sorted()
                    .map { .buildCity($0) })
            }
            if canAfford(Building.devCardCost, player: player) && !state.devCardDeck.isEmpty {
                moves.append(.buyDevCard)
            }
            moves += developmentCardMoves(for: player, in: state)
            for resource in Resource.allCases {
                let rate = Trading.bestRate(for: resource, player: player.id, state: state)
                guard (player.resources[resource] ?? 0) >= rate else { continue }
                for other in Resource.allCases where other != resource && (state.bank[other] ?? 0) >= 1 {
                    moves.append(.bankTrade(give: [resource: rate], get: [other: 1]))
                }
            }
            for offer in state.pendingTradeOffers where offer.from != player.id {
                // Accepting is only actually legal if the responder currently
                // holds what's wanted and the proposer still holds what they
                // offered (either side may have spent/traded cards since the
                // offer was made) - `Trading.respond` re-validates both and
                // throws otherwise, so `legalMoves` must match.
                if let proposer = state.players.first(where: { $0.id == offer.from }),
                   canAfford(offer.want, player: player),
                   canAfford(offer.give, player: proposer) {
                    moves.append(.respondToTrade(offerID: offer.id, accept: true))
                }
                moves.append(.respondToTrade(offerID: offer.id, accept: false))
            }
            moves += Conquest.moves(for: player, in: state)
            moves.append(contentsOf: tradeProposals(for: player))
            return moves

        case .discarding(let pending):
            // No single "acting player" is embedded in this phase - any player
            // in `pending` may discard whenever they are ready - so this
            // returns the union across all of them. Prefer
            // `legalMoves(for:seat:)` unless you genuinely want the union: a
            // discard here is only legal for the seat whose hand it was
            // computed from, so anything that picks from this list and applies
            // it as one seat can pick another seat's move and be rejected.
            var moves: [GameMove] = []
            for pid in pending.sorted() {
                moves.append(contentsOf: discardMoves(for: pid, in: state))
            }
            return moves

        case .movingRobber(let playerIndex):
            let thief = state.players[playerIndex].id
            var moves: [GameMove] = []
            for tile in state.board.tiles.map(\.coordinate) where tile != state.board.robberTile {
                let victims = Robber.eligibleVictims(for: tile, thief: thief, in: state)
                if victims.isEmpty {
                    moves.append(.moveRobber(tile, stealFrom: nil))
                } else {
                    moves += victims.map { .moveRobber(tile, stealFrom: $0) }
                }
            }
            return moves

        default:
            // Later tasks extend this switch for the other phases.
            return []
        }
    }

    /// How many of one resource an enumerated proposal may offer or ask for.
    ///
    /// Two, not one. The enumeration previously offered exactly one card for
    /// exactly one card, which meant a bot could not express "two ore for a
    /// wheat" - and lopsided trades are most of how Catan is actually
    /// negotiated. An agent whose action space cannot represent a two-for-one
    /// is not playing Catan badly; it is playing a different game.
    ///
    /// It stops at two deliberately. Going to three roughly doubles the
    /// enumeration again for offers real players rarely make, and this list is
    /// recomputed on the hot path - `GameView` reads it while rendering. Three
    /// or more, and multi-resource bundles, remain legal to *apply*:
    /// `Trading.proposeTrade` validates any positive offer the proposer can
    /// afford, so a human, or a policy that composes its own offers rather
    /// than picking from this list, can still make them. This bounds what is
    /// enumerated, not what is possible.
    public static let maxEnumeratedTradeQuantity = 2

    /// How many of one resource a *generous* proposal (see
    /// `TradeHeuristics`'s unlock-override) may offer, wider than
    /// `maxEnumeratedTradeQuantity` on the give side only. Fixed at 3 - one more
    /// than a bot would ever need to beat its own worst bank rate (4:1, no
    /// port), which is the bound that actually matters: a generous offer only
    /// exists to be a genuinely better deal than paying the bank, and above
    /// that ceiling it never can be. The want side stays at
    /// `maxEnumeratedTradeQuantity`; nothing asks for more.
    public static let maxGenerousGiveQuantity = 3

    /// How many DECLINES one player may accumulate in a single turn (via
    /// `state.declinedTradeOffersThisTurn`) before `GameSession` stops
    /// offering `.proposeTrade` as a legal move for them - not how many
    /// offers they may propose in total. An offer that gets ACCEPTED never
    /// increments this (`Trading.respond`'s accept branch only touches
    /// `tradesAcceptedThisTurn`), so a seat whose offers keep landing can, in
    /// principle, propose far more than 3 times in a turn - bounded only by
    /// `GameSession.maxActionsPerTurn`, not this constant. That's judged the
    /// right shape, not an oversight left over from the old
    /// `proposedTradeThisTurn` one-shot-per-turn gate this replaced: a bot
    /// that keeps successfully trading isn't the same failure mode as one
    /// that keeps getting turned down, and the latter is what this constant
    /// exists to stop - a policy that just keeps retrying a declined offer
    /// forever, crowding out every other move and never reaching `.endTurn`
    /// on its own. See the final-review fix report
    /// (`docs/AI_summaries/2026-09-03-creative-bot-trade-offers.md`) for the
    /// full reasoning.
    public static let maxTradeProposalsPerTurn = 3

    /// Trade proposals worth putting in front of a chooser.
    ///
    /// Bounded at `maxGenerousGiveQuantity` on the give side and
    /// `maxEnumeratedTradeQuantity` on the want side, one resource type per
    /// side: 5 give types x 4 want types x 3 x 2 = 120 at the absolute most, and
    /// far fewer in practice since the proposer must hold what they offer.
    private static func tradeProposals(for player: Player) -> [GameMove] {
        var moves: [GameMove] = []
        // Driven off `Resource.allCases`, not `player.resources` - dictionary
        // iteration order is seeded per process, and these would otherwise be
        // enumerated in a different order on every launch.
        for give in Resource.allCases {
            let held = player.resources[give] ?? 0
            guard held > 1 else { continue }
            for giveCount in 1...min(maxGenerousGiveQuantity, held - 1) {
                for want in Resource.allCases where want != give {
                    for wantCount in 1...maxEnumeratedTradeQuantity {
                        moves.append(.proposeTrade(TradeOffer.enumerated(
                            from: player.id, give: [give: giveCount], want: [want: wantCount])))
                    }
                }
            }
        }
        return moves
    }

    /// The most cards a composed proposal may put on the table.
    ///
    /// Five covers the lopsided bundles a strong player actually makes - two
    /// brick and two wood for the one wheat that finishes a city, which is the
    /// worked example this limit was set against - with one to spare, while
    /// keeping a policy from composing a hand-dumping offer no table would see
    /// in real play.
    public static let maxComposedTradeGive = 5
    /// The most cards a composed proposal may ask for. Three reaches a
    /// three-for-two, and nothing a single turn completes needs more.
    public static let maxComposedTradeWant = 3

    /// Whether `move` is a trade proposal `seat` may make although `legal` does
    /// not list it.
    ///
    /// ## Why policies may compose offers at all
    /// `legalMoves` lists single-resource offers only, because enumerating
    /// bundles would multiply a list that is rebuilt on the rendering path.
    /// But bundles are how a good player trades, and `Trading.proposeTrade`
    /// already applies any positive offer the proposer can afford. So the
    /// enumeration bounds what is *shown*, and this decides what a policy may
    /// *choose* - with the engine, not the policy, as the authority.
    ///
    /// ## What makes one permitted
    /// - Proposing must be allowed right now: `legal` offers at least one
    ///   proposal, which carries the phase, the turn, the pending-offer rule
    ///   and the per-turn cap with it rather than restating them here.
    /// - It comes from `seat`, asks for and gives something, never the same
    ///   resource on both sides, and stays within the composed limits.
    /// - `seat` can afford its side.
    /// - Its id is the content-derived `TradeOffer.enumerated` id, so a seeded
    ///   game that makes it replays identically in every process.
    public static func isPermittedComposedProposal(
        _ move: GameMove,
        by seat: PlayerID,
        in state: GameState,
        legal: [GameMove]
    ) -> Bool {
        guard case .proposeTrade(let offer) = move, offer.from == seat else { return false }
        guard legal.contains(where: { if case .proposeTrade = $0 { true } else { false } }) else { return false }
        guard isWellFormedComposition(offer),
              let proposer = state.players.first(where: { $0.id == seat }),
              canAfford(offer.give, player: proposer) else { return false }
        return offer.id == TradeOffer.enumerated(from: seat, give: offer.give, want: offer.want).id
    }

    /// Positive amounts, disjoint sides, and within the composed limits.
    private static func isWellFormedComposition(_ offer: TradeOffer) -> Bool {
        guard !offer.give.isEmpty, !offer.want.isEmpty,
              offer.give.values.allSatisfy({ $0 > 0 }),
              offer.want.values.allSatisfy({ $0 > 0 }),
              Set(offer.give.keys).isDisjoint(with: offer.want.keys) else { return false }
        let given = Resource.allCases.reduce(0) { $0 + (offer.give[$1] ?? 0) }
        let wanted = Resource.allCases.reduce(0) { $0 + (offer.want[$1] ?? 0) }
        return given <= maxComposedTradeGive && wanted <= maxComposedTradeWant
    }

    /// The moves `seat` may legally make right now - **when `seat` is the
    /// player the phase is waiting on.**
    ///
    /// The qualifier is real. Only `.discarding` is genuinely per-seat; in
    /// every other phase this returns the *acting* player's moves whoever
    /// asks, so calling it for a seat that is not up hands back a list `apply`
    /// will reject with `.notYourTurn`. `GameSession` only ever asks for the
    /// acting seat, so nothing is wrong today - but the previous one-line
    /// summary read as a promise that any seat could be queried, which would
    /// be a natural thing for a future agent or evaluator to rely on.
    ///
    /// Prefer this over `legalMoves(for:)` anywhere a specific player is about
    /// to choose. The unscoped version returns a *union* in `.discarding` -
    /// every pending player's combinations together - because no single seat
    /// owns that phase. A policy picking from the union can pick a discard
    /// computed from a different hand, and `apply` then rejects it. `Bot`
    /// worked around that with its own filter; anything else that tried,
    /// including a uniform-random policy, hit it immediately.
    ///
    /// An action list that includes moves the actor cannot make is also simply
    /// wrong as an action space: it teaches a learner that illegal moves are
    /// options.
    public static func legalMoves(for state: GameState, seat: PlayerID) -> [GameMove] {
        if case .discarding(let pending) = state.phase {
            guard pending.contains(seat) else { return [] }
            return discardMoves(for: seat, in: state)
        }
        return legalMoves(for: state)
    }

    /// Every discard `pid` could legally make, from their own hand.
    private static func discardMoves(for pid: PlayerID, in state: GameState) -> [GameMove] {
        guard let index = state.players.firstIndex(where: { $0.id == pid }) else { return [] }
        let player = state.players[index]
        let count = Robber.discardCount(for: player)
        return discardCombinations(holding: player.resources, count: count).map { .discard($0) }
    }

    /// Applies `move` and returns what happened, as structured events.
    ///
    /// Events are RETURNED rather than accumulated in `GameState`. The engine
    /// used to append a prose sentence to `state.log` on every move, which
    /// made the state 127x more expensive to copy (measured), forced the
    /// engine to guess which seat was human in order to write "You", and left
    /// the UI substring-matching that prose to drive a visual effect. A caller
    /// that wants a transcript keeps these; a search or self-play harness
    /// discards them and pays nothing. See `GameEvent`.
    @discardableResult
    public static func apply(
        _ move: GameMove,
        by player: PlayerID,
        to state: inout GameState
    ) throws -> [GameEvent] {
        try applyReportingPrivateEvents(move, by: player, to: &state).events
    }

    /// Applies a move once and returns both its public transcript and any
    /// actor-private facts produced by that exact application.
    public static func applyReportingPrivateEvents(
        _ move: GameMove,
        by player: PlayerID,
        to state: inout GameState
    ) throws -> AppliedMoveResult {
        var events: [GameEvent] = []
        var privateEvents: [PrivateGameEvent] = []
        switch state.phase {
        case .setupForward, .setupBackward:
            switch move {
            case .placeInitialSettlement, .placeInitialRoad:
                events += try SetupPhase.apply(move, by: player, to: &state)
            default:
                throw MoveError.wrongPhase
            }

        case .rollDice(let playerIndex):
            guard player.index == playerIndex else { throw MoveError.notYourTurn }

            // Any mature active card may be played before the roll. Resolve it
            // and leave the phase untouched so the player still owes the dice.
            if let event = try applyDevelopmentCard(move, by: player, to: &state) {
                WinCondition.checkForWinner(&state)
                events.append(event)
                events += winEvent(state)
                return AppliedMoveResult(events: events)
            }

            guard case .rollDice = move else { throw MoveError.wrongPhase }
            // Two independent d6 off the state's own generator, not the global
            // RNG - so a recorded move list replays to the same dice and a
            // seeded self-play run reproduces exactly. See `RandomSource`.
            let roll = Int.random(in: 1...6, using: &state.rng)
                + Int.random(in: 1...6, using: &state.rng)
            MainPhase.rollDice(state: &state, roll: roll)
            if roll != 7 {
                state.phase = .mainTurn(playerIndex: playerIndex)
            }
            // A roll of 7 routes into .discarding or .movingRobber, already
            // set by MainPhase.rollDice.
            events.append(.rolled(player, total: roll))

        case .discarding(let pending):
            guard pending.contains(player) else { throw MoveError.notYourTurn }
            guard case .discard(let discarded) = move else { throw MoveError.wrongPhase }
            guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
                throw MoveError.other("unknown player")
            }
            guard discarded.values.allSatisfy({ $0 >= 0 }) else { throw MoveError.illegalPlacement }
            let total = discarded.values.reduce(0, +)
            guard total == Robber.discardCount(for: state.players[playerIndex]) else {
                throw MoveError.illegalPlacement
            }
            try deduct(discarded, from: &state, playerIndex: playerIndex)
            events.append(.discarded(player, count: total))

            var remainingPending = pending
            remainingPending.remove(player)
            if remainingPending.isEmpty {
                state.phase = .movingRobber(playerIndex: state.robberMoverIndex ?? playerIndex)
                state.robberMoverIndex = nil
            } else {
                state.phase = .discarding(pending: remainingPending)
            }

        case .movingRobber(let playerIndex):
            guard player.index == playerIndex else { throw MoveError.notYourTurn }
            guard case .moveRobber(let target, let stealFrom) = move else { throw MoveError.wrongPhase }
            let stolen = try Robber.apply(move: target, stealFrom: stealFrom, by: player, to: &state)
            state.robberMoverIndex = nil
            state.phase = .mainTurn(playerIndex: playerIndex)
            events.append(.movedRobber(player, from: stealFrom, stealing: stolen))

        case .mainTurn(let playerIndex):
            // Trade responses come from whichever player the offer is
            // directed at, not necessarily the active turn player, so this
            // is handled before the "is it your turn" guard below.
            if case .respondToTrade(let offerID, let accept) = move {
                let offer = state.pendingTradeOffers.first(where: { $0.id == offerID })
                try Trading.respond(offerID: offerID, accept: accept, by: player, state: &state)
                if let offer {
                    events.append(accept
                        ? .acceptedTrade(player, from: offer.from, gave: offer.want, got: offer.give)
                        : .rejectedTrade(player, from: offer.from))
                }
                events += winEvent(state)
                return AppliedMoveResult(events: events)
            }

            guard player.index == playerIndex else { throw MoveError.notYourTurn }

            switch move {
            case .buildRoad(let edge):
                guard Building.canBuildRoad(edge, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.roadCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].roads.insert(edge)
                state.longestRoadPlayer = LongestRoad.compute(for: state)
                WinCondition.checkForWinner(&state)
                events.append(.builtRoad(player))

            case .buildSettlement(let vertex):
                guard Building.canBuildSettlement(vertex, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.settlementCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].settlements.insert(vertex)
                state.longestRoadPlayer = LongestRoad.compute(for: state)
                WinCondition.checkForWinner(&state)
                events.append(.builtSettlement(player))

            case .buildCity(let vertex):
                guard Building.canBuildCity(vertex, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.cityCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].settlements.remove(vertex)
                state.players[playerIndex].cities.insert(vertex)
                state.longestRoadPlayer = LongestRoad.compute(for: state)
                WinCondition.checkForWinner(&state)
                events.append(.builtCity(player))

            case .buyDevCard:
                let card = try DevCards.buy(by: player, state: &state)
                privateEvents.append(.boughtDevCard(owner: player, card: card))
                // A bought VP card counts toward victory points immediately
                // (it's the "playing" of a knight/road-building/etc. card
                // that's deferred a turn, not VP cards being counted), so a
                // win can trigger right here even though the card can't be
                // "played".
                WinCondition.checkForWinner(&state)
                events.append(.boughtDevCard(player))

            case .buyArmyCard:
                let paid = try Conquest.buy(by: player, state: &state)
                events.append(.boughtArmyCard(player, paid: paid))

            case .deployArmy(let hex, let strengths):
                let result = try Conquest.deploy(strengths, to: hex, by: player, state: &state)
                events.append(.deployedArmy(player, hex: hex, total: strengths.reduce(0, +), result: result))

            case .playKnight, .playRoadBuilding, .playYearOfPlenty, .playMonopoly:
                guard let event = try applyDevelopmentCard(move, by: player, to: &state) else {
                    throw MoveError.wrongPhase
                }
                WinCondition.checkForWinner(&state)
                events.append(event)

            case .bankTrade(let give, let get):
                try Trading.bankTrade(give: give, get: get, by: player, state: &state)
                events.append(.tradedWithBank(player, gave: give, got: get))

            case .proposeTrade(let offer):
                guard offer.from == player else { throw MoveError.notYourTurn }
                try Trading.proposeTrade(offer, state: &state)
                events.append(.proposedTrade(player, give: offer.give, want: offer.want))

            case .endTurn:
                state.devCardsBoughtThisTurn = [:]
                state.armyCardsBoughtThisTurn = [:]
                state.devCardPlayedThisTurn = nil
                state.tradesAcceptedThisTurn = [:]
                state.declinedTradeOffersThisTurn = [:]
                // An offer only ever left `pendingTradeOffers` when somebody
                // explicitly responded to it, so unanswered offers accumulated
                // across turns - a 93-deep backlog was observed in a single
                // game. That let an offer be accepted turns after it was made,
                // and inflated the branching factor of every subsequent
                // `legalMoves` call for free. A trade offer is a within-turn
                // negotiation; it does not outlive the turn that made it.
                state.pendingTradeOffers.removeAll()
                let nextIndex = (playerIndex + 1) % state.players.count
                state.phase = .rollDice(playerIndex: nextIndex)
                events.append(.endedTurn(player))

            default:
                throw MoveError.wrongPhase
            }

        default:
            throw MoveError.wrongPhase
        }
        events += winEvent(state)
        return AppliedMoveResult(events: events, privateEvents: privateEvents)
    }

    /// Replays one persisted move under the rule behavior recorded with it.
    /// This is not a way to opt new gameplay into old rules: production move
    /// application always uses `apply`, while checkpoint validation alone uses
    /// this compatibility boundary.
    @discardableResult
    public static func replay(
        _ move: GameMove,
        by player: PlayerID,
        rulesVersion: Int,
        to state: inout GameState
    ) throws -> [GameEvent] {
        guard (oldestSupportedRulesVersion...currentRulesVersion).contains(rulesVersion) else {
            throw MoveError.other("unsupported recorded rules version")
        }
        if rulesVersion == oldestSupportedRulesVersion,
           let events = try applyRulesVersionOneException(move, by: player, to: &state) {
            return events
        }
        return try apply(move, by: player, to: &state)
    }

    private static func applyRulesVersionOneException(
        _ move: GameMove,
        by player: PlayerID,
        to state: inout GameState
    ) throws -> [GameEvent]? {
        switch (state.phase, move) {
        case (.movingRobber(let seat), .moveRobber(let tile, nil))
            where seat == player.index && legacyNilVictimDiffers(at: tile, player: player, state: state):
            let stolen = try Robber.applyRulesVersionOne(
                move: tile, stealFrom: nil, by: player, to: &state)
            state.robberMoverIndex = nil
            state.phase = .mainTurn(playerIndex: seat)
            return [.movedRobber(player, from: nil, stealing: stolen)]

        case (.rollDice(let seat), .playKnight(let tile, nil))
            where seat == player.index && legacyNilVictimDiffers(at: tile, player: player, state: state):
            return try applyLegacyKnight(tile: tile, by: player, state: &state)

        case (.mainTurn(let seat), .playKnight(let tile, nil))
            where seat == player.index && legacyNilVictimDiffers(at: tile, player: player, state: state):
            return try applyLegacyKnight(tile: tile, by: player, state: &state)

        case (.mainTurn(let seat), .playYearOfPlenty(let first, let second))
            where seat == player.index && !DevCards.canTakeForYearOfPlenty(first, second, from: state):
            try DevCards.playYearOfPlentyRulesVersionOne(
                first, second, by: player, state: &state)
            WinCondition.checkForWinner(&state)
            var requested: [Resource: Int] = [:]
            requested[first, default: 0] += 1
            requested[second, default: 0] += 1
            return [.playedYearOfPlenty(player, taken: requested)] + winEvent(state)

        default:
            return nil
        }
    }

    private static func legacyNilVictimDiffers(
        at tile: HexCoordinate,
        player: PlayerID,
        state: GameState
    ) -> Bool {
        !state.board.tiles.contains(where: { $0.coordinate == tile })
            || !Robber.eligibleVictims(for: tile, thief: player, in: state).isEmpty
    }

    private static func applyLegacyKnight(
        tile: HexCoordinate,
        by player: PlayerID,
        state: inout GameState
    ) throws -> [GameEvent] {
        let stolen = try DevCards.playKnightRulesVersionOne(
            moveRobberTo: tile, stealFrom: nil, by: player, state: &state)
        WinCondition.checkForWinner(&state)
        return [.playedKnight(player, from: nil, stealing: stolen)] + winEvent(state)
    }

    /// Every complete development-card decision available to `player` in either
    /// active turn phase. Choices are complete `GameMove`s, so presentation may
    /// stage one without mutating state and commit it once.
    private static func developmentCardMoves(for player: Player, in state: GameState) -> [GameMove] {
        var moves: [GameMove] = []
        if DevCards.canPlay(.knight, by: player.id, in: state) {
            for tile in state.board.tiles.map(\.coordinate) where tile != state.board.robberTile {
                let victims = Robber.eligibleVictims(for: tile, thief: player.id, in: state)
                if victims.isEmpty {
                    moves.append(.playKnight(moveRobberTo: tile, stealFrom: nil))
                } else {
                    moves += victims.map { .playKnight(moveRobberTo: tile, stealFrom: $0) }
                }
            }
        }
        if DevCards.canPlay(.roadBuilding, by: player.id, in: state) {
            moves += DevCards.legalRoadBuildingPairs(by: player.id, in: state)
                .map { .playRoadBuilding($0.first, $0.second) }
        }
        if DevCards.canPlay(.yearOfPlenty, by: player.id, in: state) {
            for first in Resource.allCases {
                for second in Resource.allCases where DevCards.canTakeForYearOfPlenty(first, second, from: state) {
                    moves.append(.playYearOfPlenty(first, second))
                }
            }
        }
        if DevCards.canPlay(.monopoly, by: player.id, in: state) {
            moves += Resource.allCases.map { .playMonopoly($0) }
        }
        return moves
    }

    /// Applies one active development card and returns its public result. A nil
    /// return means the move is not a development-card move at all.
    private static func applyDevelopmentCard(
        _ move: GameMove,
        by player: PlayerID,
        to state: inout GameState
    ) throws -> GameEvent? {
        switch move {
        case .playKnight(let tile, let victim):
            let stolen = try DevCards.playKnight(
                moveRobberTo: tile, stealFrom: victim, by: player, state: &state)
            return .playedKnight(player, from: victim, stealing: stolen)
        case .playRoadBuilding(let first, let second):
            try DevCards.playRoadBuilding(first, second, by: player, state: &state)
            return .playedRoadBuilding(player)
        case .playYearOfPlenty(let first, let second):
            try DevCards.playYearOfPlenty(first, second, by: player, state: &state)
            var taken: [Resource: Int] = [:]
            taken[first, default: 0] += 1
            taken[second, default: 0] += 1
            return .playedYearOfPlenty(player, taken: taken)
        case .playMonopoly(let resource):
            let count = try DevCards.playMonopoly(resource, by: player, state: &state)
            return .playedMonopoly(player, resource: resource, gained: count)
        default:
            return nil
        }
    }

    /// A `.gameWon` event, but only on the transition into `.gameOver`.
    /// `apply` calls this at each of its exits; emitting it from one place
    /// keeps every path consistent, including the two that return early.
    private static func winEvent(_ state: GameState) -> [GameEvent] {
        guard case .gameOver(let winner) = state.phase else { return [] }
        return [.gameWon(winner)]
    }

    // MARK: - Helpers

    /// Whether `player` holds at least `cost`.
    ///
    /// Public because it was otherwise re-implemented by hand at seven call
    /// sites across the engine, the AI and the views - each an opportunity for
    /// one of them to drift from the rule the engine actually enforces, which
    /// is exactly how the bank-trade bug shipped.
    public static func canAfford(_ cost: [Resource: Int], player: Player) -> Bool {
        cost.allSatisfy { resource, amount in (player.resources[resource] ?? 0) >= amount }
    }

    static func deduct(_ cost: [Resource: Int], from state: inout GameState, playerIndex: Int) throws {
        guard canAfford(cost, player: state.players[playerIndex]) else { throw MoveError.insufficientResources }
        for (resource, amount) in cost {
            state.players[playerIndex].resources[resource, default: 0] -= amount
            state.bank[resource, default: 0] += amount
        }
    }

    /// Every way to pick exactly `count` cards from `holding` (a resource ->
    /// count map), one resource type at a time via backtracking. Used to
    /// enumerate legal `.discard` combinations - small enough hands (at most
    /// ~18 cards over 5 resource types) that this never blows up.
    private static func discardCombinations(holding: [Resource: Int], count: Int) -> [[Resource: Int]] {
        let resources = Resource.allCases
        var results: [[Resource: Int]] = []

        func backtrack(index: Int, remaining: Int, chosen: [Resource: Int]) {
            if remaining == 0 {
                results.append(chosen)
                return
            }
            guard index < resources.count else { return }
            let resource = resources[index]
            let maxTake = min(remaining, holding[resource] ?? 0)
            for take in 0...maxTake {
                var next = chosen
                if take > 0 { next[resource] = take }
                backtrack(index: index + 1, remaining: remaining - take, chosen: next)
            }
        }

        backtrack(index: 0, remaining: count, chosen: [:])
        return results
    }
}
