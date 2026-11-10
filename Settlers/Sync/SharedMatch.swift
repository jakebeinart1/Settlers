import CatanAI
import CatanEngine
import Foundation

/// One finished, rated game as it travels between phones: who sat where, the
/// opening position, and every move. Nothing derived is sent.
///
/// ## Why no result travels
/// The winner, the stats and therefore the Elo are recomputed by every phone
/// that downloads the game, by replaying it through the rules engine. A
/// record claiming a win its moves do not produce is rejected rather than
/// believed, and a phone can never disagree with another about what a game
/// it has already seen was worth. The engine replays a recorded game exactly
/// (CLAUDE.md, "Determinism invariants"), which is what makes this possible.
///
/// ## What it cannot catch
/// A fabricated game whose every move is legal. Replaying the bots' moves
/// against their policies would catch that and costs a full bot evaluation
/// per move on every phone; it is the upgrade if a ladder is ever gamed.
struct SharedMatch: Codable, Sendable {
    struct Move: Codable, Sendable {
        let player: PlayerID
        let move: GameMove
        /// False for a move the app made for the person (a timeout, Auto
        /// Robber), so a ghost never learns it as theirs. Absent in games
        /// uploaded before 2026-10-24; older phones ignore it.
        var isHumanDecision: Bool?
        /// Older clients ignore this field. Absent legacy payloads keep their
        /// original current-rules verification behavior.
        var rulesVersion: Int?
    }

    /// Bumped when the payload changes shape; a phone skips versions it does
    /// not know rather than misreading them.
    static let currentVersion = 1

    let version: Int
    let match: UUID
    let date: Date
    /// `RatedEntity.key` per seat, in turn order.
    let seats: [String]
    let initialState: GameState
    let moves: [Move]
    /// Set on a rated game its player left unfinished by starting another
    /// (`LiveSync.recordAbandoned`). Rated as a forfeit (`verified`), so a
    /// restart costs the same Elo as a loss. Phones older than 2026-10-26
    /// reject it as unfinished and leave it unrated until they update.
    var abandoned: Bool?
    /// Additive payload metadata; the existing CloudKit asset/schema stays
    /// unchanged. Old payloads are Classic/Standard, as that was the only
    /// scope recorded before personal mode ratings existed.
    var ratingPool: RatingPool?

    enum Rejection: Error, Equatable {
        case unknownVersion(Int)
        case notClassicStandard
        case seatCountMismatch
        /// Exactly one person sits at a rated table, and it is the uploader.
        case personIsNotUploader
        case replayFailed
        case notFinished
        case invalidRatingPool
    }

    /// The per-seat stats this game really produced, or why it is not a
    /// game this ladder counts. `owner` is the CloudKit user id that created
    /// the record, which is the uploader's player id (`PlayerDirectory`).
    ///
    /// The person seat is filed under `owner` whatever it says: only its
    /// creator can write a record, so nobody can post a game as someone else,
    /// and a game posted before player ids existed ("person:Jake") lands on
    /// its uploader's row too.
    func verified(owner: String) throws -> SeatStatsRecord {
        guard version == Self.currentVersion else { throw Rejection.unknownVersion(version) }
        if let ratingPool {
            guard ratingPool.mode == initialState.mode, ratingPool.variant == initialState.variant,
                  ratingPool.mode != .naval || ratingPool.variant == .standard else { throw Rejection.invalidRatingPool }
            let expected = ratingPool.difficulty == .expert ? RatedEntity.expert.key : RatedEntity.classic.key
            guard seats.filter({ !$0.hasPrefix(RatedEntity.personPrefix) }).allSatisfy({ $0 == expected }) else {
                throw Rejection.invalidRatingPool
            }
        } else {
            guard initialState.mode == .classic, initialState.variant == .standard else { throw Rejection.notClassicStandard }
        }
        guard seats.count == initialState.players.count else { throw Rejection.seatCountMismatch }
        guard seats.filter({ $0.hasPrefix(RatedEntity.personPrefix) }).count == 1, !owner.isEmpty else {
            throw Rejection.personIsNotUploader
        }
        try validateReplayInput()
        var stats: [SeatStats]
        do {
            stats = try SeatStats.compute(initial: initialState, moves: moves.map {
                LoggedMove(player: $0.player, move: $0.move, rulesVersion: $0.rulesVersion)
            })
        } catch {
            throw Rejection.replayFailed
        }
        if abandoned == true, !stats.contains(where: \.won) { forfeit(&stats) }
        guard stats.filter(\.won).count == 1 else { throw Rejection.notFinished }
        return SeatStatsRecord(match: match, date: date,
                               seats: zip(seats, stats).map { entity, stats in
                                   SeatStatsRecord.Entry(entity: entity.hasPrefix(RatedEntity.personPrefix)
                                                             ? RatedEntity.person(owner).key : entity, stats: stats)
                               }, ratingPool: ratingPool, abandoned: abandoned)
    }

