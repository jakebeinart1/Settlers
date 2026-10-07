import SwiftUI
import CatanEngine

extension BoardDecisionIntent {
    var usesMaritimePieces: Bool { self == .buildShip || self == .sailShip || self == .captureShip }
}

/// Minimum-sized map controls can overlap even when ships occupy different
/// sea hexes. Resolve that ambiguity before either camera focus or selection;
/// draw order must never decide which public hull the player meant.
enum NavalShipHitTargets {
    static func diameter(geometry: HexGeometry) -> CGFloat {
        max(minimumSide, geometry.size * artworkScale)
    }

    /// Includes every control whose rectangle overlaps the activated control.
    /// A touch intercepted by a neighbor therefore still offers the intended
    /// vessel, with stable identities independent of dictionary or draw order.
    static func nearbyShips(to coordinate: HexCoordinate, ships: [Ship], geometry: HexGeometry) -> [Ship] {
        let target = rectangle(at: coordinate, geometry: geometry)
        return ships.filter { target.intersects(rectangle(at: $0.coordinate, geometry: geometry)) }
            .sorted { $0.id < $1.id }
    }

    private static let minimumSide: CGFloat = 44
    private static let artworkScale: CGFloat = 1.10

    private static func rectangle(at coordinate: HexCoordinate, geometry: HexGeometry) -> CGRect {
        let center = geometry.center(of: coordinate)
        let side = diameter(geometry: geometry)
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }
}

/// Retains the identities during the native cover's dismissal animation.
/// The chooser still reads each current public Ship from the live array.
private struct NavalNearbyShips: Identifiable {
    let shipIDs: [Int]
    var id: [Int] { shipIDs }
}

/// A nearby-vessel chooser covers both stacked ships and overlapping targets
/// at World zoom. Each isolated control remains an ordinary direct button.
struct NavalShipLayer: View {
    let state: GameState
    let ships: [Ship]
    let decision: BoardDecisionPresentation?
    let geometry: HexGeometry
    let containerSize: CGSize
    let playerIdentity: (PlayerID) -> PlayerIdentity
    let allowsGameCommands: Bool
    let onSelectTarget: (BoardTarget) -> Void
    let onFocus: (Ship) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var nearbyShipIDs: [Int]?

