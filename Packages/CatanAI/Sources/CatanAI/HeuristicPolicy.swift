import CatanEngine

/// `Bot` as a `Policy`, so the shipped heuristic plugs into `GameSession` the
/// same way any future agent will.
///
/// The adapter is deliberately thin. `Bot` keeps its own signature - the tests
/// exercise it directly and there is no reason to churn them - and this only
/// bridges the shapes. What it does add is the identifier an evaluation record
/// needs: comparing two bots is meaningless unless each result says which bot
/// produced it.
public struct HeuristicPolicy: Policy {
    public let id: String
    private let bot: Bot

    /// - Parameter id: how this policy appears in an evaluation record. Include
    ///   the personality, because two `HeuristicPolicy` seats with different
    ///   personalities are genuinely different opponents.
    public init(personality: BotPersonality, weights: BotWeights = .default, id: String) {
        self.bot = Bot(personality: personality, weights: weights)
        self.id = id
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        bot.decide(for: observation.state, player: observation.seat, rng: &rng)
    }
}

/// Picks uniformly among legal moves.
///
/// Exists to be the anchor a strength claim is measured against. Bot-vs-bot
/// win rates are 25% by construction at a four-seat table and say nothing
/// about whether a bot is any good; a policy that plays legally and thinks not
/// at all is the floor that makes "better" mean something. It never changes,
/// which is the point - an anchor that moves measures nothing.
public struct RandomPolicy: Policy {
    public let id = "random"

    public init() {}

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        // `legalMoves` is never empty in a phase a policy is asked to act in;
        // `.endTurn` would not be legal in most of them, so failing loudly
        // beats substituting a move the engine would reject.
        guard let move = observation.legalMoves.randomElement(using: &rng) else {
            preconditionFailure("asked to move with no legal move in phase \(observation.state.phase)")
        }
        return move
    }
}
