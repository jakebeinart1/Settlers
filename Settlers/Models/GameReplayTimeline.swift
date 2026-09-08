import Foundation
import CatanEngine

/// One archived game unfolded into every position it passed through, so the
/// replay screen can scrub between them.
///
/// ## Why the whole game is materialised up front
/// A scrubber is a random-access control: dragging its handle from move 300
/// back to move 40 has to land on move 40 immediately, and the engine can only
/// walk *forwards*. Re-applying 40 moves per slider tick is the obvious
/// alternative and it is far worse - a drag emits dozens of values a second,
/// each one paying for a replay from the opening position.
///
/// The cost of holding every frame is real and bounded: a long four-seat game
/// records roughly 600 moves, and a `GameState` is a few kilobytes, so the
/// worst case measured here is single-digit megabytes held only while the
/// replay screen is open. Build it once, off the main actor, and let scrubbing
/// be a subscript.
///
/// ## Why the archive, not the live game
/// Every name, civilization and seat here comes from the recording's own
/// `SeatRoster`, never from `CivilizationAssignment` - that global describes
/// whatever match is loaded *now*, and a replay of last week's game must not
/// borrow today's colours. `Civilization.forSeat` is deliberately unused for
/// the same reason.
struct GameReplayTimeline: Equatable {
    /// One position, plus what the move into it did. Frame 0 is the opening
    /// position and has no actor.
    struct Frame: Identifiable, Equatable {
        let id: Int
        let state: GameState
        let actor: PlayerID?
        let headline: String
        /// Where every seat's points came from *at this frame*, indexed by
        /// seat. Precomputed rather than derived while rendering: a slider
        /// drag emits dozens of values a second and
        /// `LongestRoad.length(for:in:)` is a graph search, so recomputing it
        /// per seat per drag value is the one expensive thing on this screen.
        let breakdowns: [VictoryPointBreakdown]

        /// Total victory points per seat, the number the score strip prints.
        var scores: [Int] { breakdowns.map(\.total) }
    }

    let summary: GameLogSummary
    let roster: GameLogStore.SeatRoster
    let frames: [Frame]

    /// Set when the recording stopped replaying before its last move.
    ///
    /// A recording is written by whatever build was running at the time, and
    /// this app has already shipped more than one rules version. Rather than
    /// refusing the whole game - which would hide the 200 moves that *did*
    /// replay - the timeline keeps what it reconstructed and says where it
    /// stopped. Silence would be the bad option here: a replay that quietly
    /// ends at move 173 of 400 looks like a game that ended at move 173.
    let truncation: String?

    var lastIndex: Int { frames.count - 1 }
    var seatCount: Int { summary.playerCount }

    init(detail: GameLogDetail) {
        summary = detail.summary
        roster = detail.roster

        var state = detail.initialState
        var built = [Frame(id: 0, state: state, actor: nil,
                           headline: "Opening position", breakdowns: Self.breakdowns(in: state))]
        var stoppedAt: String?
        for (offset, event) in detail.events.enumerated() {
            do {
                let events = try RulesEngine.apply(event.move, by: event.player, to: &state)
                built.append(Frame(
                    id: offset + 1,
                    state: state,
                    actor: event.player,
                    headline: GameReplayNarrator.headline(
                        for: events, move: event.move, actor: event.player, roster: detail.roster),
                    breakdowns: Self.breakdowns(in: state)))
            } catch {
                stoppedAt = "This recording replays as far as move \(offset) of "
                    + "\(detail.events.count). The rest was recorded by a different "
                    + "version of the rules and cannot be reconstructed."
                break
            }
        }
        frames = built
        truncation = stoppedAt
    }

    /// The archived identity of a seat: the recording's name and civilization,
    /// with a stable fallback when an old log carried neither.
    func identity(for seat: PlayerID) -> PlayerIdentity {
        PlayerIdentity(
            seat: seat,
            displayName: roster.displayName(for: seat),
            civilization: roster.civilization(for: seat) ?? Self.fallbackCivilization(seat),
            controller: roster.humanSeats.contains(seat) ? .human : .computer)
    }

    /// Deliberately not `Civilization.forSeat`, which answers from the global
    /// assignment of the match loaded right now.
    private static func fallbackCivilization(_ seat: PlayerID) -> Civilization {
        Civilization.allCases[seat.index % Civilization.allCases.count]
    }

    private static func breakdowns(in state: GameState) -> [VictoryPointBreakdown] {
        state.players.map { VictoryPointBreakdown(seat: $0.id, state: state) }
    }
}
