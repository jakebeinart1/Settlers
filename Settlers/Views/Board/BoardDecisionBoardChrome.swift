import SwiftUI
import CatanEngine

/// The piece carried by the board-side cradle while a spatial choice is open.
///
/// This is deliberately presentation vocabulary rather than a `GameMove`.
/// Dragging the piece can only produce a `BoardTarget`; the decision dock owns
/// confirmation and the view model remains the only route to durable state.
enum BoardDecisionPieceKind: Equatable {
    case road
    case settlement
    case city
    case robber

    init(intent: BoardDecisionIntent) {
        switch intent {
        case .initialRoad, .buildRoad, .roadBuilding: self = .road
        case .initialSettlement, .buildSettlement: self = .settlement
        case .buildCity: self = .city
        case .robberAfterSeven, .knight: self = .robber
        }
    }
}

/// A compact painted tray that keeps the active piece visible off the map.
///
/// The cradle never commits an action. Its drag gesture is attached by
/// `BoardView`, in the board's coordinate space, so tap and drag both end at
/// the same typed target callback.
struct BoardDecisionCradle: View {
    let piece: BoardDecisionPieceKind
    let civilization: Civilization
    let roadOrdinal: Int?
    let isDragging: Bool
    let accessibilityLabel: String

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(cradleFill)
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.82), lineWidth: 3)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .inset(by: 3)
                    .strokeBorder(CatanTheme.cityPennantGold, lineWidth: 2)
                BoardDecisionPieceGlyph(
                    piece: piece,
                    civilization: civilization,
                    roadOrdinal: roadOrdinal,
                    size: 38
                )
            }
            .frame(width: 54, height: 50)

            Text("DRAG")
                .font(.system(size: 8, weight: .black, design: .serif))
                .tracking(1.2)
                .foregroundStyle(CatanTheme.cityPennantGold)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 13))
        .shadow(color: .black.opacity(0.52), radius: 3, x: 0, y: 2)
        .opacity(isDragging ? 0.42 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.Board.dragCradle)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("Uncommitted piece")
        .accessibilityHint("Drag to a highlighted board target, or tap a highlighted target.")
    }

    private var cradleFill: LinearGradient {
        LinearGradient(
            colors: [
                CatanTheme.panelBackground.opacity(0.97),
                Color(red: 0.045, green: 0.12, blue: 0.22).opacity(0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The piece that follows the finger during a drag. It is intentionally larger
/// than the cradle copy so the destination remains readable beneath a thumb.
struct BoardDecisionDragToken: View {
    let piece: BoardDecisionPieceKind
    let civilization: Civilization
    let roadOrdinal: Int?

    var body: some View {
        BoardDecisionPieceGlyph(
            piece: piece,
            civilization: civilization,
            roadOrdinal: roadOrdinal,
            size: 46
        )
        .padding(7)
        .background(Color.black.opacity(0.42), in: Circle())
        .overlay(Circle().stroke(CatanTheme.cityPennantGold, lineWidth: 3))
        .shadow(color: CatanTheme.cityPennantGold.opacity(0.55), radius: 5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Exact civilization artwork inside a dashed gold proposal seal. The artwork
/// is translucent and the seal supplies a non-color-only cue that this is not
/// yet committed state.
struct ProvisionalBuildingBadge: View {
    let civilization: Civilization
    let isCity: Bool
    let size: CGFloat
    let accessibilityLabel: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.2))
            Circle()
                .stroke(
                    CatanTheme.cityPennantGold,
                    style: StrokeStyle(lineWidth: max(2, size * 0.075), dash: [5, 3])
                )
            CivilizationBadge(civilization: civilization, isCity: isCity, size: size * 0.86)
                .opacity(0.8)
        }
        .frame(width: size, height: size)
        .shadow(color: CatanTheme.cityPennantGold.opacity(0.65), radius: 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.Board.stagedBuildingPreview)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("Proposed, not yet built")
    }
}

/// Small numbered seals keep Road Building's two selected edges visibly
/// ordered without painting a second road style over the board.
struct BoardRoadOrderBadge: View {
    let ordinal: Int

    var body: some View {
        Text("\(ordinal)")
            .font(.system(size: 10, weight: .black, design: .serif))
            .foregroundStyle(Color.black.opacity(0.86))
            .frame(width: 18, height: 18)
            .background(CatanTheme.cityPennantGold, in: Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.86), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct BoardDecisionPieceGlyph: View {
    let piece: BoardDecisionPieceKind
    let civilization: Civilization
    let roadOrdinal: Int?
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        switch piece {
        case .road:
            roadGlyph
        case .settlement:
            CivilizationBadge(civilization: civilization, isCity: false, size: size)
        case .city:
            CivilizationBadge(civilization: civilization, isCity: true, size: size)
        case .robber:
            robberGlyph
        }
    }

    private var roadGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.9))
                .frame(width: size, height: size * 0.34)
            RoundedRectangle(cornerRadius: 2)
                .fill(civilization.accentColor)
                .frame(width: size * 0.86, height: size * 0.2)
            if let roadOrdinal {
                Text("\(roadOrdinal)")
                    .font(.system(size: size * 0.28, weight: .black, design: .serif))
                    .foregroundStyle(.white)
            }
        }
        .rotationEffect(.degrees(-24))
    }

    private var robberGlyph: some View {
        ZStack {
            Circle()
                .fill(CatanTheme.robber)
            Circle()
                .strokeBorder(CatanTheme.cityPennantGold, lineWidth: max(2, size * 0.08))
            VStack(spacing: -size * 0.04) {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: size * 0.22, height: size * 0.22)
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: size * 0.38, height: size * 0.34)
            }
        }
        .frame(width: size, height: size)
    }
}
