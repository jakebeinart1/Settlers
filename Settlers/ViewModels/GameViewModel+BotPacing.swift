import Foundation
import CatanEngine

/// How fast the bots appear to play.
///
/// Both rules here are presentation, not gameplay: the engine has no notion of
/// time and `GameSession` decides a move in microseconds. Everything a player
/// perceives as a bot "thinking" is added deliberately, and in exactly these
/// two places.
extension GameViewModel {
    /// Waits until the player's chosen interval has passed since the previous
    /// bot action.
    ///
    /// A DEADLINE, not a fixed nap. Deciding and committing a move costs real
    /// time, and that cost grows with the length of the game - measured over
    /// one 770-move Expanded match, 37ms per action at the start against
    /// 395ms at the end (`docs/plans/2026-09-11-expanded-bots-and-speed.md`).
    /// Sleeping the whole interval *on top* of that work made the interval a
    /// floor that drifted upward all game: the same "Standard" setting paced
    /// an action a second early on and appreciably slower late on, which is
    /// half of what "the end of a long game feels sluggish" was. Waiting only
    /// for the remainder holds the rhythm the player picked, and can only ever
    /// shorten the wait - when the work outruns the interval there is no sleep
    /// at all, never a negative one.
    ///
    /// The speed is read from the singleton on every call rather than captured
    /// once before the loop: that is acceptance criterion B1.2 - a speed the
    /// player changes mid-turn has to reach the very next action, not the next
    /// game.
    func waitForNextBotAction() async {
        let interval = PacingPreferences.shared.aiTurnSpeed.secondsPerBotAction
        let sinceLastAction = lastBotActionAt.map { Date().timeIntervalSince($0) } ?? 0
        let remaining = interval - max(0, sinceLastAction)
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
    }

    /// Holds off applying `move` if it's a bot accepting someone *else's*
    /// still-open trade offer, until a randomized 2-4s have passed since
    /// that offer was first proposed (see `offerProposedAt`'s doc) - real
    /// Catan only lets you act on your own turn, and without this, a bot
    /// whose turn happens to fall right after the proposal could snap up an
    /// offer the human's card is still showing, with none of the human's
    /// read-and-decide time. A no-op for every other move (declines,
    /// proposals, builds, etc. all go through immediately).
    func waitForFairAcceptWindow(before move: GameMove) async {
        guard case .respondToTrade(let offerID, true) = move,
              let proposedAt = offerProposedAt[offerID]
        else { return }
        let targetDelay = Double.random(in: 2...4)
        let elapsed = Date().timeIntervalSince(proposedAt)
        guard elapsed < targetDelay else { return }
        try? await Task.sleep(for: .seconds(targetDelay - elapsed))
    }
}
