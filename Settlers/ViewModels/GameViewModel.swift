import Observation
import CatanEngine
import CatanAI

/// Drives a single local game: owns the authoritative `GameState`, applies
/// the human's moves through `RulesEngine`, and runs bot turns (via
/// `CatanAI.Bot`) until control returns to the human or the game ends.
/// Persists to `GameStore` after every applied move so the game can resume
/// across app launches.
@MainActor
@Observable
public final class GameViewModel {
    public private(set) var state: GameState
    public let humanPlayer = PlayerID(index: 0)
    public private(set) var isBotThinking: Bool = false

    public init() {
        if let saved = GameStore.shared.load() {
            state = saved
        } else {
            state = GameSetup.newGame(board: BoardGenerator.standard())
        }
    }

    /// Starts a fresh game, discarding whatever `state` currently holds.
    public func startNewGame(randomizedBoard: Bool) {
        let board = randomizedBoard
            ? BoardGenerator.randomized(seed: UInt64.random(in: .min ... .max))
            : BoardGenerator.standard()
        state = GameSetup.newGame(board: board)
        try? GameStore.shared.save(state)
    }

    /// Applies a human move, persists the result, and lets any subsequent
    /// bot turns run. A save failure here is swallowed the same way
    /// `runBotTurnIfNeeded()` swallows one: losing the on-disk save is not
    /// worth surfacing as if the move itself failed (the move already
    /// succeeded against `state`, which is what the caller/UI cares about),
    /// and only `RulesEngine.apply`'s own errors indicate the human's move
    /// itself was rejected.
    public func apply(_ move: GameMove) throws {
        try RulesEngine.apply(move, by: humanPlayer, to: &state)
        try? GameStore.shared.save(state)
        Task { await runBotTurnIfNeeded() }
    }

    /// Runs bot turns in a loop for as long as the active player (or, during
    /// `.discarding`, the next pending bot) isn't the human and the game
    /// hasn't ended, pausing briefly before each move so bot play reads as
    /// "thinking" rather than instant.
    ///
    /// `sameBotActionCap` guards against a bot never producing `.endTurn`:
    /// manual verification (see task-12-report.md) found `Bot.decide` can
    /// legitimately keep proposing the same trade offer forever once it has
    /// a resource surplus but no affordable build (`TradeHeuristics
    /// .proposeTrades` returns an identical offer every call, and nothing
    /// in `Bot.decideMainTurn` tracks "already proposed this turn"), which
    /// would otherwise hang this loop - and the app - indefinitely. Once the
    /// same bot has acted this many times in a row without the active
    /// player changing, force `.endTurn` for it instead of trusting
    /// `Bot.decide` again.
    public func runBotTurnIfNeeded() async {
        let sameBotActionCap = 25
        var currentBot: PlayerID?
        var actionsForCurrentBot = 0

        while let botPlayer = nextBotPlayer() {
            isBotThinking = true
            try? await Task.sleep(for: .milliseconds(600))

            if botPlayer == currentBot {
                actionsForCurrentBot += 1
            } else {
                currentBot = botPlayer
                actionsForCurrentBot = 1
            }

            // Only `.mainTurn` allows an unbounded number of actions before
            // the phase moves on (build, trade, play dev cards, repeat) -
            // `.movingRobber`/`.discarding` each resolve in a single move
            // per player, so the cap only ever needs to bite here.
            let move: GameMove
            if actionsForCurrentBot > sameBotActionCap, case .mainTurn = state.phase {
                move = .endTurn
            } else {
                let bot = Bot(personality: personality(for: botPlayer))
                move = bot.decide(for: state, player: botPlayer)
            }
            try? RulesEngine.apply(move, by: botPlayer, to: &state)
            try? GameStore.shared.save(state)
        }
        isBotThinking = false
    }

    /// The bot that should act next, or `nil` if it's the human's turn or
    /// the game is over. `.discarding` has no single active player, so this
    /// picks any one bot still in `pending`; it's re-derived each loop
    /// iteration so it naturally advances to the next pending bot (or to
    /// `nil` once only the human remains).
    private func nextBotPlayer() -> PlayerID? {
        switch state.phase {
        case .setupForward(let playerIndex),
             .setupBackward(let playerIndex),
             .rollDice(let playerIndex),
             .mainTurn(let playerIndex),
             .movingRobber(let playerIndex):
            let player = PlayerID(index: playerIndex)
            return player == humanPlayer ? nil : player
        case .discarding(let pending):
            return pending.first { $0 != humanPlayer }
        case .gameOver:
            return nil
        }
    }

    private func personality(for player: PlayerID) -> BotPersonality {
        switch player.index {
        case 1: return .balanced
        case 2: return .aggressive
        case 3: return .cautious
        default: return .balanced
        }
    }
}
