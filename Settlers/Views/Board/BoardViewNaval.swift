import SwiftUI
import CatanEngine
import UIKit

extension BoardView {
    /// Home is a deliberate camera pose on the public world, not a fit
    /// remembered from whichever areas happen to be discovered.
    static let navalHomeCamera = BoardCamera(zoom: 2.6, pan: .zero)

    #if DEBUG
    /// Leaf siblings expose the projected geometry without becoming an
    /// accessibility ancestor of ship or destination controls. A fixed
    /// viewport frame alone cannot catch a changing fit or camera pose.
    func navalCameraReferenceMarkers(geometry: HexGeometry) -> some View {
        ZStack {
            cameraMarker(at: HexCoordinate(q: 0, r: 0), identifier: "naval.camera.reference", geometry: geometry)
            cameraMarker(at: HexCoordinate(q: 1, r: 0), identifier: "naval.camera.neighbor", geometry: geometry)
            ForEach(state.naval?.ships ?? [], id: \.id) { ship in
                shipPositionMarker(ship, geometry: geometry)
            }
        }
        .allowsHitTesting(false)
    }

    /// Public committed ship positions give native tests independent evidence
    /// of which hull moved. They are siblings, never AX ancestors of controls.
    private func shipPositionMarker(_ ship: Ship, geometry: HexGeometry) -> some View {
        Color.white.opacity(0.001)
            .frame(width: 1, height: 1)
            .position(geometry.center(of: ship.coordinate))
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("naval.ship.position.\(ship.id)")
            .accessibilityLabel("Committed public ship position")
            .accessibilityValue("q=\(ship.coordinate.q);r=\(ship.coordinate.r);steps=\(ship.stepsRemaining)")
            .accessibilityRespondsToUserInteraction(false)
    }

    private func cameraMarker(at coordinate: HexCoordinate, identifier: String,
                              geometry: HexGeometry) -> some View {
        let point = geometry.center(of: coordinate)
        let value = String(format: "zoom=%.6f;panX=%.6f;panY=%.6f;hexSize=%.6f;x=%.6f;y=%.6f",
                           Double(camera.zoom), Double(camera.pan.width), Double(camera.pan.height),
                           Double(geometry.size), Double(point.x), Double(point.y))
        return Color.white.opacity(0.001)
            .frame(width: 1, height: 1)
            .position(point)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel("Naval camera reference")
            .accessibilityValue(value + ";reduceMotion=\(reduceMotion ? 1 : 0)")
            .accessibilityRespondsToUserInteraction(false)
    }
    #endif

    func beginNavalOpening() {
        guard animatesStateChanges, let naval = state.naval, naval.options.fogEnabled,
              state.players.allSatisfy({ $0.settlements.isEmpty && $0.cities.isEmpty }),
              naval.ships.isEmpty else { return }
        withdrawMist(newlyRevealed: naval.revealed)
    }

    func withdrawMist(newlyRevealed: Set<HexCoordinate>) {
        guard animatesStateChanges, state.naval?.options.fogEnabled == true, !newlyRevealed.isEmpty else {
            retiringMist = []
            mistProgress = 1
            return
        }
        retiringMist = newlyRevealed
        mistProgress = 0
        UIAccessibility.post(notification: .announcement,
                             argument: "\(NavalQuantityText.hexes(newlyRevealed.count)) discovered for all players. \(discoverySummary)")
    }

    private var discoverySummary: String {
        "Shared map: \(state.naval?.revealed.count ?? 0) of \(board.tiles.count) hexes charted. Discovered terrain stays visible."
    }

