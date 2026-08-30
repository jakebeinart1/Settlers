import Testing
@testable import CatanEngine

/// Proves the action numbering is a bijection, and that it covers what the
/// game actually produces.
///
/// Both halves matter and they fail differently. A numbering that is not
/// invertible corrupts silently - a policy picks index 4,000, the decoder
/// hands back a different move than the encoder meant, and the only symptom is
/// bad play. A numbering that is invertible but incomplete is worse in a
/// quieter way: the moves it cannot express are simply invisible to anything
/// built on it, so an agent never learns they exist.

private let board = BoardGenerator.standard()
private let space = ActionSpace(board: board)

@Test func theSpaceIsTheSizeItClaims() {
    // Recomputed by hand rather than read back from the type, so a change to
    // the segment layout has to be acknowledged here rather than sailing past.
    let vertices = 54, edges = 72, tiles = 19, resources = 5, victimSlots = 5
    let discardMultisets = 3_002   // sizes 1...10 over 5 resource types
    let expected =
        vertices + edges                      // initial placements
        + 1 + edges + vertices + vertices + 1  // roll, build x3, buy
        + tiles * victimSlots                  // knight
        + edges * (edges - 1)                  // road building, ordered pairs
        + resources * resources + resources    // year of plenty, monopoly
        + tiles * victimSlots                  // robber
        + discardMultisets
        + resources * (resources - 1) * ActionSpace.bankRates.count
        + resources * (resources - 1)
            * RulesEngine.maxEnumeratedTradeQuantity * RulesEngine.maxEnumeratedTradeQuantity
        + ActionSpace.maxIndexedPendingOffers * 2
        + 1                                    // endTurn
    #expect(space.size == expected)
    #expect(space.size == 8_815, "if this moved, bump ActionSpace.layoutVersion")
}

@Test func everyIndexRoundTripsBackToItself() {
    // The whole space, one index at a time. `respondToTrade` needs a list of
    // pending offers to name, so supply a full one.
    // Distinct CONTENT for each, not just distinct positions: offer ids are
    // derived from their contents, so sixteen offers that merely differ by
    // proposer would share ids and every lookup would find the first.
    let resources = Resource.allCases
    let offers = (0..<ActionSpace.maxIndexedPendingOffers).map { index -> TradeOffer in
        let give = resources[index % resources.count]
        let want = resources[(index / resources.count + 1 + index % resources.count) % resources.count]
        return TradeOffer.enumerated(
            from: PlayerID(index: index % 4),
            give: [give: 1 + index % 2],
            want: [want == give ? resources[(index + 2) % resources.count] : want: 1]
        )
    }
    #expect(Set(offers.map(\.id)).count == offers.count, "the fixture must not contain duplicate offer ids")
    var unmapped: [Int] = []
    for index in 0..<space.size {
        guard let move = space.move(at: index, pendingOffers: offers) else {
            unmapped.append(index)
            continue
        }
        #expect(space.index(of: move, pendingOffers: offers) == index,
                "index \(index) decoded to \(move) which re-encodes elsewhere")
    }
    #expect(unmapped.isEmpty, "every index must name a move; \(unmapped.count) did not")
}

@Test func outOfRangeIndicesAreRejectedRatherThanWrapped() {
    #expect(space.move(at: -1) == nil)
    #expect(space.move(at: space.size) == nil)
    #expect(space.move(at: space.size + 1_000) == nil)
}

@Test func everyLegalMoveInARealGameHasAnIndex() throws {
    // The completeness half. Plays several seeded games with random-legal
    // policies so the walk reaches discards, robber moves, dev cards and
    // trades - not just the opening.
    var checked = 0
    for seed: UInt64 in [1, 2, 3, 4] {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        let liveSpace = ActionSpace(board: state.board)
        var driver = RandomSource(seed: seed &* 17)

        for _ in 0..<600 {
            if case .gameOver = state.phase { break }
            guard let actor = actingPlayer(state) else { break }
            let legal = RulesEngine.legalMoves(for: state, seat: actor)
            guard !legal.isEmpty else { break }

            for move in legal {
                let index = liveSpace.index(of: move, pendingOffers: state.pendingTradeOffers)
                #expect(index != nil, "no index for a legal move: \(move)")
                checked += 1
            }

            guard let move = legal.randomElement(using: &driver) else { break }
            try RulesEngine.apply(move, by: actor, to: &state)
        }
    }
    #expect(checked > 5_000, "the walk should have covered thousands of legal moves, saw \(checked)")
}

@Test func theMaskMarksExactlyTheLegalMoves() throws {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 5), seed: 5)
    let liveSpace = ActionSpace(board: state.board)
    var driver = RandomSource(seed: 5)

    // Walk into the main phase, where the mask is at its most interesting.
    for _ in 0..<200 {
        if case .mainTurn = state.phase { break }
        guard let actor = actingPlayer(state),
              let move = RulesEngine.legalMoves(for: state, seat: actor).randomElement(using: &driver)
        else { break }
        try RulesEngine.apply(move, by: actor, to: &state)
    }

    let actor = try #require(actingPlayer(state))
    let legal = RulesEngine.legalMoves(for: state, seat: actor)
    let observation = GameObservation(seat: actor, state: state, legalMoves: legal)
    let mask = liveSpace.mask(for: observation)

    #expect(mask.count == liveSpace.size, "a mask must be the full width so it can multiply elementwise")
    #expect(mask.filter { $0 }.count == Set(legal.compactMap {
        liveSpace.index(of: $0, pendingOffers: state.pendingTradeOffers)
    }).count)
    for move in legal {
        let index = try #require(liveSpace.index(of: move, pendingOffers: state.pendingTradeOffers))
        #expect(mask[index], "a legal move must be marked legal: \(move)")
    }
}

@Test func aDiscardTooLargeToNumberIsRejectedNotAliased() {
    // Eleven cards is past `maxDiscardCards`. Returning nil is the point:
    // quietly mapping it onto some other multiset's index would corrupt both.
    let huge: [Resource: Int] = [.brick: 6, .ore: 5]
    #expect(huge.values.reduce(0, +) > ActionSpace.maxDiscardCards)
    #expect(space.index(of: .discard(huge)) == nil)

    // And one that fits is fine.
    #expect(space.index(of: .discard([.brick: 3, .ore: 2])) != nil)
}

@Test func aResponseToAnUnknownOfferHasNoIndex() {
    let offer = TradeOffer.enumerated(from: PlayerID(index: 1), give: [.wool: 1], want: [.ore: 1])
    // Not in the supplied list, so it cannot be named by position.
    #expect(space.index(of: .respondToTrade(offerID: offer.id, accept: true), pendingOffers: []) == nil)
    #expect(space.index(of: .respondToTrade(offerID: offer.id, accept: true), pendingOffers: [offer]) != nil)
}

@Test func theNumberingDoesNotDependOnHowTheBoardWasBuilt() {
    // The failure this guards is subtle: `Board` holds vertices and edges in
    // `Set`s, and Swift seeds set iteration order per process, so a numbering
    // taken from iteration order would differ between launches - and a model
    // trained on one would read the other through a permuted lens.
    let first = ActionSpace(board: BoardGenerator.standard())
    let second = ActionSpace(board: BoardGenerator.standard())
    #expect(first.size == second.size)
    for index in stride(from: 0, to: first.size, by: 37) {
        #expect(first.move(at: index) == second.move(at: index), "index \(index) means two different things")
    }
}
