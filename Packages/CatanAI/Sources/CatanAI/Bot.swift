import CatanEngine

/// A baseline bot that always plays through `RulesEngine.legalMoves` -
/// exactly the same entrypoint a human-driven UI uses - so it can never
/// fabricate an illegal move. Placement and build choices lean on
/// `PlacementHeuristics`/`BuildPlanner`; other move categories (trading,
/// dev-card play, robber targeting beyond a simple safe default) are left to
/// Task 10.
public struct Bot: Sendable {
    public let personality: BotPersonality

    public init(personality: BotPersonality) {
        self.personality = personality
    }

    /// Always returns a member of `RulesEngine.legalMoves(for: state)`.
    public func decide(for state: GameState, player: PlayerID) -> GameMove {
        let legal = RulesEngine.legalMoves(for: state)

        switch state.phase {
        case .setupForward, .setupBackward:
            return decideSetupPlacement(legal: legal, state: state)

        case .rollDice:
            return .rollDice

        case .mainTurn:
            return decideMainTurn(legal: legal, state: state, player: player)

        case .discarding:
            return decideDiscard(legal: legal, state: state, player: player)

        case .movingRobber:
            return decideRobber(legal: legal, state: state, player: player)

        case .gameOver:
            // `RulesEngine.legalMoves` always returns `[]` for `.gameOver`
            // (see its `default: return []` case), so `legal.first ?? .endTurn`
            // would silently hand back `.endTurn` - a move that is NOT a
            // member of `legalMoves(for:)` here, breaking `decide`'s
            // contract. `decide` is never expected to be called once the
            // game is over, so fail loudly instead of returning a plausible
            // but illegal move.
            preconditionFailure("Bot.decide should never be called when the game is over")
        }
    }

    // MARK: - Setup placement

    private func decideSetupPlacement(legal: [GameMove], state: GameState) -> GameMove {
        guard !legal.isEmpty else { return .endTurn }

        if case .placeInitialSettlement = legal[0] {
            var best = legal[0]
            var bestScore = -Double.infinity
            for move in legal {
                guard case .placeInitialSettlement(let vertex) = move else { continue }
                let score = PlacementHeuristics.score(vertex: vertex, board: state.board)
                if score > bestScore {
                    bestScore = score
                    best = move
                }
            }
            return best
        }

        // Otherwise every legal move is `.placeInitialRoad` - point it
        // toward whichever endpoint has the better future settlement value.
        var best = legal[0]
        var bestScore = -Double.infinity
        for move in legal {
            guard case .placeInitialRoad(let edge) = move else { continue }
            let (a, b) = state.board.vertices(of: edge)
            let score = max(
                PlacementHeuristics.score(vertex: a, board: state.board),
                PlacementHeuristics.score(vertex: b, board: state.board)
            )
            if score > bestScore {
                bestScore = score
                best = move
            }
        }
        return best
    }

    // MARK: - Discarding

    private func decideDiscard(legal: [GameMove], state: GameState, player: PlayerID) -> GameMove {
        guard let me = state.players.first(where: { $0.id == player }) else {
            return legal.first ?? .endTurn
        }
        let requiredCount = Robber.discardCount(for: me)

        // `legalMoves(for:)` in `.discarding` is the union of every pending
        // player's legal combinations, so first narrow to ones that are
        // actually affordable for and sized for this player.
        let mine = legal.filter { move in
            guard case .discard(let discarded) = move else { return false }
            guard discarded.values.reduce(0, +) == requiredCount else { return false }
            return discarded.allSatisfy { resource, amount in (me.resources[resource] ?? 0) >= amount }
        }
        // `mine` should never be empty: `RulesEngine`'s discard-combination
        // enumeration (`discardCombinations` in RulesEngine.swift) can always
        // produce at least one way to discard exactly `requiredCount` cards
        // from a hand that holds >= `requiredCount` cards (discard is a
        // subset of the hand itself), and `requiredCount` (half the hand,
        // rounded down) is by construction never more than what `me` holds.
        // If this ever fires, that invariant broke - falling back to
        // `legal.first` here would silently return a DIFFERENT pending
        // player's `.discard` combination (still a member of the union
        // `legal`, but not guaranteed to satisfy `player`'s own required
        // count/holdings), which `RulesEngine.apply` would then reject as
        // illegal. Fail loudly instead.
        guard !mine.isEmpty else {
            preconditionFailure("no legal discard combination found for \(player) holding \(me.resources)")
        }

        // Prefer discarding from whichever resources this player holds the
        // most of, keeping their remaining hand as diverse as possible.
        func redundancy(_ discarded: [Resource: Int]) -> Int {
            discarded.reduce(0) { partial, entry in
                let (resource, amount) = entry
                return partial + amount * (me.resources[resource] ?? 0)
            }
        }

        return mine.max { a, b in
            guard case .discard(let da) = a, case .discard(let db) = b else { return false }
            return redundancy(da) < redundancy(db)
        } ?? mine[0]
    }

    // MARK: - Robber