    /// A downloaded archive can decode even when its indices or quantities
    /// would trap inside rules replay. Check those before running the engine.
    /// A migrated save can start midgame, so an opening phase is not required.
    private func validateReplayInput() throws {
        let state = initialState
        let indices = state.players.indices
        guard GameSetup.supportedPlayerCounts.contains(indices.count),
              state.players.map(\.id.index).elementsEqual(indices),
              state.robberMoverIndex.map(indices.contains) ?? true,
              moves.allSatisfy({ indices.contains($0.player.index) }) else { throw Rejection.replayFailed }
        switch state.phase {
        case .discarding(let pending):
            guard !pending.isEmpty, pending.allSatisfy({ indices.contains($0.index) }) else { throw Rejection.replayFailed }
        case .gameOver:
            // A recording must earn its result during replay. A position
            // that already names a winner has no evidence of how it ended.
            throw Rejection.replayFailed
        default:
            guard state.phase.awaitingSeatIndex.map(indices.contains) == true else { throw Rejection.replayFailed }
        }

        let rules = state.rules
        let validAmounts = { (amounts: [Resource: Int]) in
            amounts.values.allSatisfy { (0...rules.bankPerResource).contains($0) }
        }
        guard validAmounts(state.bank), state.players.allSatisfy({ validAmounts($0.resources) }),
              state.pendingTradeOffers.allSatisfy({ validAmounts($0.give) && validAmounts($0.want) }),
              state.tradesAcceptedThisTurn.values.allSatisfy({ (0...(Int.max / 2)).contains($0) }),
              moves.allSatisfy({ Self.hasSafeResourceAmounts($0.move, checking: validAmounts) }) else {
            throw Rejection.replayFailed
        }
        try Self.validateReplayBoard(state)
    }

    private static func validateReplayBoard(_ state: GameState) throws {
        let shape = state.rules.board
        let coordinates = Set(state.board.tiles.map(\.coordinate))
        let axis = -shape.radius...shape.radius
        guard coordinates.count == state.board.tiles.count, coordinates.count <= shape.tileCount,
              coordinates.allSatisfy({ axis.contains($0.q) && axis.contains($0.r) }),
              state.players.allSatisfy({ $0.roads.count <= state.rules.maxRoadsPerPlayer }),
              state.players.allSatisfy({ (0...state.rules.devCardDeckSize).contains($0.playedKnights) }) else {
            throw Rejection.replayFailed
        }
        // The Naval checkpoint validator measures distance from the saved
        // sailing origin. Reject off-board coordinates before that arithmetic.
        if let naval = state.naval {
            guard naval.ships.allSatisfy({ $0.previousSailingOrigin.map(coordinates.contains) ?? true }),
                  Naval.validationProblem(in: state) == nil else { throw Rejection.replayFailed }
        }
    }

    private static func hasSafeResourceAmounts(
        _ move: GameMove, checking valid: ([Resource: Int]) -> Bool
    ) -> Bool {
        switch move {
        case .discard(let amounts), .buyArmyCard(let amounts): valid(amounts)
        case .bankTrade(let give, let get): valid(give) && valid(get)
        default: true
        }
    }

    /// Jake, 2026-10-26: "make it a restart counts towards a loss in elo". The
    /// person loses; the AI seat with the most points takes the win, the
    /// earliest seat on a tie, so every phone picks the same one.
    private func forfeit(_ stats: inout [SeatStats]) {
        let bots = seats.indices.filter { !seats[$0].hasPrefix(RatedEntity.personPrefix) }
        guard let winner = bots.max(by: { (stats[$0].finalVP, -$0) < (stats[$1].finalVP, -$1) }) else { return }
        stats[winner].won = true
    }
}

extension SharedMatch {
    /// Archived ghosts belong only to the phone that kept them on reset.
    /// Publishing their games would create a nameless, unplayable ghost row
    /// on every other phone, so the historic privacy rule also binds outboxes.
    var containsArchivedGhost: Bool {
        seats.contains { key in
            guard case .ghost(let id) = RatedEntity(key: key) else { return false }
            return id.contains("~")
        }
    }

    /// Adoption re-files stats and ghosts while queued replay evidence stays
    /// immutable. Publish those canonical seat IDs with exactly the same
    /// match, timestamp and moves instead of leaking obsolete local IDs.
    func refilingSeats(_ canonical: [String]) throws -> Self {
        guard canonical.count == seats.count else { throw Rejection.seatCountMismatch }
        return Self(version: version, match: match, date: date, seats: canonical,
                    initialState: initialState, moves: moves, abandoned: abandoned, ratingPool: ratingPool)
    }

    var personIDs: [String] {
        seats.compactMap { key in
            guard case .person(let id) = RatedEntity(key: key) else { return nil }
            return id
        }
    }

    /// The shared form of a game this phone played, seats as recorded.
    init(record: SeatStatsRecord, log: GameLogDetail) {
        self.init(
            version: Self.currentVersion, match: record.match, date: record.date,
            seats: record.seats.map(\.entity),
            initialState: log.initialState,
            moves: log.events.map {
                Move(player: $0.player, move: $0.move, isHumanDecision: $0.isHumanDecision,
                     rulesVersion: $0.rulesVersion ?? RulesEngine.oldestSupportedRulesVersion)
            },
            abandoned: record.abandoned, ratingPool: record.ratingPool
        )
    }
}