    var body: some View {
        ZStack {
            ForEach(groups, id: \.coordinate) { group in
                shipGroup(group.ships, at: group.coordinate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let nearbyShipIDs, !dynamicTypeSize.isAccessibilitySize {
                nearbyChooser(for: nearbyShipIDs, fillsScreen: false).padding(8)
            }
        }
        .fullScreenCover(item: accessibleNearbyGroup) { group in
            nearbyChooser(for: group.shipIDs, fillsScreen: true)
                .presentationBackground(.clear)
        }
        // A nearby list describes the tapped pose; moving the camera or
        // advancing public vessels invalidates that physical ambiguity.
        .onChange(of: geometry.origin) { nearbyShipIDs = nil }
        .onChange(of: geometry.size) { nearbyShipIDs = nil }
        .onChange(of: ships) { nearbyShipIDs = nil }
    }

    /// The map viewport cannot contain a naturally growing AX text list.
    /// A native presentation owns the screen without altering board geometry.
    private var accessibleNearbyGroup: Binding<NavalNearbyShips?> {
        Binding(get: {
            guard dynamicTypeSize.isAccessibilitySize, let nearbyShipIDs else { return nil }
            return NavalNearbyShips(shipIDs: nearbyShipIDs)
        }, set: { nearbyShipIDs = $0?.shipIDs })
    }

    private func nearbyChooser(for ids: [Int], fillsScreen: Bool) -> NavalFleetChooser {
        NavalFleetChooser(
            ships: ships.filter { ids.contains($0.id) }, selectedShip: decision?.selectedShip,
            playerIdentity: playerIdentity, canSelect: canSelect,
            onSelect: { ship in focusOrSelect(ship); nearbyShipIDs = nil },
            onClose: { nearbyShipIDs = nil },
            maximumListHeight: max(44, min(174, containerSize.height - 92)),
            title: "Nearby ships", accessibilityPrefix: "naval.nearby", fillsScreen: fillsScreen
        )
    }

    private var groups: [(coordinate: HexCoordinate, ships: [Ship])] {
        let grouped = Dictionary(grouping: ships, by: \.coordinate)
        return grouped.keys.sorted().map { ($0, grouped[$0, default: []].sorted { $0.id < $1.id }) }
    }

    private func shipGroup(_ group: [Ship], at coordinate: HexCoordinate) -> some View {
        let ship = group[0]
        let selected = group.contains { $0.id == decision?.selectedShip }
        let nearby = NavalShipHitTargets.nearbyShips(to: coordinate, ships: ships, geometry: geometry)
        return Button {
            if nearby.count > 1 { nearbyShipIDs = nearby.map(\.id) } else { focusOrSelect(ship) }
        } label: {
            shipGroupArtwork(group)
                .frame(width: NavalShipArtworkMetrics.diameter(hexSize: geometry.size),
                       height: NavalShipArtworkMetrics.diameter(hexSize: geometry.size))
                .overlay(alignment: .topTrailing) {
                    if group.count > 1 {
                        Text("\(group.count)")
                            .font(.system(size: 10, weight: .bold, design: .serif))
                            .foregroundStyle(.black)
                            .padding(3)
                            .background(CatanTheme.chipGold, in: Circle())
                    }
                }
                .frame(width: NavalShipHitTargets.diameter(geometry: geometry),
                       height: NavalShipHitTargets.diameter(geometry: geometry))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(geometry.center(of: coordinate))
        .allowsHitTesting(acceptsShipTaps)
        .accessibilityIdentifier(group.count == 1 ? "board.ship.\(ship.id)" : "board.ships.\(coordinate.q)_\(coordinate.r)")
        .accessibilityLabel(group.count == 1 ? shipLabel(ship) : "\(group.count) ships at this location")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(nearby.count > 1 ? "Opens the nearby vessel chooser" : canSelect(ship) ? "Selects this ship for a preview" : "Focuses this public ship")
    }

    /// A capture proposal paints one future vessel, not two boats blended
    /// together. The committed button label, owner and position stay intact.
    /// Stacks show two separate silhouettes and a neutral total; Nearby/Fleet
    /// remains the complete owner list and the exact ship-selection authority.
    @ViewBuilder
    private func shipGroupArtwork(_ group: [Ship]) -> some View {
        let visible = group.filter {
            !(decision?.intent == .captureShip && decision?.selectedShip == $0.id)
        }
        if visible.isEmpty {
            Color.clear
        } else if visible.count == 1 {
            paintedShip(visible[0])
        } else {
            GeometryReader { proxy in
                let representatives = stackRepresentatives(visible)
                ZStack {
                    ForEach(Array(representatives.enumerated()), id: \.element.id) { index, ship in
                        paintedShip(ship)
                            .scaleEffect(0.72)
                            .offset(x: proxy.size.width * (index == 0 ? -0.14 : 0.14),
                                    y: proxy.size.height * (index == 0 ? 0.08 : -0.08))
                    }
                }
            }
        }
    }

    private func paintedShip(_ ship: Ship) -> some View {
        let civilization = playerIdentity(ship.owner).civilization
        return NavalShipBadge(color: civilization.accentColor, civilization: civilization,
                              isSelected: ship.id == decision?.selectedShip)
    }

    private func stackRepresentatives(_ group: [Ship]) -> [Ship] {
        let first = group.first { $0.id == decision?.selectedShip } ?? group[0]
        let second = group.first { $0.owner != first.owner }
            ?? group.first { $0.id != first.id }!
        return [first, second]
    }

    /// Ships share sea hexes with destination targets. During placement the
    /// target underneath must receive the tap; Fleet still offers inspection.
    private var acceptsShipTaps: Bool {
        guard let decision else { return true }
        return decision.intent == .captureShip || (decision.intent == .sailShip && decision.selectedShip == nil)
    }

    private func focusOrSelect(_ ship: Ship) {
        onFocus(ship)
        if canSelect(ship) { onSelectTarget(.ship(ship.id)) }
    }

    private func canSelect(_ ship: Ship) -> Bool {
        guard allowsGameCommands else { return false }
        if let decision { return decision.legalShips.contains(ship.id) }
        guard case .mainTurn(let playerIndex) = state.phase else { return false }
        return ship.owner.index == playerIndex && ship.stepsRemaining > 0
            && playerIdentity(ship.owner).controller == .human
    }

    private func shipLabel(_ ship: Ship) -> String {
        let identity = playerIdentity(ship.owner)
        return "\(identity.displayName), \(identity.civilization.displayName) vessel, \(NavalShipName.name(ship.id)), \(NavalQuantityText.stepsRemaining(ship.stepsRemaining))"
    }
}

/// Fleet rows preserve readable identities when the world is zoomed out or
/// several owners share a hex. Selection remains a proposal in the coordinator.
struct NavalFleetChooser: View {
    let ships: [Ship]
    let selectedShip: Int?
    let playerIdentity: (PlayerID) -> PlayerIdentity
    let canSelect: (Ship) -> Bool
    let onSelect: (Ship) -> Void
    let onClose: () -> Void
    var maximumListHeight: CGFloat = 174
    var title: String = "Fleet"
    var accessibilityPrefix: String = "naval.fleet"
    var fillsScreen = false
    @AccessibilityFocusState private var isHeadingFocused: Bool

    var body: some View {
        Group {
            if fillsScreen { expandedContent } else { compactContent }
        }
        .foregroundStyle(CatanTheme.onWaterText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityPrefix)
        .onAppear { if fillsScreen { isHeadingFocused = true } }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Close", action: onClose)
                    .font(.caption.bold())
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("\(accessibilityPrefix).close")
                    .accessibilityLabel("Close \(title.lowercased())")
            }
            if ships.isEmpty {
                Text("No ships have been launched yet.").font(.caption)
            } else {
                fleetList.frame(maxHeight: maximumListHeight)
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(PaintedChromeBackground(fill: .color(CatanTheme.waterBackground), cornerRadius: 12))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
    }

    /// The header takes its natural height; the list receives the remaining
    /// native presentation space. No fixed board-height subtraction or text
    /// cap can make a 250pt popover readable at Accessibility XXXL.
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            expandedHeader
            fleetList.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaintedChromeBackground(fill: .color(CatanTheme.waterBackground), cornerRadius: 12))
        .padding(12)
        .background(TintedTextureBackground(tint: CatanTheme.waterBackground).ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(CatanTheme.cityPennantGold)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isHeadingFocused)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .background(PaintedChromeBackground(fill: .color(CatanTheme.waterBackground), cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(accessibilityPrefix).close")
            .accessibilityLabel("Close \(title.lowercased())")
        }
    }

    private var fleetList: some View {
        ScrollView {
            VStack(spacing: fillsScreen ? 12 : 6) {
                if ships.isEmpty {
                    Text("No ships have been launched yet.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(ships.sorted { $0.id < $1.id }, id: \.id) { ship in
                        fleetRow(ship)
                    }
                }
            }
            .padding(.vertical, fillsScreen ? 3 : 0)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func fleetRow(_ ship: Ship) -> some View {
        let identity = playerIdentity(ship.owner)
        return Button { onSelect(ship) } label: {
            if fillsScreen {
                expandedRow(ship, identity: identity)
            } else {
                compactRow(ship, identity: identity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(accessibilityPrefix).ship.\(ship.id)")
        .accessibilityLabel("\(identity.displayName), \(NavalShipName.name(ship.id)), \(NavalQuantityText.stepsRemaining(ship.stepsRemaining))")
        .accessibilityValue(ship.id == selectedShip ? "Selected" : "Not selected")
        .accessibilityHint(canSelect(ship) ? "Focus and select this ship for a preview" : "Focus this public ship without changing the game")
    }

    private func compactRow(_ ship: Ship, identity: PlayerIdentity) -> some View {
        HStack(spacing: 8) {
            NavalShipBadge(color: identity.civilization.accentColor, civilization: identity.civilization,
                           isSelected: ship.id == selectedShip)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(identity.displayName)'s ship").font(.caption.bold())
                Text(NavalQuantityText.stepsRemaining(ship.stepsRemaining))
                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
            if ship.id == selectedShip { Image(systemName: "checkmark") }
        }
        .padding(6)
        .frame(minHeight: 44)
        .background(identity.civilization.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
    }

    /// Stable hull identity leads the card; ownership and movement wrap on
    /// their own lines instead of competing for one compressed text column.
    private func expandedRow(_ ship: Ship, identity: PlayerIdentity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                NavalShipBadge(color: identity.civilization.accentColor, civilization: identity.civilization,
                               isSelected: ship.id == selectedShip)
                    .frame(width: 44, height: 44)
                Text(NavalShipName.name(ship.id))
                    .font(.system(.headline, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if ship.id == selectedShip { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            Text(identity.displayName).font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(NavalQuantityText.stepsRemaining(ship.stepsRemaining))
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(PaintedChromeBackground(fill: .tintedTexture(identity.civilization.cardBackgroundColor(active: true)),
                                           cornerRadius: 9, notchScale: 0.7))
    }
}
