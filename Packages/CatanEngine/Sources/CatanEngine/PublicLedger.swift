/// What one observer may legitimately believe about every seat's hand.
///
/// ## Why a ledger instead of reading `state.players[i].resources`
/// `GameObservation.state` is the whole `GameState`, so a policy *can* read
/// every opponent's exact hand - and the shipping heuristic does, in three
/// places (Monopoly targeting, trade evaluation, threat scoring). Strength
/// measured against a bot with that access is partly a measurement of the
/// access. The planner consumes this type instead, so the constraint holds by
/// construction rather than by discipline.
///
/// ## What it can and cannot know
/// Card *counts* are public at a real table and are tracked exactly wherever
/// the event stream allows. Card *identities* are known only where a public
/// event names them: roll payouts, build and purchase costs, bank and port
/// trades, Year of Plenty, Monopoly, and the terms of an accepted player trade.
/// Steals, development-card faces, and cards spent out of an already-uncertain
/// pool are genuinely unknown and are modelled as such.
///
/// ## The two bounds, and why they can loosen
/// `known` is a floor - resources this seat certainly holds - and `maxTotal` is
/// a ceiling on hand size. Every fold keeps `sum(known) <= maxTotal`. A steal
/// removes a card of unknown identity, which can force the floor down without
/// telling us where; when that happens the floor is lowered in
/// `Resource.allCases` order. That makes the belief know *less* than the truth,
/// never more, which is the only direction that is safe here. Doing it in a
/// fixed order rather than by picking a "likely" resource keeps the fold a pure
/// function of the event sequence, which the determinism invariants require.
public struct PublicLedger: Codable, Sendable, Equatable {

    /// One seat's believed holdings, from the owning ledger's point of view.
    public struct SeatBelief: Codable, Sendable, Equatable {
        /// Resources this seat certainly holds. A floor, never an estimate.
        ///
        /// Encoded through `knownPairs` below for the same per-process ordering
        /// reason the seat map is.
        public var known: [Resource: Int]
        /// Upper bound on how many resource cards this seat holds.
        public var maxTotal: Int
        /// Development cards held, bought-but-unplayable ones included. The
        /// count is public; the faces are not.
        public var devCardCount: Int

        public init(known: [Resource: Int] = [:], maxTotal: Int = 0, devCardCount: Int = 0) {
            self.known = known
            self.maxTotal = maxTotal
            self.devCardCount = devCardCount
        }

        private enum CodingKeys: String, CodingKey {
            case known, maxTotal, devCardCount
        }

        private struct ResourceCount: Codable, Sendable {
            let resource: Resource
            let count: Int
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(
                Resource.allCases.compactMap { resource -> ResourceCount? in
                    guard let count = known[resource], count != 0 else { return nil }
                    return ResourceCount(resource: resource, count: count)
                },
                forKey: .known
            )
            try container.encode(maxTotal, forKey: .maxTotal)
            try container.encode(devCardCount, forKey: .devCardCount)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let pairs = try container.decode([ResourceCount].self, forKey: .known)
            known = Dictionary(uniqueKeysWithValues: pairs.map { ($0.resource, $0.count) })
            maxTotal = try container.decode(Int.self, forKey: .maxTotal)
            devCardCount = try container.decode(Int.self, forKey: .devCardCount)
        }

        /// Sets the floor for `resource`, storing nothing when it reaches zero.
        ///
        /// ## Why absence rather than a stored zero
        /// Every read here is `known[resource] ?? 0`, so an absent key and a
        /// stored zero already mean the same thing - but only to this type.
        /// They do not mean the same thing to `Equatable`, and they did not
        /// mean the same thing to `Codable`: `encode` skips zero counts, so a
        /// belief carrying one round-tripped to a belief without one and
        /// compared unequal to itself.
        ///
        /// That broke `aFullyDeltaCommittedMatchStillPassesAColdFullReplay`,
        /// which reloads a checkpoint and requires it to equal the document
        /// that was written. `debit`, `shrink` and `normalise` all spend a
        /// floor down to zero, so an ordinary game reached the broken state
        /// within a few moves. Keeping one canonical spelling in memory is
        /// what makes the encoded bytes, the equality and the reload agree.
        mutating func setKnown(_ resource: Resource, to count: Int) {
            if count > 0 {
                known[resource] = count
            } else {
                known.removeValue(forKey: resource)
            }
        }

