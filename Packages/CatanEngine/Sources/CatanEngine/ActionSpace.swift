/// A fixed, ordered numbering of every move the game can express.
///
/// ## Why this exists
/// A `GameMove` is an enum with associated values - the right shape for the
/// rules, and the wrong shape for anything that has to *count* moves. A
/// trainer needs a move to be an integer so a policy can put a probability on
/// it; a language model needs it to be a short token rather than a paragraph;
/// a search needs to index a table by it. All three need the numbering to mean
/// the same thing every time, on every machine.
///
/// So: `index(of:)` and `move(at:)` are inverses, and `mask(for:)` marks which
/// indices are legal right now. That is the whole interface. Nothing about it
/// commits to how an agent is eventually built.
///
/// ## The ordering is canonical, and that is load-bearing
/// Vertices, edges and tiles are sorted once at construction, and must stay in
/// step with `StateEncoding.BoardIndex`, which sorts the same three the same
/// way. They briefly did not: tiles here were taken in `board.tiles` order (the
/// generator's spiral) while the encoder sorted them, so all 19 hexes disagreed
/// and "robber to tile k" named a different hex from tile slot k of the feature
/// vector - the exact pairing a trainer makes. `ActionSpaceTests` now pins the
/// agreement. `Board` stores
/// vertices and edges in `Set`s, and Swift seeds set iteration order
/// per process - so a numbering from iteration order would mean something
/// different on every launch, and a model trained on Monday would read
/// Tuesday's board through a permuted lens. This repo has been bitten by that
/// class of bug four separate times; see the determinism section of
/// `.claude/rules/swift.md`.
///
/// ## Size, and the obvious optimisation
/// On the standard board this is **9,335** indices. It is worth knowing where
/// they go, because two cases are 87% of it:
///
/// | segment | size | share |
/// |---|---|---|
/// | `playRoadBuilding` (ordered edge pairs) | 5,112 | 55% |
/// | `discard` (multisets up to `maxDiscardCards`) | 3,002 | 32% |
/// | everything else combined | 1,221 | 13% |
///
/// Both are compound actions flattened into one index. If that ratio ever
/// matters - and for a learned policy it probably will - the fix is to
/// decompose them into sequences of atomic choices: road building becomes two
/// consecutive single-edge picks, discarding becomes one card at a time. That
/// takes the space to roughly 1,200 and costs a change to `GameMove` itself,
/// which is why it is written down here rather than done now. A flat 9,335 is
/// a perfectly ordinary policy-head width in the meantime.
///
/// ## Not the same numbering as a prompt's move list
/// `StateEncoding.promptDescription` also numbers moves, but 0-based *within
/// one observation's* `legalMoves` - single digits, meaningless elsewhere.
/// This numbering is global and permanent. Feeding a number from one into the
/// other yields a legal-looking move nobody chose; cross over via
/// `observation.legalMoves[n]` and `index(of:pendingOffers:)`.
///
/// ## Two indices depend on state, deliberately
/// `respondToTrade` names an offer by `UUID`, which cannot be numbered in
/// advance, so it is indexed by *position* in `pendingTradeOffers`. Pass the
/// same list to `index(of:)` and `move(at:)` or they will not agree. Anything
/// past `maxIndexedPendingOffers` is unrepresentable and returns `nil` rather
/// than silently aliasing onto another offer.
public struct ActionSpace: Sendable {

    /// Bump when the numbering changes in any way that moves an existing
    /// index. A model trained against one numbering cannot read another, and
    /// the failure is silent: it plays badly rather than erroring. Anything
    /// that persists a trained artifact must record this and refuse a
    /// mismatch.
    public static let layoutVersion = 2

    /// Largest discard this numbering can express. A player discards half of
    /// what they hold above seven, so reaching eleven means holding
    /// twenty-two cards - possible, vanishingly rare, and not worth tripling
    /// the segment for. Beyond it, `index(of:)` returns `nil` rather than
    /// pretending.
    public static let maxDiscardCards = 10

    /// How many pending offers can be named by index.
    ///
    /// This was 16, on the stated grounds that "offers no longer outlive the
    /// turn that made them, so the list is short". That premise is false and
    /// was never measured: `RulesEngine.tradeProposals` enumerates up to 80
    /// candidates per call, `Trading.proposeTrade` appends with no cap, and the
    /// list is only cleared at `endTurn`. Over twelve seeded games of
    /// random-legal play `pendingTradeOffers` reached **152 within a single
    /// turn**, so roughly a tenth of the responses a policy could legally make
    /// had no index and were dropped from the mask with no signal.
    ///
    /// 256 covers that with margin and costs 480 indices, which is under 6% of
    /// the space. `mask(for:)` now traps rather than dropping, so if a position
    /// ever exceeds this it fails loudly instead of quietly narrowing what the
    /// agent believes it may do.
    public static let maxIndexedPendingOffers = 256

