import SwiftUI
import CatanEngine

/// The card family borrows the existing coastal paint and engraved frame.
/// Native borders stay intact at hand, reveal and HUD aspect ratios.
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
/// Every emblem shares one engraved silhouette family. Cream paper, painted
/// gold and a dark rim retain their identity even in the compact hand shelf.
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

    /// A single crest reads as protection without miniature heraldic detail.
    private var shield: some View {
        ZStack {
            ZStack {
                TintedTextureBackground(tint: DevCardChrome.ivory)
                DevCardSilhouette(kind: .crest).fill(DevCardChrome.gold)
                    .frame(width: 32, height: 43).offset(y: -5)
            }
            .clipShape(DevCardSilhouette(kind: .shield))
            DevCardSilhouette(kind: .shield)
                .stroke(DevCardChrome.ink, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            DevCardSilhouette(kind: .shield)
                .stroke(DevCardChrome.gold, lineWidth: 2)
                .padding(7)
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

    /// Two cards from the bank: two resource squares, fanned. The same
    /// squares the HUD and trade use - never the hex commodity art, which
    /// turned into clutter at hand-badge size.
    private var harvest: some View {
        ZStack {
            card(.lumber).rotationEffect(.degrees(-12)).offset(x: -13, y: 4)
            card(.grain).rotationEffect(.degrees(10)).offset(x: 13, y: -4)
        }
    }

    /// A coffer: Monopoly takes every card of one kind into one chest.
    private var tribute: some View {
        ZStack {
            TintedTextureBackground(tint: DevCardChrome.gold)
                .clipShape(DevCardSilhouette(kind: .coffer))
                .overlay(DevCardSilhouette(kind: .coffer).stroke(DevCardChrome.ink, lineWidth: 4))
                .frame(width: 82, height: 68)
            Rectangle().fill(DevCardChrome.ink)
                .frame(width: 77, height: 4).offset(y: -2)
            HStack(spacing: 42) {
                Rectangle().frame(width: 5, height: 36)
                Rectangle().frame(width: 5, height: 36)
            }
            .foregroundStyle(DevCardChrome.ink.opacity(0.8)).offset(y: 11)
            Rectangle().fill(DevCardChrome.ivory)
                .frame(width: 10, height: 18).offset(y: 2)
        }
    }

    private var monument: some View {
        ZStack {
            Image(systemName: "laurel.leading").offset(x: -29, y: 8)
            Image(systemName: "laurel.trailing").offset(x: 29, y: 8)
            Image(systemName: "star.fill")
                .font(.system(size: 60, weight: .regular))
                .foregroundStyle(DevCardChrome.gold)
                .shadow(color: DevCardChrome.ink, radius: 0, x: 2, y: 3)
        }
        .font(.system(size: 45)).foregroundStyle(DevCardChrome.ivory)
    }

    /// A resource square sized for the 100-unit emblem space, inked so it
    /// separates from the card's own painted colour.
    private func card(_ resource: Resource, size: CGFloat = 46) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(DevCardChrome.ivory)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DevCardChrome.ink, lineWidth: 4))
            .overlay(ResourceSquare(resource: resource, size: size * 0.45))
            .frame(width: size, height: size * 1.3)
    }
}

/// Coordinates use a 100-unit square so every size shares the same silhouette.
private struct DevCardSilhouette: Shape {
    enum Kind { case shield, roads, coffer, crest }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .shield:
            path.move(to: CGPoint(x: 18, y: 12))
            path.addLine(to: CGPoint(x: 82, y: 12))
            path.addLine(to: CGPoint(x: 79, y: 57))
            path.addQuadCurve(to: CGPoint(x: 50, y: 91), control: CGPoint(x: 77, y: 78))
            path.addQuadCurve(to: CGPoint(x: 21, y: 57), control: CGPoint(x: 23, y: 78))
            path.closeSubpath()
        case .roads:
            path.move(to: CGPoint(x: 15, y: 77))
            path.addLine(to: CGPoint(x: 48, y: 30))
            path.addLine(to: CGPoint(x: 85, y: 65))
        case .coffer:
            path.move(to: CGPoint(x: 4, y: 46))
            path.addQuadCurve(to: CGPoint(x: 50, y: 5), control: CGPoint(x: 7, y: 5))
            path.addQuadCurve(to: CGPoint(x: 96, y: 46), control: CGPoint(x: 93, y: 5))
            path.addLine(to: CGPoint(x: 96, y: 94))
            path.addLine(to: CGPoint(x: 4, y: 94))
            path.closeSubpath()
        case .crest:
            path.addLines([CGPoint(x: 50, y: 4), CGPoint(x: 90, y: 45),
                           CGPoint(x: 50, y: 96), CGPoint(x: 10, y: 45)])
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
    var isCompact = false

    var body: some View {
        VStack(spacing: 10) {
            if !isCompact { DevCardIllustration(type: type) }
            HStack(spacing: 12) {
                if isCompact {
                    DevCardEmblem(type: type).frame(width: 44, height: 44)
                        .padding(6).background(DevCardChrome.background(type))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(DevCardStyle.fullName(for: type))
                        .font(.title2.bold())
                        .accessibilityIdentifier(AccessibilityID.DevCards.detail(type))
                    Text(countLabel).font(.caption).foregroundStyle(DevCardChrome.ivory.opacity(0.8))
                }
                Spacer(minLength: 0)
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
