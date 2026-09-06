import Foundation
import CatanAI

/// Stable persisted/logged identity for a measured strategic style.
/// `BotPersonality` is a bag of tuning values; persisting those values would
/// turn every tuning edit into a migration and would not say which contract
/// they were intended to implement.
public enum OpponentStrategy: String, Codable, CaseIterable, Sendable {
    case balanced
    case aggressive
    case cautious

    public var personality: BotPersonality {
        switch self {
        case .balanced: return .balanced
        case .aggressive: return .aggressive
        case .cautious: return .cautious
        }
    }
}

/// Persisted implementation choice. Missing values belong to older heuristic
/// matches, so changing the new-game catalog cannot change a resumed policy ID.
public enum OpponentPolicy: String, Codable, CaseIterable, Sendable {
    case heuristic
    case neuralR2

    /// Describes the configured match, not the backend of any individual move.
    /// Decision traces record neural decisions and heuristic fallbacks separately.
    public static func modeDescription(for policies: [OpponentPolicy]) -> String {
        guard !policies.isEmpty else { return "Human players only." }
        guard policies.contains(.neuralR2) else { return "Heuristic AI • heuristic trading; all hands visible." }
        let label = policies.contains(.heuristic) ? "Neural + heuristic AI (experimental)" : "Neural AI (experimental)"
        return "\(label) • heuristic trading; all hands visible."
    }
}

/// The stable identity and behavior contract for one computer opponent.
///
/// A civilization is not merely paint: it names the general and selects the
/// dialogue voice. The policy selects an implementation; the strategic
/// personality configures its heuristic trade and fallback decisions. Keeping
/// those choices in the saved profile prevents a chair change or catalog update
/// from silently replacing a running match's policy.
///
/// Difficulty is deliberately absent. The current personalities are measured
/// play styles, not calibrated strength tiers. When a real strength ladder
/// exists, difficulty can be composed alongside this profile without changing
/// the opponent's identity or voice.
public struct OpponentProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let civilization: Civilization
    public let strategy: OpponentStrategy
    public let policy: OpponentPolicy

    public init(id: String, name: String, civilization: Civilization,
                strategy: OpponentStrategy, policy: OpponentPolicy = .heuristic) {
        self.id = id
        self.name = name
        self.civilization = civilization
        self.strategy = strategy
        self.policy = policy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        civilization = try values.decode(Civilization.self, forKey: .civilization)
        strategy = try values.decode(OpponentStrategy.self, forKey: .strategy)
        policy = try values.decodeIfPresent(OpponentPolicy.self, forKey: .policy) ?? .heuristic
    }

    func usingPolicy(_ policy: OpponentPolicy) -> OpponentProfile {
        OpponentProfile(id: id, name: name, civilization: civilization, strategy: strategy, policy: policy)
    }

    public var dialogueVoice: TradeMessages.Empire { civilization.tradeMessagesEmpire }
    public var strategicPersonality: BotPersonality { strategy.personality }

    /// One canonical profile per playable civilization.
    ///
    /// The mapping is explicit rather than inferred from enum order or seat
    /// order. Reordering either collection therefore cannot change behavior.
    public static let catalog: [OpponentProfile] = [
        OpponentProfile(id: "charlemagne", name: "Charlemagne", civilization: .medieval, strategy: .balanced, policy: .neuralR2),
        OpponentProfile(id: "alexander", name: "Alexander", civilization: .greece, strategy: .aggressive, policy: .neuralR2),
        OpponentProfile(id: "ramesses", name: "Ramesses", civilization: .egypt, strategy: .cautious, policy: .neuralR2),
        OpponentProfile(id: "moctezuma", name: "Moctezuma", civilization: .aztec, strategy: .aggressive, policy: .neuralR2),
        OpponentProfile(id: "washington", name: "Washington", civilization: .columbia, strategy: .balanced, policy: .neuralR2),
        OpponentProfile(id: "augustus", name: "Augustus", civilization: .rome, strategy: .aggressive, policy: .neuralR2),
        OpponentProfile(id: "tokugawa", name: "Tokugawa", civilization: .japan, strategy: .cautious, policy: .neuralR2),
        OpponentProfile(id: "ragnar", name: "Ragnar", civilization: .norse, strategy: .balanced, policy: .neuralR2),
    ]

    private static let byCivilization = Dictionary(
        uniqueKeysWithValues: catalog.map { ($0.civilization, $0) }
    )

    public static func forCivilization(_ civilization: Civilization) -> OpponentProfile {
        guard let profile = byCivilization[civilization] else {
            preconditionFailure("Every civilization must have one opponent profile")
        }
        return profile
    }
}