    // Canonical orderings, sorted once.
    private let vertices: [VertexID]
    private let edges: [EdgeID]
    private let tiles: [HexCoordinate]
    /// Every discard multiset, in a fixed order, sizes 1...`maxDiscardCards`.
    private let discards: [[Resource: Int]]

    private let offsets: [Int]
    /// Total number of indices. `0..<size` is the whole action space.
    public let size: Int

    /// Segment order. Changing this changes every index after it, which is
    /// what `layoutVersion` is for.
    private enum Segment: Int, CaseIterable {
        case placeInitialSettlement, placeInitialRoad
        case rollDice, buildRoad, buildSettlement, buildCity, buyDevCard
        case playKnight, playRoadBuilding, playYearOfPlenty, playMonopoly
        case moveRobber, discard, bankTrade, proposeTrade, respondToTrade, endTurn
    }

    /// Seats at the table. Part of the numbering, because the robber segment
    /// is sized by how many players there are to steal from.
    public let playerCount: Int

    public init(board: Board, playerCount: Int = 4) {
        self.playerCount = playerCount
        vertices = board.onBoardVertices.sorted()
        edges = board.onBoardEdges.sorted()
        tiles = board.tiles.map(\.coordinate).sorted()
        discards = Self.allDiscards(upTo: Self.maxDiscardCards)

        let victimSlots = 1 + playerCount
        let resources = Resource.allCases.count
        let sizes: [Int] = [
            vertices.count,                          // placeInitialSettlement
            edges.count,                             // placeInitialRoad
            1,                                       // rollDice
            edges.count,                             // buildRoad
            vertices.count,                          // buildSettlement
            vertices.count,                          // buildCity
            1,                                       // buyDevCard
            tiles.count * victimSlots,               // playKnight
            edges.count * max(edges.count - 1, 0),   // playRoadBuilding, ordered pairs
            resources * resources,                   // playYearOfPlenty
            resources,                               // playMonopoly
            tiles.count * victimSlots,               // moveRobber
            discards.count,                          // discard
            resources * (resources - 1) * Self.bankRates.count,
            resources * (resources - 1)
                * RulesEngine.maxGenerousGiveQuantity * RulesEngine.maxEnumeratedTradeQuantity,
            Self.maxIndexedPendingOffers * 2,        // respondToTrade
            1,                                       // endTurn
        ]
        var running = 0
        var computed: [Int] = []
        for segmentSize in sizes {
            computed.append(running)
            running += segmentSize
        }
        offsets = computed
        size = running
    }

    /// The bank rates a trade can use. Which one applies is a property of the
    /// player's ports, so all three are numbered and the mask decides.
    static let bankRates = [2, 3, 4]

    // MARK: - Encoding

    /// The index for `move`, or `nil` if this numbering cannot express it -
    /// a discard larger than `maxDiscardCards`, or a response to an offer past
    /// `maxIndexedPendingOffers`.
    public func index(of move: GameMove, pendingOffers: [TradeOffer] = []) -> Int? {
        switch move {
        case .placeInitialSettlement(let vertex):
            return offset(.placeInitialSettlement, vertices.firstIndex(of: vertex))
        case .placeInitialRoad(let edge):
            return offset(.placeInitialRoad, edges.firstIndex(of: edge))
        case .rollDice:
            return offsets[Segment.rollDice.rawValue]
        case .buildRoad(let edge):
            return offset(.buildRoad, edges.firstIndex(of: edge))
        case .buildSettlement(let vertex):
            return offset(.buildSettlement, vertices.firstIndex(of: vertex))
        case .buildCity(let vertex):
            return offset(.buildCity, vertices.firstIndex(of: vertex))
        case .buyDevCard:
            return offsets[Segment.buyDevCard.rawValue]
        case .playKnight(let tile, let victim):
            return offset(.playKnight, robberSlot(tile: tile, victim: victim))
        case .playRoadBuilding(let first, let second):
            return offset(.playRoadBuilding, edgePairSlot(first, second))
        case .playYearOfPlenty(let first, let second):
            return offset(.playYearOfPlenty, resourceIndex(first) * Resource.allCases.count + resourceIndex(second))
        case .playMonopoly(let resource):
            return offset(.playMonopoly, resourceIndex(resource))
        case .moveRobber(let tile, let victim):
            return offset(.moveRobber, robberSlot(tile: tile, victim: victim))
        case .discard(let amounts):
            return offset(.discard, discards.firstIndex(of: amounts.filter { $0.value > 0 }))
        case .bankTrade(let give, let get):
            return offset(.bankTrade, bankTradeSlot(give: give, get: get))
        case .proposeTrade(let offer):
            return offset(.proposeTrade, proposeSlot(give: offer.give, want: offer.want))
        case .respondToTrade(let offerID, let accept):
            guard let position = pendingOffers.firstIndex(where: { $0.id == offerID }),
                  position < Self.maxIndexedPendingOffers else { return nil }
            return offset(.respondToTrade, position * 2 + (accept ? 0 : 1))
        case .endTurn:
            return offsets[Segment.endTurn.rawValue]
        }
    }

