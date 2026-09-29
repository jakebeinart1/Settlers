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
    /// game this ladder counts. `uploader` is the name the record's creator
    /// has claimed (`LiveSync` resolves it from the record's owner).
    ///
    /// `holding` is the slug the uploader's claim sits under. It is the name's
    /// own slug unless they have renamed: then a game posted as "Jake" is
    /// checked against `jake`, which the renamed "Bein" still holds.
    func verified(uploader: String, holding: String? = nil) throws -> SeatStatsRecord {
        guard version == Self.currentVersion else { throw Rejection.unknownVersion(version) }
        guard initialState.mode == .classic, initialState.variant == .standard else { throw Rejection.notClassicStandard }
        guard seats.count == initialState.players.count else { throw Rejection.seatCountMismatch }
        // By slug, not by exact name: a game uploaded as "Jake" still belongs
        // to the holder of `jake` after they rename themselves "Bein", and it
        // is recorded under the name they go by now.
        let people = seats.filter { $0.hasPrefix(RatedEntity.personPrefix) }
        guard people.count == 1, let person = LiveSync.slug(ofPersonKey: people[0]),
              person == holding ?? GhostTrainer.ghostID(forPerson: uploader) else { throw Rejection.personIsNotUploader }
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
                                                             ? RatedEntity.person(uploader).key : entity, stats: stats)
                               })
    }
}

extension SharedMatch {
    /// The shared form of a game this phone played. The person's seat is
    /// written under `name`, the uploader's claimed name, so a game typed as
    /// "jake" and one typed as "Jake" land on one leaderboard row.
    init(record: SeatStatsRecord, log: GameLogDetail, name: String) {
        self.init(
            version: Self.currentVersion, match: record.match, date: record.date,
            seats: record.seats.map { $0.entity.hasPrefix(RatedEntity.personPrefix) ? RatedEntity.person(name).key : $0.entity },
            initialState: log.initialState,
            moves: log.events.map { Move(player: $0.player, move: $0.move) }
        )
    }
}
