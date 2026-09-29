import CatanEngine
import SwiftUI

/// The picture above each walkthrough card, drawn from the game's own art -
/// the same tile paintings, resource cards and civilization pieces a player
/// meets on the board - so "this is a settlement" points at the actual thing.
///
/// Pieces are shown as Rome's, the default civilization, rather than the
/// player's own: this screen opens from the menu, before any game has chosen.
///
/// Every element is drawn with the game's own tokens, not a lookalike (Jake,
/// 2026-09-29: "use the exact theming from the game"): resources are the flat
/// rounded swatches of the HUD and Build popup (the painted resource-card art
/// appears nowhere in play), dice are `GameView.DieFaceView`, number tokens,
/// robber and roads use the board's `CatanTheme` colors and outlines, and
/// development cards use `DevCardStyle` as the hand tiles do.
struct HowToPlayIllustration: View {
    let kind: HowToPlayContent.Illustration

    private static let showcaseCivilization = Civilization.rome
    private static let gold = SettingsChrome.ornamentGold

    var body: some View {
        switch kind {
        case .terrain: terrain
        case .settlement: piece("settlement", height: 110)
        case .city: piece("city", height: 130)
        case .road: road
        case .dice: dice
        case .robber: robber
        case .cards: cards
        case .trade: trade
        case .victory: victory
        }
    }

    private var terrain: some View {
        HStack(spacing: 6) {
            ForEach(Resource.allCases, id: \.self) { resource in
                VStack(spacing: 6) {
                    HexTile(imageName: CatanTheme.textureImageName(for: .resource(resource)))
                        .frame(width: 56, height: 64)
                    ResourceSwatch(resource: resource, size: 24)
                    Text(resource.rawValue.capitalized)
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                }
            }
        }
    }

    private func piece(_ name: String, height: CGFloat) -> some View {
        Image(Self.showcaseCivilization.paintedPieceImageName(isCity: name == "city") ?? "")
            .resizable().scaledToFit()
            .frame(height: height)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
    }

    private var road: some View {
        HStack(spacing: -6) {
            piece("settlement", height: 60)
            // The board's road: the civilization's accent over a near-black
            // border (`BoardView.roadViews`), in the same civilization as the
            // settlement beside it.
            Capsule()
                .fill(Self.showcaseCivilization.accentColor)
                .padding(3)
                .background(Capsule().fill(Color.black.opacity(0.9)))
                .frame(width: 110, height: 18)
                .shadow(color: .black.opacity(0.4), radius: 1.2, y: 1)
                .rotationEffect(.degrees(-20))
            Circle()
                .stroke(Self.gold, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: 40, height: 40)
        }
    }

    private var dice: some View {
        HStack(spacing: 14) {
            GameView.DieFaceView(value: 3, size: 56)
            GameView.DieFaceView(value: 5, size: 56)
            Text("=")
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.6))
            numberToken(8)
        }
    }

    /// The board's number token (`TileDrawing.drawNumberToken`).
    private func numberToken(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 34, weight: .bold, design: .serif))
            .foregroundStyle(number == 6 || number == 8 ? CatanTheme.hotNumber : CatanTheme.coolNumber)
            .frame(width: 60, height: 60)
            .background(Circle().fill(CatanTheme.numberTokenBackground).shadow(color: .black.opacity(0.5), radius: 4, y: 3))
            .overlay(Circle().stroke(CatanTheme.numberTokenEdge, lineWidth: 1.25))
    }

    private var robber: some View {
        // The board's robber (`TileDrawing.drawRobber`): a scrim over the
        // hex, a dark disc with a pennant-gold rim, the hex's number in white.
        ZStack {
            HexTile(imageName: CatanTheme.textureImageName(for: .resource(.grain)))
                .frame(width: 120, height: 138)
                .overlay(HexagonShape().fill(Color.black.opacity(0.45)))
            Circle()
                .fill(CatanTheme.robber)
                .overlay(Circle().stroke(CatanTheme.cityPennantGold, lineWidth: 3))
                .frame(width: 48, height: 48)
            Text("9")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            HStack(spacing: 4) {
                GameView.DieFaceView(value: 3, size: 30)
                GameView.DieFaceView(value: 4, size: 30)
            }
            .offset(x: 84, y: -52)
        }
    }

    private var cards: some View {
        HStack(spacing: -4) {
            devCard(.knight, tilt: -10)
            devCard(.roadBuilding, tilt: 0)
            devCard(.victoryPoint, tilt: 10)
        }
    }

    /// Drawn as `DevCardPopupView`'s hand tile draws a card.
    private func devCard(_ type: DevCardType, tilt: Double) -> some View {
        VStack(spacing: 8) {
            Image(systemName: DevCardStyle.icon(for: type)).font(.system(size: 30))
            Text(DevCardStyle.shortName(for: type))
                .font(.system(size: 12, weight: .bold, design: .serif))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(.white)
        .frame(width: 84, height: 112)
        .background {
            // Opaque underneath so the overlapping cards do not show through
            // each other; the tint on top is the hand tile's own.
            RoundedRectangle(cornerRadius: 11).fill(SettingsChrome.plaqueFill)
            RoundedRectangle(cornerRadius: 11).fill(DevCardStyle.color(for: type).opacity(0.48).gradient)
        }
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.28), lineWidth: 1))
        .rotationEffect(.degrees(tilt))
    }

    private var trade: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in ResourceSwatch(resource: .wool, size: 44) }
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Self.gold)
            ResourceSwatch(resource: .ore, size: 44)
        }
    }

    private var victory: some View {
        ZStack {
            Image(systemName: "star.fill")
                .font(.system(size: 130))
                .foregroundStyle(Self.gold)
            Text("\(Ruleset.forMode(.classic).defaultVictoryPointTarget)")
                .font(.system(size: 38, weight: .black, design: .serif))
                .foregroundStyle(.black)
                .offset(y: 6)
        }
    }
}

/// One tile as the board draws it (`TileDrawing`): a sand frame, and the
/// painting clipped to a hexagon inset to 86% inside it.
private struct HexTile: View {
    let imageName: String

    var body: some View {
        ZStack {
            HexagonShape().fill(CatanTheme.desert)
            HexagonShape().stroke(Color.black.opacity(0.18), lineWidth: 1)
            Image(imageName)
                .resizable().scaledToFill()
                .clipShape(HexagonShape())
                .overlay(HexagonShape().stroke(Color.black.opacity(0.22), lineWidth: 1))
                .scaleEffect(0.86)
        }
    }
}

/// A resource as play shows it: the flat rounded swatch of the HUD hand row
/// and the Build popup's cost chips, not the painted card art.
struct ResourceSwatch: View {
    let resource: Resource
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.17)
            .fill(CatanTheme.color(for: resource))
            .frame(width: size, height: size)
    }
}

/// A pointy-top hexagon filling its frame.
private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.75))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.75))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25))
            path.closeSubpath()
        }
    }
}