        /// Cards held whose identity this ledger cannot pin down.
        public var uncertain: Int { max(0, maxTotal - knownTotal) }

        public var knownTotal: Int { known.values.reduce(0, +) }

        /// How many of `resource` this seat is believed to hold.
        ///
        /// The floor plus an even share of the uncertain remainder: a seat
        /// holding two known ore and three unknown cards is treated as holding
        /// more ore than one holding two known ore and nothing else, because it
        /// is. Deliberately not a probability - the planner needs an orderable
        /// quantity, and a uniform split over five resources is the honest
        /// prior when no event has narrowed it.
        public func believedHolding(of resource: Resource) -> Double {
            Double(known[resource] ?? 0) + Double(uncertain) / Double(Resource.allCases.count)
        }
    }

    /// The seat this ledger belongs to. Its own entry is exact, because a seat
    /// sees its own hand.
    public let observer: PlayerID
    public private(set) var seats: [PlayerID: SeatBelief]

    public init(observer: PlayerID, seats: [PlayerID: SeatBelief] = [:]) {
        self.observer = observer
        self.seats = seats
    }

    // MARK: - Codable

    /// Encoded as a seat-ordered array, not as the dictionary it is stored in.
    ///
    /// ## Why this is hand-written
    /// Swift encodes a `Dictionary` whose key is neither `String` nor `Int` as
    /// an **unkeyed array of alternating keys and values, in the dictionary's
    /// own iteration order** - and that order is seeded per process. A ledger
    /// written by one process and one written by another therefore serialise
    /// the same beliefs in a different order, and any consumer comparing the
    /// two sees a difference that is not there.
    ///
    /// That is not hypothetical. It broke
    /// `test_separate_process_traces_match_semantically_including_rng`, which
    /// replays a seed in two processes and compares the traces: record 3 came
    /// back with `observer: 2` from one run and `observer: 1` from the other,
    /// while the games themselves were identical move for move. Sorting the
    /// seats on the way out makes the bytes a function of the beliefs rather
    /// than of the hash seed.
    private enum CodingKeys: String, CodingKey {
        case observer, seats
    }

    private struct SeatEntry: Codable, Sendable {
        let seat: PlayerID
        let belief: SeatBelief
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observer, forKey: .observer)
        try container.encode(
            seats.keys.sorted().map { SeatEntry(seat: $0, belief: seats[$0] ?? SeatBelief()) },
            forKey: .seats
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        observer = try container.decode(PlayerID.self, forKey: .observer)
        let entries = try container.decode([SeatEntry].self, forKey: .seats)
        seats = Dictionary(uniqueKeysWithValues: entries.map { ($0.seat, $0.belief) })
    }

    public func belief(of seat: PlayerID) -> SeatBelief {
        seats[seat] ?? SeatBelief()
    }

    /// A ledger that knows only what the current position shows, with no event
    /// history behind it.
    ///
    /// Used when a game is resumed from a checkpoint written before ledgers
    /// were persisted, and by callers that have no event stream. Hand sizes are
    /// exact because they are public; composition is unknown for every seat but
    /// the observer, whose own hand it reads directly. That is a weaker belief
    /// than a counted one and never a wrong one.
    public static func fromPositionAlone(_ state: GameState, observer: PlayerID) -> PublicLedger {
        var seats: [PlayerID: SeatBelief] = [:]
        for player in state.players {
            let handSize = player.resources.values.reduce(0, +)
            seats[player.id] = SeatBelief(
                // Match reconcileObserverHand's canonical form: encoding omits
                // zeros, so keeping them here would change checkpoint equality.
                known: player.id == observer ? player.resources.filter { $0.value > 0 } : [:],
                maxTotal: handSize,
                devCardCount: player.devCards.count
            )
        }
        return PublicLedger(observer: observer, seats: seats)
    }

    /// Replaces the observer's own entry with the truth.
    ///
    /// A seat sees its own hand exactly, so this leaks nothing - and it makes
    /// the ledger self-healing. A fold that drifts for the observer (an
    /// approximation in a hypothetical evaluation, a resumed game whose
    /// history is gone) is corrected on the next decision rather than
    /// compounding for the rest of the match.
    public mutating func reconcileObserverHand(from state: GameState) {
        guard let me = state.players.first(where: { $0.id == observer }) else { return }
        seats[observer] = SeatBelief(
            known: me.resources.filter { $0.value > 0 },
            maxTotal: me.resources.values.reduce(0, +),
            devCardCount: me.devCards.count
        )
    }

