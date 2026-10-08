import CoreGraphics
import SwiftUI

/// The movie is a purpose-built public view, never a screenshot of a replay
/// screen which may have a hidden-card breakdown or an unrelated sheet open.
struct ReplayVideoFrameView: View {
    let frame: ReplayExportFrame

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("EMPIRES").font(.system(size: 24, weight: .black, design: .serif))
                Text(frame.status).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(frame.isPartial ? SettingsChrome.ornamentGold : .white.opacity(0.8))
            }
            BoardView(state: frame.boardState, playerIdentity: frame.identity(for:), decision: nil,
                      onSelectTarget: { _ in }, allowsGameCommands: false, animatesStateChanges: false)
                .staticWorldOverview()
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            scores
            Text(frame.caption)
                .font(.system(size: 14, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(3, reservesSpace: true)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            Text("Move \(frame.position) · Public scores · \(frame.reconstructionLabel)")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(background)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private var scores: some View {
        HStack(spacing: 6) {
            ForEach(frame.identities) { identity in
                VStack(spacing: 4) {
                    CivilizationCrest(civilization: identity.civilization, size: 24)
                    Text(identity.displayName).font(.system(size: 11, design: .serif))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(frame.publicScores[identity.seat.index]) public VP")
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
    }

    private var background: some View {
        GeometryReader { geometry in
            ThemedBackgroundImage().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .overlay(Color.black.opacity(0.7))
        }
    }
}

enum ReplayVideoRenderer {
    /// SwiftUI rendering belongs to the main actor. The exporter awaits each
    /// image and hands the immutable CGImage to its isolated encoding actor.
    @MainActor
    static func image(for frame: ReplayExportFrame, configuration: ReplayVideoConfiguration) throws -> CGImage {
        let pointSize = CGSize(width: CGFloat(configuration.width) / 2, height: CGFloat(configuration.height) / 2)
        let view = ReplayVideoFrameView(frame: frame).frame(width: pointSize.width, height: pointSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(pointSize)
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { throw ReplayVideoExportError.renderingFailed }
        return image
    }
}