    /// Let the opaque starting cover render before retiring it. This task
    /// belongs to the reveal set, so replacement or navigation cancels only
    /// cosmetics; no gameplay action waits for the animation.
    @MainActor
    func animateMistWithdrawal() async {
        guard !retiringMist.isEmpty else { return }
        do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 1.0)) { mistProgress = 1 }
    }

    func focusNavalShip(_ coordinate: HexCoordinate, fit: BoardFit, container: CGSize) {
        navalReturnCamera = nil
        let zoom = Self.navalHomeCamera.zoom
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        let point = fit.geometry.center(of: coordinate)
        let pose = BoardCamera(zoom: zoom, pan: CGSize(width: (center.x - point.x) * zoom,
                                                     height: (center.y - point.y) * zoom))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            camera = pose.clamped(fittedBounds: fit.bounds, container: container, maximumZoom: cameraMaximumZoom)
        }
    }

    func navalNavigation(fit: BoardFit, container: CGSize) -> some View {
        NavalNavigationControls(
            ships: state.naval?.ships ?? [], decision: decision,
            canReturn: navalReturnCamera != nil,
            availableHeight: container.height, discoverySummary: discoverySummary,
            playerIdentity: playerIdentity,
            canSelect: canDraftNavalShip,
            onSelect: { ship in
                focusNavalShip(ship.coordinate, fit: fit, container: container)
                if canDraftNavalShip(ship) { onSelectTarget(.ship(ship.id)) }
            },
            onOverview: { toggleNavalOverview(fit: fit, container: container) },
            onHome: {
                navalReturnCamera = nil
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { camera = Self.navalHomeCamera }
            }
        )
    }

    /// World is a reversible inspection trip. Gestures and discoveries may
    /// continue, but returning changes no draft, resources or public terrain.
    private func toggleNavalOverview(fit: BoardFit, container: CGSize) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            if let previous = navalReturnCamera {
                camera = previous.clamped(fittedBounds: fit.bounds, container: container, maximumZoom: cameraMaximumZoom)
                navalReturnCamera = nil
            } else {
                navalReturnCamera = camera
                camera = .fitted
            }
        }
    }

    private func canDraftNavalShip(_ ship: Ship) -> Bool {
        guard allowsGameCommands else { return false }
        if let decision { return decision.legalShips.contains(ship.id) }
        guard case .mainTurn(let index) = state.phase else { return false }
        return ship.owner.index == index && ship.stepsRemaining > 0
            && playerIdentity(ship.owner).controller == .human
    }

    @ViewBuilder
    func navalShipPreview(geometry: HexGeometry) -> some View {
        if let decision, decision.intent == .captureShip, let selected = decision.selectedShip,
           let ship = state.naval?.ships.first(where: { $0.id == selected }) {
            provisionalShip(for: decision.actor, size: NavalShipArtworkMetrics.diameter(hexSize: geometry.size))
                .position(geometry.center(of: ship.coordinate))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("board.ship-capture-preview")
                .accessibilityLabel("Capture preview for \(playerIdentity(ship.owner).displayName)'s ship")
                .accessibilityValue("Will become \(playerIdentity(decision.actor).displayName)'s ship after confirmation")
        } else if let decision, decision.intent.usesMaritimePieces, let destination = decision.selectedTile {
            if let selected = decision.selectedShip,
               let ship = state.naval?.ships.first(where: { $0.id == selected }) {
                Path { path in
                    path.move(to: geometry.center(of: ship.coordinate))
                    for coordinate in decision.sailing?.selectedRoute ?? [destination] {
                        path.addLine(to: geometry.center(of: coordinate))
                    }
                }
                .stroke(CatanTheme.chipGold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 4]))
                .allowsHitTesting(false)
            }
            provisionalShip(for: decision.actor, size: NavalShipArtworkMetrics.diameter(hexSize: geometry.size))
                .position(geometry.center(of: destination))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("board.ship-preview")
                .accessibilityLabel(decision.intent == .buildShip ? "Ship launch preview" : "Sailing destination preview")
                .accessibilityValue("Proposed, not yet committed")
        }
    }

    /// The reused artwork deliberately hides itself. Its proposal container
    /// supplies independent semantics, just like a staged building badge.
    private func provisionalShip(for owner: PlayerID, size: CGFloat) -> some View {
        ZStack {
            NavalShipBadge(color: playerIdentity(owner).civilization.accentColor,
                           civilization: playerIdentity(owner).civilization, isProvisional: true)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
    }
}

private struct NavalNavigationControls: View {
    let ships: [Ship]
    let decision: BoardDecisionPresentation?
    let canReturn: Bool
    let availableHeight: CGFloat
    let discoverySummary: String
    let playerIdentity: (PlayerID) -> PlayerIdentity
    let canSelect: (Ship) -> Bool
    let onSelect: (Ship) -> Void
    let onOverview: () -> Void
    let onHome: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isFleetOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFleetOpen, !dynamicTypeSize.isAccessibilitySize { fleetChooser(fillsScreen: false) }
            HStack(spacing: 5) {
                navigationButton("Home", symbol: "house", id: "naval.home", action: onHome)
                navigationButton(canReturn ? "Return" : "World", symbol: canReturn ? "arrow.uturn.backward" : "map",
                                 id: "naval.overview", action: onOverview)
                navigationButton("Fleet", symbol: "sailboat", id: "naval.fleet.open") { isFleetOpen.toggle() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(CatanTheme.waterBackground.opacity(0.55))
            .background(navigationFrameMarker)
            .overlay(alignment: .top) {
                Rectangle().fill(CatanTheme.onWaterText.opacity(0.16))
                    .frame(height: 1).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .fullScreenCover(isPresented: accessibleFleetPresented) {
            fleetChooser(fillsScreen: true).presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private var navigationFrameMarker: some View {
        #if DEBUG
        Color.clear.accessibilityElement()
            .accessibilityIdentifier("naval.navigation.bounds")
            .accessibilityRespondsToUserInteraction(false)
            .allowsHitTesting(false)
        #else
        EmptyView()
        #endif
    }

    private var accessibleFleetPresented: Binding<Bool> {
        Binding(get: { isFleetOpen && dynamicTypeSize.isAccessibilitySize },
                set: { if !$0 { isFleetOpen = false } })
    }

    private func fleetChooser(fillsScreen: Bool) -> NavalFleetChooser {
        NavalFleetChooser(ships: ships, selectedShip: decision?.selectedShip,
                          playerIdentity: playerIdentity, canSelect: canSelect,
                          onSelect: { ship in onSelect(ship); isFleetOpen = false },
                          onClose: { isFleetOpen = false },
                          maximumListHeight: max(44, min(174, availableHeight - 144)),
                          fillsScreen: fillsScreen)
    }

    private func navigationButton(_ title: String, symbol: String, id: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold, design: .serif))
            }
            .frame(width: 48, height: 44)
            .contentShape(Rectangle())
            .foregroundStyle(CatanTheme.onWaterText)
            .background(PaintedChromeBackground(fill: .color(CatanTheme.waterBackground.opacity(0.94)), cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(navigationLabel(for: id))
        .accessibilityValue(id == "naval.overview" ? discoverySummary : "")
    }

    private func navigationLabel(for identifier: String) -> String {
        switch identifier {
        case "naval.overview": canReturn ? "Return to previous map view" : "Show world overview"
        case "naval.home": "Focus home island"
        default: "Choose a ship"
        }
    }
}
