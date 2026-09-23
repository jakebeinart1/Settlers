import CatanEngine

/// A baseline bot that always plays through `RulesEngine.legalMoves` -
/// exactly the same entrypoint a human-driven UI uses - so it can never
/// fabricate an illegal move. Placement and build choices lean on
/// `PlacementHeuristics`/`BuildPlanner`; other move categories (trading,
/// dev-card play, robber targeting beyond a simple safe default) are left to
/// Task 10.
public struct Bot: Sendable {
    public let personality: BotPersonality

    /// The tuning constants every heuristic this bot consults scores with.
    /// Separate from `personality`: a personality is a handful of dials
    /// describing a *play style* and is part of the game's presentation
    /// (which opponent you are facing), while these are the full numeric
    /// policy underneath and exist to be swept or trained. Defaulted so
    /// callers that don't care never see them.
    public let weights: BotWeights
    /// When this bot buys Conquest army cards. An experiment knob, not a
    /// personality trait. See `ArmyBuying`.
    public let armyBuying: ArmyBuying

    public init(personality: BotPersonality, weights: BotWeights = .default, armyBuying: ArmyBuying = .idle) {
        self.personality = personality
        self.weights = weights
        self.armyBuying = armyBuying
    }

    /// Always returns a member of `RulesEngine.legalMoves(for: state)`.
    /// Convenience overload for callers (the real game, most tests) that
    /// don't need a reproducible tie-break - see the `rng:` overload below
    /// for one that does.
    public func decide(for state: GameState, player: PlayerID) -> GameMove {
        var rng = SystemRandomNumberGenerator()
        return decide(for: state, player: player, rng: &rng)
    }

    /// Same as `decide(for:player:)`, but with an injectable RNG so build
    /// near-ties (see `BuildPlanner.chooseBuild`'s `tieMargin`) can be made
    /// deterministic - e.g. for tests that need a reproducible pick.
    public func decide(for state: GameState, player: PlayerID, rng: inout some RandomNumberGenerator) -> GameMove {
        let legal = RulesEngine.legalMoves(for: state)
        return decide(for: state, player: player, legalMoves: legal, rng: &rng)
    }

    /// Chooses from the caller's seat-scoped action list.
    ///
    /// `Policy` observations may deliberately narrow the engine's complete
    /// list—for example, an out-of-turn trade responder may only accept or
    /// reject. Recomputing here bypassed that mask and let the adapter return
    /// actions the session had never offered it.
    public func decide(
        for state: GameState,
        player: PlayerID,
        legalMoves legal: [GameMove],
        rng: inout some RandomNumberGenerator
    ) -> GameMove {
        var assessments: [TradeAssessment] = []
        return decide(for: state, player: player, legalMoves: legal, rng: &rng,
                      assessments: &assessments, recordingAssessments: false)
    }

    /// Appends each actual trade assessment in evaluation order during this
    /// decision, preserving existing entries. Repeated evaluations remain
    /// repeated; masked-out/scoped early exits produce no invented records.
    /// Missing receivers produce no assessment. The action mask, policy and
    /// RNG consumption are identical to the overload without diagnostics.
    public func decide(
        for state: GameState,
        player: PlayerID,
        legalMoves legal: [GameMove],
        rng: inout some RandomNumberGenerator,
        assessments: inout [TradeAssessment]
    ) -> GameMove {
        decide(for: state, player: player, legalMoves: legal, rng: &rng,
               assessments: &assessments, recordingAssessments: true)
    }

