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

    enum Rejection: Error, Equatable {
        case unknownVersion(Int)
        case notClassicStandard
        case seatCountMismatch
        /// Exactly one person sits at a rated table, and it is the uploader.
        case personIsNotUploader
        case replayFailed
        case notFinished
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
        guard initialState.mode == .classic, initialState.variant == .standard else { throw Rejection.notClassicStandard }
        guard seats.count == initialState.players.count else { throw Rejection.seatCountMismatch }
        guard seats.filter({ $0.hasPrefix(RatedEntity.personPrefix) }).count == 1, !owner.isEmpty else {
            throw Rejection.personIsNotUploader
        }
        let stats: [SeatStats]
        do {
            stats = try SeatStats.compute(initial: initialState, moves: moves.map { LoggedMove(player: $0.player, move: $0.move) })
        } catch {
            throw Rejection.replayFailed
        }
        guard stats.filter(\.won).count == 1 else { throw Rejection.notFinished }
        return SeatStatsRecord(match: match, date: date,
                               seats: zip(seats, stats).map { entity, stats in
                                   SeatStatsRecord.Entry(entity: entity.hasPrefix(RatedEntity.personPrefix)
                                                             ? RatedEntity.person(owner).key : entity, stats: stats)
                               })
    }
}

extension SharedMatch {
    /// The shared form of a game this phone played, seats as recorded.
    init(record: SeatStatsRecord, log: GameLogDetail) {
        self.init(
            version: Self.currentVersion, match: record.match, date: record.date,
            seats: record.seats.map(\.entity),
            initialState: log.initialState,
            moves: log.events.map { Move(player: $0.player, move: $0.move) }
        )
    }
}