    // MARK: - Decoding

    /// The move at `index`, or `nil` if the index is out of range or names a
    /// pending offer that does not exist.
    public func move(at index: Int, pendingOffers: [TradeOffer] = []) -> GameMove? {
        guard index >= 0, index < size, let segment = segment(containing: index) else { return nil }
        let local = index - offsets[segment.rawValue]

        switch segment {
        case .placeInitialSettlement: return .placeInitialSettlement(vertices[local])
        case .placeInitialRoad: return .placeInitialRoad(edges[local])
        case .rollDice: return .rollDice
        case .buildRoad: return .buildRoad(edges[local])
        case .buildSettlement: return .buildSettlement(vertices[local])
        case .buildCity: return .buildCity(vertices[local])
        case .buyDevCard: return .buyDevCard
        case .playKnight:
            let (tile, victim) = robberSlot(local)
            return .playKnight(moveRobberTo: tile, stealFrom: victim)
        case .playRoadBuilding:
            let (first, second) = edgePair(local)
            return .playRoadBuilding(first, second)
        case .playYearOfPlenty:
            let count = Resource.allCases.count
            return .playYearOfPlenty(Resource.allCases[local / count], Resource.allCases[local % count])
        case .playMonopoly: return .playMonopoly(Resource.allCases[local])
        case .moveRobber:
            let (tile, victim) = robberSlot(local)
            return .moveRobber(tile, stealFrom: victim)
        case .discard: return .discard(discards[local])
        case .bankTrade:
            let (give, get) = bankTrade(local)
            return .bankTrade(give: give, get: get)
        case .proposeTrade:
            let (give, want) = proposal(local)
            // The proposer is not part of the numbering - it is always the
            // seat being asked to move, which the caller knows and the index
            // would only duplicate.
            return .proposeTrade(TradeOffer.enumerated(from: PlayerID(index: 0), give: give, want: want))
        case .respondToTrade:
            let position = local / 2
            guard position < pendingOffers.count else { return nil }
            return .respondToTrade(offerID: pendingOffers[position].id, accept: local % 2 == 0)
        case .endTurn: return .endTurn
        }
    }

    /// Which indices are legal for the observing seat right now.
    ///
    /// Always `size` long, so a policy's output can be masked by elementwise
    /// multiplication without any reshaping.
    public func mask(for observation: GameObservation) -> [Bool] {
        var mask = [Bool](repeating: false, count: size)
        for move in observation.legalMoves {
            // `index(of:)` refuses rather than aliases, and this used to drop
            // that refusal on the floor - a legal move simply went unmarked.
            // The worst case is not a slightly narrow mask: if EVERY legal move
            // is unrepresentable the mask comes back all-false, and a policy
            // head then softmaxes a row of -inf into NaN, or picks uniformly
            // among moves that are all illegal. Nothing reports either.
            //
            // A trap is the right answer because this cannot be recovered from
            // in the place it is noticed. It is also reachable only through a
            // cap being wrong, which is a bug to fix rather than a position to
            // tolerate - so failing here says exactly which cap to raise.
            guard let index = index(of: move, pendingOffers: observation.state.pendingTradeOffers) else {
                preconditionFailure(
                    "no index for legal move \(move); the action space cannot express a position the "
                        + "rules allow. Raise maxDiscardCards (currently \(Self.maxDiscardCards)) or "
                        + "maxIndexedPendingOffers (currently \(Self.maxIndexedPendingOffers)) and bump layoutVersion.")
            }
            mask[index] = true
        }
        return mask
    }

    // MARK: - Segment arithmetic

    private func offset(_ segment: Segment, _ local: Int?) -> Int? {
        guard let local else { return nil }
        return offsets[segment.rawValue] + local
    }

    private func segment(containing index: Int) -> Segment? {
        // Small and fixed, so a linear scan from the end is both simplest and
        // fastest.
        Segment.allCases.reversed().first { offsets[$0.rawValue] <= index }
    }

    private func resourceIndex(_ resource: Resource) -> Int {
        Resource.allCases.firstIndex(of: resource)!
    }

