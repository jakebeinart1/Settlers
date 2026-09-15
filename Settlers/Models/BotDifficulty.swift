import Foundation
import CatanAI
import CatanEngine

/// How strong the computer opponents play.
///
/// ## Why this is a separate axis from `OpponentStrategy`
/// `OpponentProfile` deliberately carries no difficulty, and says why: its
/// personalities are *measured play styles*, not calibrated strength tiers,
/// and difficulty was to be "composed alongside this profile without changing
/// the opponent's identity or voice" once a real strength ladder existed. One
/// now does, so this is that composition. Charlemagne is still Charlemagne and
/// still speaks with his own voice at either difficulty; only the machinery
/// choosing his moves changes.
///
/// ## The ladder is measured, not asserted
/// Both tiers were measured under the `bot-strength` protocol - 1,248 decisive
/// games, complete chair rotation, held-out seeds, against three frozen
/// `balanced` heuristics at a 25.0% null:
///
/// | tier | policy | win rate |
/// |---|---|---|
/// | Classic | `HeuristicPolicy` | 25.0% (it *is* the anchor) |
/// | Expert | `EvaluationPolicy` | 47.3% (95% CI 44.5-50.0) |
///
/// That is the whole justification for offering a choice: the two tiers are
/// known to differ, and by how much. A difficulty control whose levels had not
/// been measured against each other would be decoration.
public enum BotDifficulty: String, Codable, CaseIterable, Sendable {
    /// The heuristic that has always shipped. Named for what it is rather than
    /// "Easy", because it is not easy - it beat its author.
    case classic
    /// Position evaluation with fitted weights.
    case expert

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .expert: return "Expert"
        }
    }

    /// One line for the New Game screen, under the control.
    public var summary: String {
        switch self {
        case .classic: return "The opponents that have always shipped."
        case .expert: return "Plans around your position. Measurably stronger."
        }
    }

    /// The default for a new game and for any setup saved before this control
    /// existed.
    ///
    /// Classic, deliberately: a player with a game in progress must not find
    /// their opponents quietly replaced by stronger ones because they
    /// installed an update. Choosing Expert is a decision someone makes, not
    /// one made for them.
    public static let `default` = BotDifficulty.classic

    /// The policy this tier plays with, for an opponent with `profile`.
    ///
    /// Personality reaches `HeuristicPolicy` and not `EvaluationPolicy`,
    /// because the evaluation bot has no personality axis - its weights were
    /// fitted as one policy. That is a real difference between the tiers and
    /// is left visible here rather than papered over with a personality
    /// parameter that would be ignored.
    public func policy(for profile: OpponentProfile) -> any Policy {
        switch self {
        case .classic:
            return HeuristicPolicy(
                personality: profile.strategicPersonality,
                id: "heuristic-\(profile.strategy.rawValue)"
            )
        case .expert:
            return EvaluationPolicy()
        }
    }
}
