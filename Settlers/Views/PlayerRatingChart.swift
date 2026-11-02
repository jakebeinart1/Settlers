import SwiftUI

/// A rating's actual game-by-game path, including its starting value. There is
/// no smoothing: a curve must not invent ratings between the recorded results.
struct PlayerRatingChart: View {
    let changes: [PlayerRatingChange]

    private var values: [Double] { (changes.first.map { [$0.before] } ?? []) + changes.map(\.after) }
    private var range: ClosedRange<Double> {
        (min(1000, values.min() ?? 1000) - 8)...(max(1000, values.max() ?? 1000) + 8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rating history").font(.system(.subheadline, design: .serif, weight: .semibold))
                Spacer()
                Text("\(changes.count) \(changes.count == 1 ? "game" : "games")")
                    .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 8) {
                VStack(alignment: .trailing) {
                    Text("\(Int(range.upperBound.rounded()))")
                    Spacer()
                    Text("\(Int(range.lowerBound.rounded()))")
                }
                .font(.system(.caption2, design: .serif)).foregroundStyle(.white.opacity(0.65))
                .padding(.vertical, 1)
                GeometryReader { geometry in
                    let points = points(in: geometry.size)
                    ZStack {
                        grid
                        line(points).stroke(SettingsChrome.ornamentGold, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                        if let last = points.last {
                            Circle().fill(SettingsChrome.ornamentGold).frame(width: 7, height: 7).position(last)
                        }
                    }
                }
            }
            .frame(height: 92)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartDescription)
            .accessibilityIdentifier("ratings.chart")
            HStack {
                Text(changes.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                Spacer()
                Text(changes.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
            }
            .font(.system(.caption2, design: .serif))
            .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var grid: some View {
        VStack {
            ForEach(0..<3) { index in
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                if index < 2 { Spacer() }
            }
        }
        .padding(.vertical, 6)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let values = values
        guard !values.isEmpty else { return [] }
        let lowest = range.lowerBound
        let highest = range.upperBound
        return values.enumerated().map { index, value in
            CGPoint(x: 4 + (size.width - 8) * Double(index) / Double(max(1, values.count - 1)),
                    y: 6 + (size.height - 12) * (1 - (value - lowest) / (highest - lowest)))
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private var chartDescription: String {
        guard let first = changes.first, let last = changes.last else { return "No rated games yet" }
        return "Rating history across \(changes.count) games, from \(Int(first.before.rounded())) "
            + "to \(Int(last.after.rounded())). Individual changes follow in the game record."
    }
}
