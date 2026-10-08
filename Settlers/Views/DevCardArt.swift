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

/// Painted emblem in the board pieces' rugged style (thick ink outline,
/// crackled flat fill), one colour scheme per card so it reads at 28pt.
/// Source art and how it was made: `design-references/approved/dev-cards/`.
struct DevCardEmblem: View {
    let type: DevCardType

    var body: some View {
        Image(Self.imageName(for: type))
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    static func imageName(for type: DevCardType) -> String {
        switch type {
        case .knight: return "devcard-knight"
        case .roadBuilding: return "devcard-road-building"
        case .yearOfPlenty: return "devcard-year-of-plenty"
        case .monopoly: return "devcard-monopoly"
        case .victoryPoint: return "devcard-victory-point"
        }
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