    private func decide(
        for state: GameState,
        player: PlayerID,
        legalMoves legal: [GameMove],
        rng: inout some RandomNumberGenerator,
        assessments: inout [TradeAssessment],
        recordingAssessments: Bool
    ) -> GameMove {
        precondition(!legal.isEmpty, "asked to decide with no legal moves")

        let chosen: GameMove
        switch state.phase {
        case .setupForward, .setupBackward:
            chosen = decideSetupPlacement(legal: legal, state: state, player: player)

        case .rollDice:
            chosen = legal.contains(.rollDice) ? .rollDice : legal[0]

        case .mainTurn:
            chosen = decideMainTurn(legal: legal, state: state, player: player, rng: &rng,
                                    assessments: &assessments, recordingAssessments: recordingAssessments)

        case .discarding:
            chosen = decideDiscard(legal: legal, state: state, player: player)

        case .movingRobber:
            chosen = decideRobber(legal: legal, state: state, player: player)

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
        precondition(legal.contains(chosen), "Bot returned a move outside the supplied action mask")
        return chosen
    }

    // MARK: - Setup placement

    private func decideSetupPlacement(legal: [GameMove], state: GameState, player: PlayerID) -> GameMove {
        guard !legal.isEmpty else { return .endTurn }

        // Empty for the very first placement (nothing built yet); once a
        // first settlement exists, scoring the second one against it
        // pushes toward covering new resource types rather than just
        // re-maximizing pips on ones already covered (see
        // `PlacementHeuristics.score`'s `alreadyCovered` doc).
        let alreadyCovered = coveredResources(for: player, in: state)

        if case .placeInitialSettlement = legal[0] {
            var best = legal[0]
            var bestScore = -Double.infinity
            for move in legal {
                guard case .placeInitialSettlement(let vertex) = move else { continue }
                let score = PlacementHeuristics.score(
                    vertex: vertex, board: state.board, alreadyCovered: alreadyCovered, weights: weights
                )
                if score > bestScore {
                    bestScore = score
                    best = move
                }
            }
            return best
        }

        // Otherwise every legal move is `.placeInitialRoad` - point it toward
        // the outward endpoint. All candidates share the just-placed
        // settlement endpoint, so scoring `max(a, b)` made that same occupied,
        // often-high-value endpoint win every comparison and reduced the road
        // choice to legal-move order.
        var best = legal[0]
        var bestScore = -Double.infinity
        let ownBuildings = state.players.first(where: { $0.id == player })
            .map { $0.settlements.union($0.cities) } ?? []
        for move in legal {
            guard case .placeInitialRoad(let edge) = move else { continue }
            let (a, b) = state.board.vertices(of: edge)
            let score: Double
            if state.rules.isLargeBoard {
                let outward = ownBuildings.contains(a) ? b : a
                score = PlacementHeuristics.score(
                    vertex: outward, board: state.board, alreadyCovered: alreadyCovered, weights: weights
                )
            } else {
                score = max(
                    PlacementHeuristics.score(
                        vertex: a, board: state.board, alreadyCovered: alreadyCovered, weights: weights
                    ),
                    PlacementHeuristics.score(
                        vertex: b, board: state.board, alreadyCovered: alreadyCovered, weights: weights
                    )
                )
            }
            if score > bestScore {
                bestScore = score
                best = move
            }
        }
        return best
    }

    /// The resource types touching any settlement/city `player` already
    /// owns - empty before their first setup placement.
    private func coveredResources(for player: PlayerID, in state: GameState) -> Set<Resource> {
        guard let me = state.players.first(where: { $0.id == player }) else { return [] }
        var resources = Set<Resource>()
        for vertex in me.settlements.union(me.cities) {
            for coordinate in vertex.touchingTiles {
                guard let tile = state.board.tiles.first(where: { $0.coordinate == coordinate }) else { continue }
                if case .resource(let resource) = tile.kind {
                    resources.insert(resource)
                }
            }
        }
        return resources
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
        let (tile, victim) = RobberHeuristics.chooseRobberTarget(
            state: state, player: player, personality: personality, weights: weights
        )
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
    private func decideMainTurn(
        legal: [GameMove], state: GameState, player: PlayerID, rng: inout some RandomNumberGenerator,
        assessments: inout [TradeAssessment], recordingAssessments: Bool
    ) -> GameMove {
        if let response = decideScopedTradeResponse(legal: legal, state: state, player: player,
                                                   assessments: &assessments, recordingAssessments: recordingAssessments) {
            return response
        }
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
            if evaluateTrade(
                offer: offer, receiver: player, state: state,
                assessments: &assessments, recordingAssessments: recordingAssessments
            ) {
                consider(
                    .respondToTrade(offerID: offer.id, accept: true),
                    score: weights.acceptTradeMoveBase
                        + personality.tradeWillingness * weights.acceptTradeMoveWillingnessScale
                )
            }
        }

        // Playing an owned dev card (knight/road building/year of
        // plenty/monopoly) never competes for the same resources as a build,
        // so it's always worth weighing independently; aggressive bots lean
        // into it harder (mostly via knight plays).
        consider(
            DevCardHeuristics.choosePlay(state: state, player: player, personality: personality, weights: weights),
            score: weights.playDevCardMoveBase + personality.aggressiveness * weights.playDevCardMoveAggressionScale
        )

        // Deploying spends cards already paid for, so like playing a dev card
        // it never competes with a build for resources.
        consider(
            ConquestHeuristics.chooseDeploy(state: state, player: player, legal: legal),
            score: weights.playDevCardMoveBase
        )

        let buildMove = BuildPlanner.chooseBuild(
            for: state, player: player, personality: personality, rng: &rng, weights: weights
        )
        consider(buildMove, score: weights.buildMoveScore)
        if ConquestHeuristics.shouldBuyAheadOfBuilding(armyBuying, state: state, player: player) {
            consider(.buyArmyCard, score: weights.buildMoveScore + 0.1)
        }

        // Buying/proposing a trade are fallbacks considered only once a
        // build wasn't clearly worth it (buying is already scored as part of
        // `BuildPlanner`'s own candidates when it *is* worthwhile).
        if buildMove == nil {
            // In Expanded, BuildPlanner may deliberately reject a card while
            // the bot establishes its production base. The older fallback
            // would immediately buy that same card anyway, nullifying the
            // mode-aware score. Classic retains its historical fallback.
            if state.mode == .classic, DevCardHeuristics.shouldBuyDevCard(state: state, player: player) {
                consider(
                    .buyDevCard,
                    score: weights.buyDevCardMoveBase
                        + personality.aggressiveness * weights.buyDevCardMoveAggressionScale
                )
            }
            if armyBuying == .idle, ConquestHeuristics.shouldBuyArmyCard(state: state, player: player) {
                consider(.buyArmyCard, score: weights.buyDevCardMoveBase)
            }
            // Fall back to the bank/port when no build is affordable yet and
            // no other player's offering a good deal - previously bots only
            // ever traded with each other, so a bot sitting on a lopsided
            // surplus (e.g. plenty of brick, zero wool) with no willing
            // trade partner would just stall every turn instead of
            // converting what it already has.
            if let bankTrade = TradeHeuristics.bestBankTrade(
                state: state, player: player, personality: personality, weights: weights
            ) {
                consider(
                    .bankTrade(give: [bankTrade.give: bankTrade.rate], get: [bankTrade.get: 1]),
                    score: weights.bankTradeMoveBase + personality.expansionBias * weights.bankTradeMoveExpansionScale
                )
            }
            for offer in TradeHeuristics.proposeTrades(
                state: state, player: player, personality: personality, weights: weights
            ) {
                consider(
                    .proposeTrade(offer),
                    score: weights.proposeTradeMoveBase
                        + personality.tradeWillingness * weights.proposeTradeMoveWillingnessScale
                )
            }

            // Lowest-priority fallback: actively decline a pending offer
            // this bot doesn't want, once nothing more valuable is
            // available. `Trading.respond` is the only thing that ever
            // removes an offer from `state.pendingTradeOffers` - an offer
            // nobody wants and nobody explicitly rejects would otherwise sit
            // there for the rest of the game (surviving every `endTurn`),
            // so a bot that's otherwise out of better moves cleans one up
            // rather than reaching `.endTurn` with it still pending.
            for offer in state.pendingTradeOffers where offer.from != player {
                if !evaluateTrade(
                    offer: offer, receiver: player, state: state,
                    assessments: &assessments, recordingAssessments: recordingAssessments
                ) {
                    consider(.respondToTrade(offerID: offer.id, accept: false), score: weights.declineTradeMoveScore)
                }
            }
        }

        return best?.move ?? .endTurn
    }

    /// Answers an out-of-turn negotiation whose action mask contains only
    /// responses. Build planning still sees the full position and may find an
    /// affordable build, but that build is intentionally not available while
    /// another player's offer is being resolved.
    private func decideScopedTradeResponse(
        legal: [GameMove],
        state: GameState,
        player: PlayerID,
        assessments: inout [TradeAssessment],
        recordingAssessments: Bool
    ) -> GameMove? {
        guard legal.allSatisfy({ if case .respondToTrade = $0 { true } else { false } }) else { return nil }
        for offer in state.pendingTradeOffers where offer.from != player {
            let accept = GameMove.respondToTrade(offerID: offer.id, accept: true)
            if legal.contains(accept), evaluateTrade(
                offer: offer, receiver: player, state: state,
                assessments: &assessments, recordingAssessments: recordingAssessments
            ) {
                return accept
            }
        }
        return legal.first { if case .respondToTrade(_, false) = $0 { true } else { false } }
    }

    /// Records the same scalar result whose boolean controls the branch;
    /// diagnostics never trigger a second scoring pass or retain global state.
    private func evaluateTrade(
        offer: TradeOffer, receiver: PlayerID, state: GameState,
        assessments: inout [TradeAssessment], recordingAssessments: Bool
    ) -> Bool {
        guard let assessment = TradeHeuristics.assessment(
            offer: offer, receiver: receiver, state: state, personality: personality, weights: weights,
            includeContributions: recordingAssessments
        ) else { return false }
        if recordingAssessments { assessments.append(assessment) }
        return assessment.accepted
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
            case (.buyArmyCard, .buyArmyCard): return candidate
            case (.deployArmy, .deployArmy) where desired == candidate: return candidate
            case (.endTurn, .endTurn): return candidate
            default: continue
            }
        }
        return nil
    }
}