    // MARK: - Folding events

    /// Folds one already-masked event, using the state as it was *before* the
    /// event was applied.
    ///
    /// `stateBefore` is required rather than convenient: a roll's payout
    /// depends on the robber's position and the bank's stock at the moment of
    /// the roll, and both can be changed by the very move being folded.
    public mutating func apply(_ event: GameEvent, stateBefore state: GameState) {
        switch event {
        case .rolled(_, let total):
            for (playerIndex, gains) in MainPhase.payouts(for: total, in: state) {
                credit(state.players[playerIndex].id, gains)
            }

        case .placedInitialSettlement:
            // The second settlement grants its adjacent tiles' resources in
            // full view of the table, but the event does not name the vertex
            // and the newest settlement cannot be recovered from one state.
            // `GameSession` diffs the two states and calls
            // `creditInitialGrant(to:at:board:)` directly.
            break

        case .placedInitialRoad, .rejectedTrade, .endedTurn, .gameWon:
            break

        case .builtRoad(let seat):
            debit(seat, Building.roadCost)
        case .builtSettlement(let seat):
            debit(seat, Building.settlementCost)
        case .builtCity(let seat):
            debit(seat, Building.cityCost)

        case .boughtDevCard(let seat):
            debit(seat, Building.devCardCost)
            seats[seat, default: SeatBelief()].devCardCount += 1

        case .boughtArmyCard(let seat):
            debit(seat, Conquest.armyCardCost)

        case .deployedArmy:
            break

        case .discarded(let seat, let count):
            // Which cards went is not public; only that `count` of them did.
            shrink(seat, by: count)

        case .movedRobber(_, let victim, let stolen), .playedKnight(_, let victim, let stolen):
            if case .playedKnight(let thief, _, _) = event {
                seats[thief, default: SeatBelief()].devCardCount -= 1
            }
            guard let victim else { break }
            // `stolen` survives masking only for the two seats entitled to it.
            if let stolen {
                debit(victim, [stolen: 1])
                if case .movedRobber(let thief, _, _) = event { credit(thief, [stolen: 1]) }
                if case .playedKnight(let thief, _, _) = event { credit(thief, [stolen: 1]) }
            } else {
                shrink(victim, by: 1)
                if case .movedRobber(let thief, _, _) = event { grow(thief, by: 1) }
                if case .playedKnight(let thief, _, _) = event { grow(thief, by: 1) }
            }

        case .playedRoadBuilding(let seat):
            seats[seat, default: SeatBelief()].devCardCount -= 1

        case .playedYearOfPlenty(let seat, let taken):
            seats[seat, default: SeatBelief()].devCardCount -= 1
            credit(seat, taken)

        case .playedMonopoly(let seat, let resource, let gained):
            seats[seat, default: SeatBelief()].devCardCount -= 1
            credit(seat, [resource: gained])
            for other in seats.keys.sorted() where other != seat {
                // Everyone else is now certainly empty of that resource. What
                // we knew they held is exactly what they lost; anything they
                // held inside their uncertain pool is lost too, but we cannot
                // say how much, so the ceiling only drops by what was certain.
                guard var belief = seats[other] else { continue }
                let certainLoss = belief.known[resource] ?? 0
                belief.setKnown(resource, to: 0)
                belief.maxTotal = max(0, belief.maxTotal - certainLoss)
                seats[other] = belief
            }

        case .tradedWithBank(let seat, let gave, let got):
            debit(seat, gave)
            credit(seat, got)

        case .acceptedTrade(let accepter, let proposer, let gave, let got):
            // `gave` is what the accepter handed over; `got` is what it
            // received. The proposer's side is the mirror image.
            debit(accepter, gave)
            credit(accepter, got)
            debit(proposer, got)
            credit(proposer, gave)

        case .proposedTrade:
            // A proposal moves no cards. It is evidence about intent, which
            // the belief model deliberately does not encode.
            break
        }
        normalise()
    }

