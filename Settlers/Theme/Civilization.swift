import SwiftUI
import CatanEngine

/// One of the four playable empires - fixed per seat (not user-customizable,
/// unlike `PieceColor`) so every game features the same four civilizations
/// with the same generals, and their settlements/cities
/// read as that civilization's own architecture rather than a generic
/// house/marker. Roads stay a plain colored bar (`RoadShape`) - the
/// civilization identity comes through in the buildings, the seat's default
/// color, and the HUD's general/empire naming.
public enum Civilization: String, CaseIterable, Sendable {
    case britannia
    case rome
    case china
    case mongolia

    /// Fixed seat assignment: 0 = human, 1-3 = bots, matching
    /// `GameViewModel`'s personality assignment order.
    public static func forSeat(_ index: Int) -> Civilization {
        switch index {
        case 0: return .britannia
        case 1: return .rome
        case 2: return .china
        default: return .mongolia
        }
    }

    public var displayName: String {
        switch self {
        case .britannia: return "Britannia"
        case .rome: return "Rome"
        case .china: return "China"
        case .mongolia: return "Mongolia"
        }
    }

    /// The general leading this civilization's bot seat - shown in place of
    /// "Bot (Balanced)"-style labels. The human's own seat (Britannia) still
    /// just reads "You" everywhere (see `CatanTheme.playerLabel`), so this
    /// name is only ever surfaced for bot seats in practice.
    public var generalName: String {
        switch self {
        case .britannia: return "Wellington"
        case .rome: return "Caesar"
        case .china: return "Sun Tzu"
        case .mongolia: return "Genghis Khan"
        }
    }

    /// Small SF Symbol standing in for this civilization's emblem - used
    /// next to its name in the HUD so each empire reads as a distinct
    /// faction at a glance, not just a color.
    public var emblemSymbol: String {
        switch self {
        case .britannia: return "shield.lefthalf.filled"
        case .rome: return "laurel.leading"
        case .china: return "flame.fill"
        case .mongolia: return "wind"
        }
    }

    @MainActor
    public func settlementShape() -> AnyShape {
        switch self {
        case .britannia: return AnyShape(BritanniaKeepShape())
        case .rome: return AnyShape(RomanColumnShape())
        case .china: return AnyShape(PagodaShape(tiers: 1))
        case .mongolia: return AnyShape(YurtShape())
        }
    }

    @MainActor
    public func cityShape() -> AnyShape {
        switch self {
        case .britannia: return AnyShape(BritanniaCastleShape())
        case .rome: return AnyShape(RomanTempleShape())
        case .china: return AnyShape(PagodaShape(tiers: 2))
        case .mongolia: return AnyShape(YurtCampShape())
        }
    }
}
