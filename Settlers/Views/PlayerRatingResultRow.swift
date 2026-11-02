import SwiftUI

/// A recorded result and its rating receipt stay together, so a number such
/// as +12 always answers which game earned it and which ladder it belongs to.
struct PlayerRatingResultRow: View {
    let change: PlayerRatingChange
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { expandedRow } else { compactRow }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ratings.result.\(change.match.uuidString)")
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 12) {
            resultSymbol.font(.system(.title3)).frame(width: 25)
            VStack(alignment: .leading, spacing: 4) { resultTitle; resultDate }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) { resultDelta; ratingRange }
        }
    }

    private var expandedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                resultSymbol.font(.system(size: 22)).frame(width: 25)
                resultTitle.fixedSize(horizontal: false, vertical: true)
            }
            resultDate.fixedSize(horizontal: false, vertical: true)
            resultDelta.lineLimit(1).minimumScaleFactor(0.7)
            ratingRange.lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultSymbol: some View {
        Image(systemName: change.won ? "checkmark.seal" : "flag")
            .foregroundStyle(change.won ? RatingPresentation.gain : .white.opacity(0.7))
            .accessibilityHidden(true)
    }

    private var resultTitle: some View {
        Text(change.abandoned ? "Restarted · loss" : change.won ? "Won" : "Lost")
            .font(.system(.subheadline, design: .serif, weight: .semibold))
    }

    private var resultDate: some View {
        Text(change.date.formatted(date: .abbreviated, time: .shortened))
            .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
    }

    private var resultDelta: some View {
        Text("\(RatingPresentation.delta(change.displayedDelta)) Elo")
            .font(.system(.headline, design: .serif))
            .foregroundStyle(change.won ? RatingPresentation.gain : RatingPresentation.loss)
    }

    private var ratingRange: some View {
        Text("\(Int(change.before.rounded())) → \(Int(change.after.rounded()))")
            .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.75))
    }
}

/// The explanation is secondary to a readable result. It lives behind one
/// information button rather than repeating the arithmetic on every screen.
struct PlayerRatingHelpView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            PaintedScreenBackground()
            VStack(spacing: 12) {
                HStack {
                    Text("About ratings").font(.system(.title2, design: .serif, weight: .bold))
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.system(size: 22)) }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Close rating information")
                        .accessibilityIdentifier("ratings.help-close")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        explanation("A rating for each challenge", "Classic, Conquest, Vast and Naval each have separate records. "
                            + "Classic AI and Expert AI are separate ladders too. There is no combined Elo across modes.")
                        explanation("One game, one result", "Beat the table to gain Elo. A loss lowers it. "
                            + "Every player and the shared AI entry start each ladder at 1000. At the same Elo as the AI, "
                            + "a player is expected to win one game in four against three opponents. The AI's rating "
                            + "changes once per game, in the opposite direction to the player's.")
                        explanation("Which games count", "Restarting or replacing an unfinished rated game counts as a loss. "
                            + "Returning to the menu and resuming later does not. Ghost tables and pass-and-play games "
                            + "stay outside these AI-only ratings.")
                        explanation("Your earlier games", "Existing rated Classic Standard games against ordinary AI are "
                            + "recalculated in their matching difficulty. Older Naval, Vast and Conquest recordings "
                            + "without a verified player identity and recorded AI difficulty are not guessed into a ladder.")
                        explanation("The same player on every device", "Your iCloud account keeps your identity. "
                            + "Changing your name keeps your games and ratings. Records sync across your devices and "
                            + "appear in other players' standings when connected. Pull down on your record to refresh "
                            + "shared standings.")
                        explanation("When older games arrive", "Ratings follow games in date order. If a device syncs "
                            + "an older result, later ratings and game-by-game changes are recalculated so everyone with "
                            + "the same games sees the same record.")
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(20)
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .presentationDetents([.large])
    }

    private func explanation(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(.headline, design: .serif)).foregroundStyle(SettingsChrome.ornamentGold)
            Text(message).font(.system(.body, design: .serif)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