    /// Credits the adjacent production of a second-placement settlement.
    ///
    /// Takes the vertex explicitly. An earlier version guessed it as the
    /// highest-sorted settlement the seat owned, which is not the newest one,
    /// so it credited a different vertex's resources - a floor claiming cards
    /// the seat had never been given. Public information does not mean
    /// inferable from one state.
    public mutating func creditInitialGrant(to seat: PlayerID, at vertex: VertexID, board: Board) {
        var gains: [Resource: Int] = [:]
        for coordinate in board.neighborTiles(of: vertex) {
            guard let tile = board.tiles.first(where: { $0.coordinate == coordinate }),
                  case .resource(let resource) = tile.kind else { continue }
            gains[resource, default: 0] += 1
        }
        credit(seat, gains)
    }

    /// Forces every ceiling to the true hand size.
    ///
    /// Hand *size* is public at a real table - everyone can count the cards in
    /// an opponent's hand - so taking it from the position leaks nothing, and
    /// it makes the ceiling exact rather than merely sound. It also makes the
    /// ledger self-correcting: any fold that under- or over-counts a size is
    /// repaired on the next move instead of drifting for the rest of the game.
    /// The composition floor is left alone, except where it would now exceed
    /// the ceiling.
    public mutating func reconcileHandSizes(from state: GameState) {
        for player in state.players {
            var belief = seats[player.id] ?? SeatBelief()
            belief.maxTotal = player.resources.values.reduce(0, +)
            belief.devCardCount = player.devCards.count
            seats[player.id] = belief
        }
        normalise()
    }

    // MARK: - Bound arithmetic

    private mutating func credit(_ seat: PlayerID, _ amounts: [Resource: Int]) {
        var belief = seats[seat] ?? SeatBelief()
        for resource in Resource.allCases {
            guard let amount = amounts[resource], amount != 0 else { continue }
            belief.setKnown(resource, to: (belief.known[resource] ?? 0) + amount)
            belief.maxTotal += amount
        }
        seats[seat] = belief
    }

    /// Spends a known cost. A seat can only pay a cost it holds, so the floor
    /// drops by the cost - but if the floor did not account for it, the payment
    /// came out of the uncertain pool and only the ceiling moves.
    private mutating func debit(_ seat: PlayerID, _ amounts: [Resource: Int]) {
        var belief = seats[seat] ?? SeatBelief()
        for resource in Resource.allCases {
            guard let amount = amounts[resource], amount != 0 else { continue }
            let certain = belief.known[resource] ?? 0
            belief.setKnown(resource, to: max(0, certain - amount))
            belief.maxTotal = max(0, belief.maxTotal - amount)
        }
        seats[seat] = belief
    }

    /// Removes `count` cards of unknown identity.
    ///
    /// Every resource in the floor drops by `count`, not just the total. A
    /// stolen card could have been any of them, so the only lower bound that
    /// stays true is the one that assumes the worst for each resource
    /// separately. Reducing the total alone looks equivalent and is not: a
    /// belief of one ore and one wool, minus one unknown card, was collapsed
    /// to "certainly one wool" - and the card actually taken was the wool.
    /// That is a ledger claiming a card the seat does not hold, which is the
    /// one direction this type must never fail in.
    private mutating func shrink(_ seat: PlayerID, by count: Int) {
        guard count > 0 else { return }
        var belief = seats[seat] ?? SeatBelief()
        belief.maxTotal = max(0, belief.maxTotal - count)
        for resource in Resource.allCases {
            guard let held = belief.known[resource], held > 0 else { continue }
            belief.setKnown(resource, to: max(0, held - count))
        }
        seats[seat] = belief
    }

    /// Adds `count` cards of unknown identity - the ceiling rises, the floor
    /// does not.
    private mutating func grow(_ seat: PlayerID, by count: Int) {
        var belief = seats[seat] ?? SeatBelief()
        belief.maxTotal += count
        seats[seat] = belief
    }

    /// Restores `sum(known) <= maxTotal`.
    ///
    /// A safety net rather than the mechanism: `shrink` already keeps the
    /// floor sound per resource. This only fires when a ceiling taken from the
    /// position is lower than the floor implies, which means the floor is
    /// already wrong, and lowering it in a fixed order at least keeps the
    /// invariant and the determinism.
    private mutating func normalise() {
        for seat in seats.keys.sorted() {
            guard var belief = seats[seat] else { continue }
            var excess = belief.knownTotal - belief.maxTotal
            guard excess > 0 else { continue }
            for resource in Resource.allCases where excess > 0 {
                let held = belief.known[resource] ?? 0
                let removed = min(held, excess)
                belief.setKnown(resource, to: held - removed)
                excess -= removed
            }
            seats[seat] = belief
        }
    }
}
