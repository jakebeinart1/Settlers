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

/// The stable identity and behavior contract for one computer opponent.
///
/// A civilization is not merely paint: it names the general and selects the
/// dialogue voice. A strategic personality controls decisions. Keeping those
/// axes together in one catalog entry means the same opponent cannot silently
/// become a different policy because a human moved to another chair.
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

    private enum CodingKeys: String, CodingKey { case id, name, civilization, strategy }
    private enum CompatibilityKeys: String, CodingKey { case policy }

    public init(id: String, name: String, civilization: Civilization, strategy: OpponentStrategy) {
        self.id = id
        self.name = name
        self.civilization = civilization
        self.strategy = strategy
    }

    /// Research saves can name a runtime this build cannot restore. Reject it
    /// explicitly instead of ignoring the extra key and changing a saved bot.
    /// Encoding retains the original four-field schema; no migration is written.
    public init(from decoder: Decoder) throws {
        let compatibility = try decoder.container(keyedBy: CompatibilityKeys.self)
        if compatibility.contains(.policy) {
            guard try compatibility.decode(String.self, forKey: .policy) == "heuristic" else {
                throw DecodingError.dataCorruptedError(forKey: .policy, in: compatibility,
                    debugDescription: "This build cannot restore the saved opponent policy.")
            }
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        civilization = try values.decode(Civilization.self, forKey: .civilization)
        strategy = try values.decode(OpponentStrategy.self, forKey: .strategy)
    }

    public var dialogueVoice: TradeMessages.Empire { civilization.tradeMessagesEmpire }
    public var strategicPersonality: BotPersonality { strategy.personality }

    /// One canonical profile per playable civilization.
    ///
    /// New opponents use Balanced; saved profiles retain their decoded strategy.
    /// The mapping is explicit rather than inferred from enum order or seat
    /// order. Reordering either collection therefore cannot change behavior.
    public static let catalog: [OpponentProfile] = [
        OpponentProfile(id: "charlemagne", name: "Charlemagne", civilization: .medieval, strategy: .balanced),
        OpponentProfile(id: "alexander", name: "Alexander", civilization: .greece, strategy: .balanced),
        OpponentProfile(id: "ramesses", name: "Ramesses", civilization: .egypt, strategy: .balanced),
        OpponentProfile(id: "moctezuma", name: "Moctezuma", civilization: .aztec, strategy: .balanced),
        OpponentProfile(id: "washington", name: "Washington", civilization: .columbia, strategy: .balanced),
        OpponentProfile(id: "augustus", name: "Augustus", civilization: .rome, strategy: .balanced),
        OpponentProfile(id: "tokugawa", name: "Tokugawa", civilization: .japan, strategy: .balanced),
        OpponentProfile(id: "ragnar", name: "Ragnar", civilization: .norse, strategy: .balanced),
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
