import SwiftUI
import CatanEngine

/// The card family borrows the existing coastal paint and engraved frame.
/// Native borders stay intact at hand, reveal and HUD aspect ratios; commodity
/// art is reused directly rather than mistaking terrain textures for resources.
enum DevCardChrome {
    static let ivory = Color(red: 0.97, green: 0.91, blue: 0.79)
    static let gold = Color(red: 0.89, green: 0.73, blue: 0.37)
    static let ink = Color(red: 0.06, green: 0.13, blue: 0.22)
    static let borderRadius: CGFloat = 8

    @MainActor static func background(_ type: DevCardType) -> PaintedChromeBackground {
        PaintedChromeBackground(fill: .tintedTexture(DevCardStyle.color(for: type)),
                                cornerRadius: borderRadius, notchScale: 0.5)
    }
}

/// A bold illustrated seal, with few interior strokes so it still reads at
/// 24pt. There are no dedicated development-card paintings in approved art.
/// Shield/roads/monument use the board's native outlined silhouette vocabulary;
/// harvest and tribute reuse the approved gold-rimmed resource illustrations.
struct DevCardEmblem: View {
    let type: DevCardType

    var body: some View {
        GeometryReader { geometry in
            emblem
                .frame(width: 100, height: 100)
                .scaleEffect(min(geometry.size.width, geometry.size.height) / 100)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var emblem: some View {
        switch type {
        case .knight: shield
        case .roadBuilding: roads
        case .yearOfPlenty: harvest
        case .monopoly: tribute
        case .victoryPoint: monument
        }
    }

    private var shield: some View {
        ZStack {
            TintedTextureBackground(tint: DevCardChrome.ivory)
                .clipShape(DevCardSilhouette(kind: .shield))
            DevCardSilhouette(kind: .shield)
                .stroke(DevCardChrome.ink, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            DevCardSilhouette(kind: .shield)
                .stroke(DevCardChrome.gold, lineWidth: 2)
                .padding(7)
            Rectangle().fill(DevCardStyle.color(for: .knight))
                .frame(width: 12, height: 51).offset(y: -6)
            Rectangle().fill(DevCardStyle.color(for: .knight))
                .frame(width: 42, height: 11).offset(y: -15)
        }
        .padding(9)
    }

    private var roads: some View {
        ZStack {
            DevCardSilhouette(kind: .roads)
                .stroke(DevCardChrome.ink, style: StrokeStyle(lineWidth: 19, lineCap: .round, lineJoin: .round))
            DevCardSilhouette(kind: .roads)
                .stroke(PaintedChromeBackground.gold, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            DevCardSilhouette(kind: .roads)
                .stroke(DevCardChrome.ivory, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 7]))
        }
        .padding(9)
    }

    private var harvest: some View {
        ZStack {
            commodity(.lumber, size: 44).offset(x: -24, y: 13)
            commodity(.wool, size: 44).offset(x: 24, y: 13)
            commodity(.grain, size: 64).offset(y: -9)
        }
    }

    private var tribute: some View {
        ZStack {
            commodity(.ore, size: 38).offset(x: -27, y: -17)
            commodity(.brick, size: 38).offset(x: 27, y: -17)
            commodity(.grain, size: 42).offset(y: -28)
            TintedTextureBackground(tint: DevCardChrome.gold)
                .clipShape(DevCardSilhouette(kind: .coffer))
                .overlay(DevCardSilhouette(kind: .coffer).stroke(DevCardChrome.ink, lineWidth: 4))
                .frame(width: 67, height: 46).offset(y: 19)
            Rectangle().fill(DevCardChrome.ink)
                .frame(width: 65, height: 4).offset(y: 14)
            Rectangle().fill(DevCardChrome.ivory)
                .frame(width: 9, height: 16).offset(y: 15)
        }
    }

    private var monument: some View {
        ZStack {
            TintedTextureBackground(tint: DevCardChrome.ivory)
                .clipShape(DevCardSilhouette(kind: .pediment))
                .overlay(DevCardSilhouette(kind: .pediment).stroke(DevCardChrome.ink, lineWidth: 4))
            HStack(spacing: 12) {
                ForEach(0..<3) { _ in
                    Rectangle().fill(DevCardChrome.ivory)
                        .frame(width: 10, height: 37)
                        .overlay(Rectangle().stroke(DevCardChrome.ink, lineWidth: 3))
                }
            }
            Rectangle().fill(DevCardChrome.gold)
                .frame(width: 70, height: 9)
                .overlay(Rectangle().stroke(DevCardChrome.ink, lineWidth: 3))
                .offset(y: 27)
        }
        .padding(8)
    }

    private func commodity(_ resource: Resource, size: CGFloat) -> some View {
        Image(CatanTheme.iconImageName(for: resource))
            .resizable().scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Coordinates use a 100-unit square so every size shares the same silhouette.
private struct DevCardSilhouette: Shape {
    enum Kind { case shield, roads, coffer, pediment }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .shield:
            path.move(to: CGPoint(x: 18, y: 12))
            path.addLines([CGPoint(x: 82, y: 12), CGPoint(x: 79, y: 57)])
            path.addQuadCurve(to: CGPoint(x: 50, y: 91), control: CGPoint(x: 77, y: 78))
            path.addQuadCurve(to: CGPoint(x: 21, y: 57), control: CGPoint(x: 23, y: 78))
            path.closeSubpath()
        case .roads:
            path.move(to: CGPoint(x: 15, y: 77))
            path.addLines([CGPoint(x: 48, y: 53), CGPoint(x: 82, y: 24)])
            path.move(to: CGPoint(x: 48, y: 53))
            path.addLine(to: CGPoint(x: 80, y: 76))
        case .coffer:
            path.addLines([CGPoint(x: 3, y: 30), CGPoint(x: 16, y: 5), CGPoint(x: 84, y: 5),
                           CGPoint(x: 97, y: 30), CGPoint(x: 97, y: 94), CGPoint(x: 3, y: 94)])
            path.closeSubpath()
        case .pediment:
            path.addLines([CGPoint(x: 8, y: 33), CGPoint(x: 50, y: 8), CGPoint(x: 92, y: 33)])
            path.closeSubpath()
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

struct DevCardIllustration: View {
    let type: DevCardType

    var body: some View {
        DevCardEmblem(type: type)
            .frame(height: 104)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(DevCardChrome.background(type))
            .accessibilityHidden(true)
    }
}

/// One full readable face for purchase and inspection. Count is supplied by
/// the caller because a reveal describes one new copy, not its entire stack.
struct DevCardFace: View {
    let type: DevCardType
    let countLabel: String

    var body: some View {
        VStack(spacing: 10) {
            DevCardIllustration(type: type)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DevCardStyle.fullName(for: type))
                    .font(.title2.bold())
                    .accessibilityIdentifier(AccessibilityID.DevCards.detail(type))
                Spacer(minLength: 0)
                Text(countLabel).font(.subheadline.bold())
            }
            .foregroundStyle(DevCardChrome.ivory)
            Text(DevCardStyle.effect(for: type))
                .font(.subheadline)
                .foregroundStyle(DevCardChrome.ivory.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fontDesign(.serif)
        .fixedSize(horizontal: false, vertical: true)
    }
}
