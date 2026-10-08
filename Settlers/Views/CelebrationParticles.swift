import SwiftUI

/// Falling particles for the end of the victory cutscene: tumbling confetti
/// for a win, slow rain for a loss. Every particle is a pure function of its
/// index and the elapsed time, so there is no particle state to step.
struct CelebrationParticles: View {
    enum Mood { case confetti([Color]), rain }

    let mood: Mood
    private let count = 70
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                for index in 0..<count { draw(index, at: elapsed, in: &context, size: size) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ index: Int, at elapsed: TimeInterval, in context: inout GraphicsContext, size: CGSize) {
        let seed = Double(index)
        let x = fraction(seed * 12.9898) * size.width
        let speed = isRain ? 420 + 260 * fraction(seed * 3.1) : 140 + 120 * fraction(seed * 3.1)
        let delay = fraction(seed * 7.7) * (isRain ? 1.2 : 0.6)
        // Confetti bursts in once; rain loops for as long as it is shown.
        let travel = max(0, elapsed - delay) * speed
        let span = size.height + 40
        let y = isRain ? travel.truncatingRemainder(dividingBy: span) - 20 : travel - 20
        guard y < size.height + 20, elapsed > delay else { return }
        switch mood {
        case .confetti(let colors):
            let sway = sin(elapsed * 3 + seed) * 18
            var piece = context
            piece.translateBy(x: x + sway, y: y)
            piece.rotate(by: .radians(elapsed * (2 + fraction(seed) * 4) + seed))
            piece.fill(Path(CGRect(x: -4, y: -2.5, width: 8, height: 5)),
                       with: .color(colors[index % colors.count]))
        case .rain:
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - 3, y: y + 16))
            context.stroke(drop, with: .color(Color(red: 0.62, green: 0.72, blue: 0.86).opacity(0.55)), lineWidth: 1.6)
        }
    }

    private var isRain: Bool {
        if case .rain = mood { return true }
        return false
    }

    /// Deterministic 0..<1 from a seed - the classic shader hash.
    private func fraction(_ value: Double) -> Double {
        let hashed = sin(value) * 43_758.5453
        return hashed - hashed.rounded(.down)
    }
}