    // MARK: - Compound slots

    private func robberSlot(tile: HexCoordinate, victim: PlayerID?) -> Int? {
        guard let tileIndex = tiles.firstIndex(of: tile) else { return nil }
        let slots = 1 + playerCount
        return tileIndex * slots + (victim.map { $0.index + 1 } ?? 0)
    }

    private func robberSlot(_ local: Int) -> (HexCoordinate, PlayerID?) {
        let slots = 1 + playerCount
        let victimSlot = local % slots
        return (tiles[local / slots], victimSlot == 0 ? nil : PlayerID(index: victimSlot - 1))
    }

    /// Ordered edge pairs, excluding a pair of the same edge - road building
    /// places two *different* roads.
    private func edgePairSlot(_ first: EdgeID, _ second: EdgeID) -> Int? {
        guard let a = edges.firstIndex(of: first), let b = edges.firstIndex(of: second), a != b else { return nil }
        return a * (edges.count - 1) + (b < a ? b : b - 1)
    }

    private func edgePair(_ local: Int) -> (EdgeID, EdgeID) {
        let span = edges.count - 1
        let a = local / span
        let raw = local % span
        return (edges[a], edges[raw < a ? raw : raw + 1])
    }

    private func bankTradeSlot(give: [Resource: Int], get: [Resource: Int]) -> Int? {
        guard give.count == 1, get.count == 1,
              let giveEntry = give.first, let getEntry = get.first,
              getEntry.value == 1, giveEntry.key != getEntry.key,
              let rateIndex = Self.bankRates.firstIndex(of: giveEntry.value) else { return nil }
        return (resourceIndex(giveEntry.key) * (Resource.allCases.count - 1)
            + otherIndex(getEntry.key, excluding: giveEntry.key)) * Self.bankRates.count + rateIndex
    }

    private func bankTrade(_ local: Int) -> ([Resource: Int], [Resource: Int]) {
        let rate = Self.bankRates[local % Self.bankRates.count]
        let pair = local / Self.bankRates.count
        let span = Resource.allCases.count - 1
        let give = Resource.allCases[pair / span]
        return ([give: rate], [other(pair % span, excluding: give): 1])
    }

    private func proposeSlot(give: [Resource: Int], want: [Resource: Int]) -> Int? {
        let giveQuantity = RulesEngine.maxGenerousGiveQuantity
        let wantQuantity = RulesEngine.maxEnumeratedTradeQuantity
        guard give.count == 1, want.count == 1,
              let giveEntry = give.first, let wantEntry = want.first,
              giveEntry.key != wantEntry.key,
              (1...giveQuantity).contains(giveEntry.value), (1...wantQuantity).contains(wantEntry.value)
        else { return nil }
        let pair = resourceIndex(giveEntry.key) * (Resource.allCases.count - 1)
            + otherIndex(wantEntry.key, excluding: giveEntry.key)
        return (pair * giveQuantity + (giveEntry.value - 1)) * wantQuantity + (wantEntry.value - 1)
    }

    private func proposal(_ local: Int) -> ([Resource: Int], [Resource: Int]) {
        let giveQuantity = RulesEngine.maxGenerousGiveQuantity
        let wantQuantity = RulesEngine.maxEnumeratedTradeQuantity
        let wantCount = local % wantQuantity + 1
        let giveCount = (local / wantQuantity) % giveQuantity + 1
        let pair = local / (giveQuantity * wantQuantity)
        let span = Resource.allCases.count - 1
        let give = Resource.allCases[pair / span]
        return ([give: giveCount], [other(pair % span, excluding: give): wantCount])
    }

    /// Position of `resource` among the resources that are not `excluded`.
    private func otherIndex(_ resource: Resource, excluding excluded: Resource) -> Int {
        Resource.allCases.filter { $0 != excluded }.firstIndex(of: resource)!
    }

    private func other(_ index: Int, excluding excluded: Resource) -> Resource {
        Resource.allCases.filter { $0 != excluded }[index]
    }

    /// Every discard multiset of size 1...`limit`, in a fixed order.
    private static func allDiscards(upTo limit: Int) -> [[Resource: Int]] {
        var all: [[Resource: Int]] = []
        let resources = Resource.allCases
        func build(_ index: Int, _ remaining: Int, _ current: [Resource: Int]) {
            if index == resources.count {
                if remaining == 0, !current.isEmpty { all.append(current) }
                return
            }
            for take in 0...remaining {
                var next = current
                if take > 0 { next[resources[index]] = take }
                build(index + 1, remaining - take, next)
            }
        }
        for total in 1...limit { build(0, total, [:]) }
        return all
    }
}
