import SwiftUI

/// Red velvet stage curtains that part to open the victory cutscene (Jake,
/// 2026-10-08: "a fading screen then a curtain appears and the curtain opens
/// to the animation beginning"). Drawn natively, not painted: the two halves
/// slide off-screen, so they must stay crisp at any width and cost no art.
struct TheatreCurtain: View {
    /// 0 is closed, 1 is fully open (each half has slid its own width out).
    var openness: CGFloat
    var title: String?

    private static let folds = 7
    private static let valanceHeight: CGFloat = 54
    private static let velvet = Color(red: 0.50, green: 0.05, blue: 0.08)
    private static let shadow = Color(red: 0.22, green: 0.01, blue: 0.03)
    private static let gold = CatanTheme.cityPennantGold

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            ZStack(alignment: .top) {
                drape.frame(width: half).offset(x: -half * openness)
                    .frame(maxWidth: .infinity, alignment: .leading)
                drape.frame(width: half).offset(x: half * openness)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let title {
                    titlePlaque(title)
                        .opacity(1 - openness * 2)
                        .frame(maxHeight: .infinity)
                }
                valance
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Vertical folds: light velvet crests between dark troughs, and a gold
    /// fringe along the hem.
    private var drape: some View {
        LinearGradient(stops: Self.foldStops, startPoint: .leading, endPoint: .trailing)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Self.gold).frame(height: 10)
                    .overlay(Rectangle().fill(Self.shadow.opacity(0.5)).frame(height: 2), alignment: .top)
            }
            .shadow(color: .black.opacity(0.6), radius: 12)
    }

    private static var foldStops: [Gradient.Stop] {
        (0...folds * 2).map { index in
            let crest = index.isMultiple(of: 2)
            return Gradient.Stop(color: crest ? velvet : shadow, location: CGFloat(index) / CGFloat(folds * 2))
        }
    }

    private var valance: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Self.shadow, Self.velvet], startPoint: .top, endPoint: .bottom))
            .frame(height: Self.valanceHeight)
            .overlay(alignment: .bottom) { Rectangle().fill(Self.gold).frame(height: 5) }
            .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
    }

    private func titlePlaque(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .black, design: .serif))
            .tracking(2)
            .foregroundStyle(Self.gold)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(PaintedChromeBackground(fill: .color(Color(white: 0.06)), cornerRadius: 12))
    }
}
