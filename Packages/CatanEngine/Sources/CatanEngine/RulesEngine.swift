public enum RulesEngine {
    public static func legalMoves(for state: GameState) -> [GameMove] {
        switch state.phase {
        case .setupForward, .setupBackward:
            return SetupPhase.legalMoves(for: state)

        case .rollDice(let playerIndex):
            var moves: [GameMove] = [.rollDice]
            // Knight is the one development card the official rules let you
            // play before rolling (e.g. to move the robber off your own
            // tile before the dice can hit it) - every other card is only
            // enumerated in `.mainTurn`, after the roll.
            let player = state.players[playerIndex]
            if DevCards.canPlay(.knight, by: player.id, in: state) {
                for tile in state.board.tiles.map(\.coordinate) where tile != state.board.robberTile {
                    moves.append(.playKnight(moveRobberTo: tile, stealFrom: nil))
                    moves.append(contentsOf: Robber.eligibleVictims(for: tile, thief: player.id, in: state)
                        .map { .playKnight(moveRobberTo: tile, stealFrom: $0) })
                }
            }
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
            if DevCards.canPlay(.knight, by: player.id, in: state) {
                for tile in state.board.tiles.map(\.coordinate) where tile != state.board.robberTile {
                    moves.append(.playKnight(moveRobberTo: tile, stealFrom: nil))
                    moves.append(contentsOf: Robber.eligibleVictims(for: tile, thief: player.id, in: state)
                        .map { .playKnight(moveRobberTo: tile, stealFrom: $0) })
                }
            }
            if DevCards.canPlay(.roadBuilding, by: player.id, in: state) {
                let legalEdges = state.board.onBoardEdges
                    .filter { Building.canBuildRoad($0, for: player.id, in: state) }
                    .sorted()
                let allEdges = state.board.onBoardEdges.sorted()
                // The second edge is judged against a board where the first is
                // already placed, so the pair is legal *in sequence*. Mutating
                // one player's road set and restoring it beats the previous
                // `var afterE1 = state` (a full `GameState` copy - board, all
                // four players, both decks - once per candidate first edge),
                // which made this branch the most expensive thing in the
                // engine at ~10.8ms per call with a Road Building card in hand.
                var probe = state
                for e1 in legalEdges {
                    probe.players[playerIndex].roads.insert(e1)
                    for e2 in allEdges where e2 != e1 && Building.canBuildRoad(e2, for: player.id, in: probe) {
                        moves.append(.playRoadBuilding(e1, e2))
                    }
                    probe.players[playerIndex].roads.remove(e1)
                }
            }
            if DevCards.canPlay(.yearOfPlenty, by: player.id, in: state) {
                for r1 in Resource.allCases {
                    for r2 in Resource.allCases {
                        moves.append(.playYearOfPlenty(r1, r2))
                    }
                }
            }
            if DevCards.canPlay(.monopoly, by: player.id, in: state) {
                moves.append(contentsOf: Resource.allCases.map { .playMonopoly($0) })
            }
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
                moves.append(.moveRobber(tile, stealFrom: nil))
                moves.append(contentsOf: Robber.eligibleVictims(for: tile, thief: thief, in: state)
                    .map { .moveRobber(tile, stealFrom: $0) })
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

    /// How many trade offers one player may propose in a single turn before
    /// `GameSession` stops offering `.proposeTrade` as a legal move for them.
    /// Three, not one: a declined offer should get a genuinely different retry
    /// (see `TradeHeuristics.proposeTrades`), not silence for the rest of the
    /// turn, but a policy that just keeps trying forever crowds out every other
    /// move and never reaches `.endTurn` on its own.
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
    public static func apply(_ move: GameMove, by player: PlayerID, to state: inout GameState) throws -> [GameEvent] {
        var events: [GameEvent] = []
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

            // Knight is the one card playable before rolling - handle it
            // here and stay in `.rollDice` so the player still has to roll
            // afterward.
            if case .playKnight(let moveRobberTo, let stealFrom) = move {
                let stolen = try DevCards.playKnight(
                    moveRobberTo: moveRobberTo, stealFrom: stealFrom, by: player, state: &state)
                WinCondition.checkForWinner(&state)
                events.append(.playedKnight(player, from: stealFrom, stealing: stolen))
                events += winEvent(state)
                return events
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
                return events
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
                try DevCards.buy(by: player, state: &state)
                // A bought VP card counts toward victory points immediately
                // (it's the "playing" of a knight/road-building/etc. card
                // that's deferred a turn, not VP cards being counted), so a
                // win can trigger right here even though the card can't be
                // "played".
                WinCondition.checkForWinner(&state)
                events.append(.boughtDevCard(player))

            case .playKnight(let moveRobberTo, let stealFrom):
                let stolen = try DevCards.playKnight(
                    moveRobberTo: moveRobberTo, stealFrom: stealFrom, by: player, state: &state)
                WinCondition.checkForWinner(&state)
                events.append(.playedKnight(player, from: stealFrom, stealing: stolen))

            case .playRoadBuilding(let e1, let e2):
                try DevCards.playRoadBuilding(e1, e2, by: player, state: &state)
                WinCondition.checkForWinner(&state)
                events.append(.playedRoadBuilding(player))

            case .playYearOfPlenty(let r1, let r2):
                try DevCards.playYearOfPlenty(r1, r2, by: player, state: &state)
                // r1 and r2 may be the same resource (e.g. "take 2 lumber"
                // is a legal choice - see the legalMoves generation above,
                // which enumerates r1/r2 independently). Building the log
                // line's resource map via a dictionary literal `[r1: 1, r2:
                // 1]` would crash with "duplicate keys" whenever r1 == r2,
                // so tally into a dictionary instead, which merges the two
                // increments correctly either way.
                var taken: [Resource: Int] = [:]
                taken[r1, default: 0] += 1
                taken[r2, default: 0] += 1
                events.append(.playedYearOfPlenty(player, taken: taken))

            case .playMonopoly(let resource):
                let collected = try DevCards.playMonopoly(resource, by: player, state: &state)
                events.append(.playedMonopoly(player, resource: resource, gained: collected))

            case .bankTrade(let give, let get):
                try Trading.bankTrade(give: give, get: get, by: player, state: &state)
                events.append(.tradedWithBank(player, gave: give, got: get))

            case .proposeTrade(let offer):
                guard offer.from == player else { throw MoveError.notYourTurn }
                try Trading.proposeTrade(offer, state: &state)
                events.append(.proposedTrade(player, give: offer.give, want: offer.want))

            case .endTurn:
                state.devCardsBoughtThisTurn = [:]
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
        return events
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
