/// Tunable knobs that differentiate bot play styles. Consumed by
/// `BuildPlanner`/`Bot`'s setup placement (`expansionBias`), and by
/// `RobberHeuristics`/`TradeHeuristics`/`DevCardHeuristics`/`Bot.decide`
/// (all three, weighting how a bot targets the robber, trades, and plays
/// dev cards).
public struct BotPersonality: Sendable {
    /// How eagerly this bot pursues aggressive plays (robber targeting,
    /// knight usage) - higher favors hurting opponents over playing it safe.
    public let aggressiveness: Double
    /// How willing this bot is to propose/accept trades - higher trades more
    /// readily even at a mediocre rate.
    public let tradeWillingness: Double
    /// How strongly this bot favors expansion (settlements/roads/cities) over
    /// hoarding resources or buying dev cards.
    public let expansionBias: Double

    public init(aggressiveness: Double, tradeWillingness: Double, expansionBias: Double) {
        self.aggressiveness = aggressiveness
        self.tradeWillingness = tradeWillingness
        self.expansionBias = expansionBias
    }

    public static let balanced = BotPersonality(aggressiveness: 0.5, tradeWillingness: 0.5, expansionBias: 0.5)
    /// High robber-disruption weight and low trade willingness (won't give
    /// opponents an easy deal), prioritizes new settlements over city
    /// upgrades (`expansionBias >= 0.5`).
    public static let aggressive = BotPersonality(aggressiveness: 0.9, tradeWillingness: 0.2, expansionBias: 0.75)
    /// Low aggressiveness (picks robber/knight fights less often), high
    /// trade willingness (readily deals for what it needs), prioritizes
    /// city upgrades over new settlements (`expansionBias < 0.5`).
    public static let cautious = BotPersonality(aggressiveness: 0.15, tradeWillingness: 0.8, expansionBias: 0.3)
}
