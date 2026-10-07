import SwiftUI

struct MatchSettingHelpEntry: Identifiable {
    let title: String
    let detail: String
    var id: String { title }

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    static func board(naval: Bool) -> [MatchSettingHelpEntry] {
        if naval {
            return [
                .init("Surprise me", "Choose an island family at random for each new match."),
                .init("Archipelago", "Several separate island groups, with multiple directions to explore."),
                .init("Peninsula", "A branching coastline with smaller offshore islands."),
                .init("Twin Islands", "Two larger island groups with smaller neighboring islands.")
            ]
        }
        return [
            .init("Standard", "Use the same terrain and number layout each game."),
            .init("Randomized", "Reshuffle terrain and production numbers for a different board each game.")
        ]
    }
}

/// Named option descriptions share one quiet, opaque plaque. Separating the
/// choices makes comparison readable without adding an info icon to every chip.
struct MatchSettingHelpView: View {
    let entries: [MatchSettingHelpEntry]
    let identifier: String
    @ScaledMetric(relativeTo: .body) private var textSize = 13.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: min(22, textSize + 1), weight: .bold, design: .serif))
                        .foregroundStyle(CatanTheme.cityPennantGold)
                    Text(entry.detail)
                        .font(.system(size: min(20, textSize), design: .serif))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PaintedChromeBackground(
            fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
