/// Tunable knobs that differentiate bot play styles. Task 10 will consume
/// these more fully (trade/dev-card/robber heuristics); for now `BuildPlanner`
/// and `Bot`'s setup placement already lean on `expansionBias`.
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
    public static let aggressive = BotPersonality(aggressiveness: 0.85, tradeWillingness: 0.4, expansionBias: 0.7)
    public static let cautious = BotPersonality(aggressiveness: 0.2, tradeWillingness: 0.6, expansionBias: 0.35)
}