    private func decideRobber(legal: [GameMove], state: GameState, player: PlayerID) -> GameMove {
        guard !legal.isEmpty else { return .endTurn }

        // `RobberHeuristics` only decides intent (maximize disruption to the
        // leading opponent) - it doesn't know which victims are actually
        // eligible to steal from (e.g. it may name a leader holding zero
        // resource cards), so match its suggestion against `legal` and fall
        // back to the best legal victim on the same tile if the exact
        // suggested pairing isn't available.
        let (tile, victim) = RobberHeuristics.chooseRobberTarget(state: state, player: player)
        if let exact = matchLegal(.moveRobber(tile, stealFrom: victim), in: legal) {
            return exact
        }

        let sameTile = legal.filter { move in
            guard case .moveRobber(let t, _) = move else { return false }
            return t == tile
        }
        guard !sameTile.isEmpty else { return legal[0] }

        func resourceCount(_ victim: PlayerID?) -> Int {
            guard let victim, let owner = state.players.first(where: { $0.id == victim }) else { return -1 }
            return owner.resources.values.reduce(0, +)
        }
        return sameTile.max { a, b in
            guard case .moveRobber(_, let va) = a, case .moveRobber(_, let vb) = b else { return false }
            return resourceCount(va) < resourceCount(vb)
        } ?? sameTile[0]
    }

    // MARK: - Main turn (build / trade / dev card)

    /// Weighs candidate moves across every category legal during a main
    /// turn - building, accepting a pending trade, playing a dev card,
    /// buying a dev card, and proposing a trade - scored so that `personality`
    /// shifts which category wins close calls, then returns whichever
    /// scores highest (or `.endTurn` if nothing clears the bar).
    private func decideMainTurn(legal: [GameMove], state: GameState, player: PlayerID) -> GameMove {
        var best: (move: GameMove, score: Double)?

        func consider(_ desired: GameMove?, score: Double) {
            guard let desired, let matched = matchLegal(desired, in: legal) else { return }
            if best == nil || score > best!.score {
                best = (matched, score)
            }
        }

        // Accepting a good pending trade is usually as valuable as a solid
        // build - score it in the same range, nudged by trade willingness.
        for offer in state.pendingTradeOffers where offer.from != player {
            if TradeHeuristics.evaluate(offer: offer, receiver: player, state: state, personality: personality) {
                consider(.respondToTrade(offerID: offer.id, accept: true), score: 2.0 + personality.tradeWillingness * 3.0)
            }
        }

        // Playing an owned dev card (knight/road building/year of
        // plenty/monopoly) never competes for the same resources as a build,
        // so it's always worth weighing independently; aggressive bots lean
        // into it harder (mostly via knight plays).
        consider(DevCardHeuristics.choosePlay(state: state, player: player, personality: personality), score: 2.5 + personality.aggressiveness * 2.0)

        let buildMove = BuildPlanner.chooseBuild(for: state, player: player, personality: personality)
        consider(buildMove, score: 3.0)

        // Buying/proposing a trade are fallbacks considered only once a
        // build wasn't clearly worth it (buying is already scored as part of
        // `BuildPlanner`'s own candidates when it *is* worthwhile).
        if buildMove == nil {
            if DevCardHeuristics.shouldBuyDevCard(state: state, player: player) {
                consider(.buyDevCard, score: 1.6 + personality.aggressiveness * 0.5)
            }
            for offer in TradeHeuristics.proposeTrades(state: state, player: player, personality: personality) {
                consider(.proposeTrade(offer), score: 1.0 + personality.tradeWillingness)
            }
        }

        return best?.move ?? .endTurn
    }

    /// Finds the member of `legal` that structurally matches `desired`
    /// (comparing payloads, since `GameMove` isn't `Equatable` and a
    /// `TradeOffer`'s freshly-generated `id` wouldn't match the legal
    /// instance's `id` anyway). Ensures every move this file hands back
    /// really is a member of `RulesEngine.legalMoves(for:)`, never a
    /// heuristic's raw suggestion.
    private func matchLegal(_ desired: GameMove, in legal: [GameMove]) -> GameMove? {
        for candidate in legal {
            switch (desired, candidate) {
            case (.buildRoad(let x), .buildRoad(let y)) where x == y: return candidate
            case (.buildSettlement(let x), .buildSettlement(let y)) where x == y: return candidate
            case (.buildCity(let x), .buildCity(let y)) where x == y: return candidate
            case (.buyDevCard, .buyDevCard): return candidate
            case (.playKnight(let mx, let sx), .playKnight(let my, let sy)) where mx == my && sx == sy: return candidate
            case (.playRoadBuilding(let x1, let x2), .playRoadBuilding(let y1, let y2)) where x1 == y1 && x2 == y2: return candidate
            case (.playYearOfPlenty(let x1, let x2), .playYearOfPlenty(let y1, let y2)) where x1 == y1 && x2 == y2: return candidate
            case (.playMonopoly(let x), .playMonopoly(let y)) where x == y: return candidate
            case (.moveRobber(let tx, let sx), .moveRobber(let ty, let sy)) where tx == ty && sx == sy: return candidate
            case (.bankTrade(let gx, let ax), .bankTrade(let gy, let ay)) where gx == gy && ax == ay: return candidate
            case (.proposeTrade(let x), .proposeTrade(let y)) where x.from == y.from && x.give == y.give && x.want == y.want: return candidate
            case (.respondToTrade(let ox, let ax), .respondToTrade(let oy, let ay)) where ox == oy && ax == ay: return candidate
            case (.endTurn, .endTurn): return candidate
            default: continue
            }
        }
        return nil
    }
}
