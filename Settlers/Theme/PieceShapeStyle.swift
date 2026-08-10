import SwiftUI

/// The visual style used to draw settlement/city pieces on the board.
/// `.classic` is the original house silhouette (`SettlementShape`/
/// `CityShape` in `TileView.swift`); `.modern` is an alternate
/// marker/gem-style look (`ModernSettlementShape`/`ModernCityShape`).
public enum PieceShapeStyle: String, Codable, CaseIterable, Sendable {
    case classic
    case modern

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .modern: return "Modern"
        }
    }

    /// The `Shape` to draw for a settlement in this style.
    @MainActor
    public func settlementShape() -> AnyShape {
        switch self {
        case .classic: return AnyShape(SettlementShape())
        case .modern: return AnyShape(ModernSettlementShape())
        }
    }

    /// The `Shape` to draw for a city in this style.
    @MainActor
    public func cityShape() -> AnyShape {
        switch self {
        case .classic: return AnyShape(CityShape())
        case .modern: return AnyShape(ModernCityShape())
        }
    }
}
