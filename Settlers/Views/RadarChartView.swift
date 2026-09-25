import SwiftUI

/// The FIFA-style spider graph (Jake, 2026-09-25): six axes rated 1-99, with
/// Expert's 75 drawn as a faint reference ring. Drawn with `Path`, because
/// Swift Charts has no radar chart and no dependency is worth one view.
/// Dashed when the numbers are borrowed from the ghost's person.
struct RadarChartView: View {
    let ratings: [RadarAxis: Int]
    var isLearnedFrom = false

    private static let axes = RadarAxis.allCases
    private static let labelInset: CGFloat = 44
    /// How far outside the 99 ring a label sits, so a 99 vertex never touches it.
    private static let labelGap: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - Self.labelInset
            ZStack {
                ForEach([25, 50, 75, 99], id: \.self) { ring in
                    polygon(centre: centre, radius: radius) { _ in Double(ring) }
                        .stroke(Color.white.opacity(ring == 75 ? 0.35 : 0.12), lineWidth: ring == 75 ? 1 : 0.5)
                }
                spokes(centre: centre, radius: radius)
                polygon(centre: centre, radius: radius) { Double(ratings[$0] ?? 1) }
                    .fill(SettingsChrome.ornamentGold.opacity(0.28))
                polygon(centre: centre, radius: radius) { Double(ratings[$0] ?? 1) }
                    .stroke(SettingsChrome.ornamentGold,
                            style: StrokeStyle(lineWidth: 2, dash: isLearnedFrom ? [5, 4] : []))
                ForEach(Array(Self.axes.enumerated()), id: \.offset) { index, axis in
                    label(axis, at: point(index, value: 99, centre: centre, radius: radius + Self.labelGap))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.axes.map { "\($0.title) \(ratings[$0] ?? 0)" }.joined(separator: ", "))
    }

    private func point(_ index: Int, value: Double, centre: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(Self.axes.count)
        let scaled = radius * CGFloat(value / 99)
        return CGPoint(x: centre.x + scaled * CGFloat(cos(angle)), y: centre.y + scaled * CGFloat(sin(angle)))
    }

    private func polygon(centre: CGPoint, radius: CGFloat, value: @escaping (RadarAxis) -> Double) -> Path {
        Path { path in
            for (index, axis) in Self.axes.enumerated() {
                let corner = point(index, value: value(axis), centre: centre, radius: radius)
                if index == 0 { path.move(to: corner) } else { path.addLine(to: corner) }
            }
            path.closeSubpath()
        }
    }

    private func spokes(centre: CGPoint, radius: CGFloat) -> some View {
        Path { path in
            for index in Self.axes.indices {
                path.move(to: centre)
                path.addLine(to: point(index, value: 99, centre: centre, radius: radius))
            }
        }
        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
    }

    private func label(_ axis: RadarAxis, at position: CGPoint) -> some View {
        VStack(spacing: 0) {
            Text("\(ratings[axis] ?? 0)")
                .font(.system(size: 15, weight: .bold, design: .serif))
            Text(axis.title)
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .foregroundStyle(.white.opacity(0.75))
        }
        .position(position)
    }
}
