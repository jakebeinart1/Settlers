import SwiftUI

/// A ghost's or a player's page (Jake, 2026-09-25): games learned from its
/// human, games against humans with self-play on its own line, the spider
/// graph, and style in words.
struct RatedEntityDetailView: View {
    let detail: EntityDetail
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onBack) {
                    Label("Leaderboard", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                }
                .accessibilityIdentifier(AccessibilityID.Leaderboard.back)
                header
                recordBlock
                radarBlock
                if !detail.style.isEmpty { styleBlock }
            }
            .padding(.bottom, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.ratedEntity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.name).font(.system(size: 24, weight: .bold, design: .serif))
                Text(detail.subtitle).font(.system(size: 12, design: .serif)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: String(Int(detail.elo.rounded())))
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(SettingsChrome.ornamentGold)
                Text("Elo").font(.system(size: 11, design: .serif)).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var recordBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let learned = detail.gamesLearned { line("Games learned from its player", "\(learned)") }
            line("Games against humans", "\(detail.record.played)")
            if detail.record.played > 0 {
                line("Won – lost", "\(detail.record.won) – \(detail.record.played - detail.record.won)")
                line("Win rate", "\(Int((detail.record.winRate * 100).rounded()))%")
            }
            if let selfPlay = detail.selfPlay {
                line("Against its own player", "\(selfPlay.won) – \(selfPlay.played - selfPlay.won)")
            }
        }
        .padding(12)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.5))
    }

    @ViewBuilder
    private var radarBlock: some View {
        if let radar = detail.radar {
            VStack(spacing: 6) {
                RadarChartView(ratings: radar, isLearnedFrom: detail.radarIsLearnedFrom)
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier(AccessibilityID.Leaderboard.radar)
                Text(detail.radarIsLearnedFrom
                     ? "Learned from its player's games · Expert is 75"
                     : "1–99 · Expert is 75")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("Not enough games yet for a graph.")
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var styleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style").font(.system(size: 16, weight: .bold, design: .serif))
            ForEach(detail.style, id: \.self) { line in
                Label(line, systemImage: "sparkle").font(.system(size: 14, design: .serif))
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14, design: .serif)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold, design: .serif))
        }
    }
}
