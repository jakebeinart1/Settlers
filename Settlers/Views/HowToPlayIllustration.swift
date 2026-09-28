import CatanEngine
import SwiftUI

/// The picture above each walkthrough card, drawn from the game's own art -
/// the same tile paintings, resource cards and civilization pieces a player
/// meets on the board - so "this is a settlement" points at the actual thing.
///
/// Pieces are shown as Rome's, the default civilization, rather than the
/// player's own: this screen opens from the menu, before any game has chosen.
struct HowToPlayIllustration: View {
    let kind: HowToPlayContent.Illustration

    private static let showcaseCivilization = "civ-rome"
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
                    Image(CatanTheme.iconImageName(for: resource))
                        .resizable().scaledToFit()
                        .frame(height: 30)
                    Text(resource.rawValue.capitalized)
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                }
            }
        }
    }

    private func piece(_ name: String, height: CGFloat) -> some View {
        Image("\(Self.showcaseCivilization)-\(name)")
            .resizable().scaledToFit()
            .frame(height: height)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
    }

    private var road: some View {
        HStack(spacing: -6) {
            piece("settlement", height: 60)
            Capsule()
                .fill(CatanTheme.color(for: PlayerID(index: 0)))
                .overlay(Capsule().stroke(Self.gold, lineWidth: 1.5))
                .frame(width: 110, height: 14)
                .rotationEffect(.degrees(-20))
            Circle()
                .stroke(Self.gold, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: 40, height: 40)
        }
    }

    private var dice: some View {
        HStack(spacing: 14) {
            Image(systemName: "die.face.3.fill")
            Image(systemName: "die.face.5.fill")
            Text("=").foregroundStyle(.white.opacity(0.6))
            numberToken(8)
        }
        .font(.system(size: 56))
    }

    private func numberToken(_ number: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(number)")
                .font(.system(size: 30, weight: .bold, design: .serif))
            Text(String(repeating: "•", count: DiceOdds.pips(for: number)))
                .font(.system(size: 12))
        }
        .foregroundStyle(number == 6 || number == 8 ? Color.red : Color.black)
        .frame(width: 70, height: 70)
        .background(Circle().fill(Color(red: 0.96, green: 0.91, blue: 0.78)))
        .overlay(Circle().stroke(Self.gold, lineWidth: 2))
    }

    private var robber: some View {
        ZStack {
            HexTile(imageName: CatanTheme.textureImageName(for: .resource(.grain)))
                .frame(width: 120, height: 138)
                .overlay(HexagonShape().fill(Color.black.opacity(0.45)))
            Circle()
                .fill(CatanTheme.robber)
                .overlay(Circle().stroke(CatanTheme.cityPennantGold, lineWidth: 3))
                .frame(width: 48, height: 48)
            Image(systemName: "7.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white, .red)
                .offset(x: 58, y: -52)
        }
    }

    private var cards: some View {
        HStack(spacing: -4) {
            devCard("shield.fill", label: "Knight", tilt: -10)
            devCard("road.lanes", label: "Roads", tilt: 0)
            devCard("star.fill", label: "Point", tilt: 10)
        }
    }

    private func devCard(_ symbol: String, label: String, tilt: Double) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30))
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .serif))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Self.gold)
        .frame(width: 84, height: 112)
        .background(RoundedRectangle(cornerRadius: 10).fill(SettingsChrome.plaqueFill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.gold, lineWidth: 1.5))
        .rotationEffect(.degrees(tilt))
    }

    private var trade: some View {
        HStack(spacing: 14) {
            HStack(spacing: -22) {
                ForEach(0..<4, id: \.self) { _ in resourceCard(.wool) }
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Self.gold)
            resourceCard(.ore)
        }
    }

    private func resourceCard(_ resource: Resource) -> some View {
        Image(CatanTheme.iconImageName(for: resource))
            .resizable().scaledToFit()
            .frame(height: 80)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 2)
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

/// One tile painting clipped to a pointy-top hexagon, as the board draws it.
private struct HexTile: View {
    let imageName: String

    var body: some View {
        Image(imageName)
            .resizable().scaledToFill()
            .clipShape(HexagonShape())
            .overlay(HexagonShape().stroke(SettingsChrome.ornamentGold.opacity(0.8), lineWidth: 1.5))
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
