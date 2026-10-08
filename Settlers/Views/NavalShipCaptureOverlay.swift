import SwiftUI
import CatanEngine

/// The painted receipt identifies the same hull before and after control
/// changes. It covers the board without changing its camera or reserved layout.
struct NavalShipCaptureOverlay: View {
    let receipt: NavalShipCaptureReceipt
    let state: GameState
    let playerIdentity: (PlayerID) -> PlayerIdentity
    let recoveryMessage: String?
    let onContinue: () -> Void
    let onReloadSavedGame: () -> Void
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.68).ignoresSafeArea()
                ViewThatFits(in: .vertical) {
                    panel(scrolling: false, maxHeight: nil)
                    panel(scrolling: true, maxHeight: max(200, geometry.size.height - 28))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("naval.capture.receipt")
        .onAppear { isTitleFocused = true }
        .transition(.opacity)
    }

    private func panel(scrolling: Bool, maxHeight: CGFloat?) -> some View {
        VStack(spacing: 14) {
            if scrolling {
                ScrollView { content }.scrollIndicators(.visible)
            } else {
                content
            }
            GoldRowButton(title: "Continue", systemImage: "checkmark",
                          iconColor: CatanTheme.cityPennantGold, action: onContinue)
                .accessibilityIdentifier("naval.capture.continue")
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .fontDesign(.serif)
        .foregroundStyle(CatanTheme.onWaterText)
        .padding(18)
        .frame(maxWidth: 366, maxHeight: maxHeight)
        .background(PaintedChromeBackground(fill: .tintedTexture(CatanTheme.waterBackground), cornerRadius: 18))
        .padding(14)
    }

    private var content: some View {
        VStack(spacing: 16) {
            Text(receipt.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
            Text("\(playerIdentity(receipt.newOwner).displayName) now controls this ship.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ownershipChange
            NavalCaptureLocationView(receipt: receipt, state: state,
                                     identity: playerIdentity(receipt.newOwner))
            Text("It stays in the same sea hex. Control lasts until another player steals it on an 11.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let recoveryMessage {
                recovery(recoveryMessage)
            }
        }
    }

    /// The native cover also covers ContentView's recovery controls. Keep the
    /// uncertain acknowledgement recoverable without bypassing its durable write.
    private func recovery(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.caption)
                .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.72))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("naval.capture.save-error")
            GoldRowButton(title: "Reload saved game", systemImage: "arrow.clockwise",
                          action: onReloadSavedGame)
                .accessibilityIdentifier("naval.capture.reload")
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    private var ownershipChange: some View {
        VStack(spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    vessel(receipt.previousOwner)
                    transferArrow
                    vessel(receipt.newOwner)
                }
                ownerName(receipt.previousOwner, caption: "Before")
                ownerName(receipt.newOwner, caption: "Now")
            } else {
                HStack(alignment: .top, spacing: 12) {
                    owner(receipt.previousOwner, caption: "Before")
                    transferArrow.padding(.top, 30)
                    owner(receipt.newOwner, caption: "Now")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ownership changed from \(playerIdentity(receipt.previousOwner).displayName) to \(playerIdentity(receipt.newOwner).displayName)")
    }

    private var transferArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(CatanTheme.cityPennantGold)
            .accessibilityHidden(true)
    }

    private func vessel(_ player: PlayerID) -> some View {
        let identity = playerIdentity(player)
        return NavalShipBadge(color: identity.civilization.accentColor, civilization: identity.civilization)
            .frame(width: 88, height: 88)
    }

    /// Accessible names use the whole card width so a long owner name does
    /// not break into fragments under a fixed-width vessel illustration.
    private func ownerName(_ player: PlayerID, caption: String) -> some View {
        VStack(spacing: 5) {
            Text(caption).font(.caption).foregroundStyle(CatanTheme.cityPennantGold)
            Text(playerIdentity(player).displayName).font(.subheadline.bold())
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func owner(_ player: PlayerID, caption: String) -> some View {
        return VStack(spacing: 5) {
            vessel(player)
            ownerName(player, caption: caption)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A small chart of already-visible neighboring terrain identifies the hull's
/// location without exposing fog or moving the actual gameplay camera.
private struct NavalCaptureLocationView: View {
    let receipt: NavalShipCaptureReceipt
    let state: GameState
    let identity: PlayerIdentity
    private static let tileSize: CGFloat = 27
    private static let chartHeight: CGFloat = 146

    var body: some View {
        GeometryReader { proxy in
            let geometry = chartGeometry(in: proxy.size)
            ZStack {
                Canvas { context, _ in
                    let board = Naval.visibleBoard(in: state)
                    for tile in board.tiles.filter({ $0.coordinate.distance(to: receipt.coordinate) <= 1 }) {
                        if tile.kind == .sea {
                            NavalArtwork.drawSea(tile, geometry: geometry, visibleBoard: board, in: context)
                        } else {
                            TileDrawing.drawTile(tile, geometry: geometry, in: context)
                        }
                    }
                }
                NavalShipBadge(color: identity.civilization.accentColor,
                               civilization: identity.civilization, isSelected: true)
                    .frame(width: 43, height: 43)
                    .position(geometry.center(of: receipt.coordinate))
            }
            .clipped()
        }
        .frame(height: Self.chartHeight)
        .background(CatanTheme.waterBackground, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The captured ship's location on the chart. Its sea hex is unchanged.")
        .accessibilityIdentifier("naval.capture.location")
    }

    private func chartGeometry(in size: CGSize) -> HexGeometry {
        let relative = HexGeometry(origin: .zero, size: Self.tileSize).center(of: receipt.coordinate)
        return HexGeometry(origin: CGPoint(x: size.width / 2 - relative.x, y: size.height / 2 - relative.y),
                           size: Self.tileSize)
    }
}
