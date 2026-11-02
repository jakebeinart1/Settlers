import SwiftUI

/// The result of this exact match, read from the same ledger as the profile.
/// A missing record is explained rather than manufacturing a rating change.
struct MatchRatingReceiptView: View {
    let matchID: UUID?
    let unratedReason: String?

    @State private var change: PlayerRatingChange?
    @State private var loaded = false
    @State private var showingRatings = false
    @State private var ownerTitle = "Your Elo"

    var body: some View {
        Group {
            if let change {
                Button { showingRatings = true } label: { receipt(change) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("game-over.rating")
            } else if loaded {
                Text(unratedReason ?? "No AI rating was recorded for this game.")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("game-over.unrated")
            } else {
                ProgressView("Loading rating…").font(.footnote)
            }
        }
        .task(id: matchID) { await loadChange() }
        .fullScreenCover(isPresented: $showingRatings, onDismiss: { Task { await loadChange() } }, content: {
            if let change {
                PlayerRatingsView(playerID: change.playerID, initialPool: change.pool,
                                  onDismiss: { showingRatings = false })
            }
        })
    }

    private func receipt(_ change: PlayerRatingChange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ownerTitle).font(.system(.headline, design: .serif))
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.footnote.bold())
            }
            Text("\(change.pool.displayName) · \(change.pool.difficulty.displayName) AI")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.white.opacity(0.8))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    endpoints(change)
                    Spacer(minLength: 12)
                    delta(change)
                }
                VStack(alignment: .leading, spacing: 6) {
                    endpoints(change)
                    delta(change)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill),
                                            cornerRadius: 12, notchScale: 0.6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ownerTitle), \(change.pool.displayName), \(change.pool.difficulty.displayName) AI, "
            + "\(Int(change.before.rounded())) to \(Int(change.after.rounded())), \(signedDelta(change)) Elo")
    }

    private func endpoints(_ change: PlayerRatingChange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(Int(change.before.rounded()))")
                .foregroundStyle(.white.opacity(0.7))
            Image(systemName: "arrow.right").font(.body)
                .foregroundStyle(.white.opacity(0.6))
            Text(verbatim: "\(Int(change.after.rounded()))")
                .foregroundStyle(SettingsChrome.ornamentGold)
        }
        .font(.system(.title2, design: .serif).bold())
        .monospacedDigit()
    }

    private func delta(_ change: PlayerRatingChange) -> some View {
        Text("\(signedDelta(change)) Elo")
            .font(.system(.headline, design: .serif))
            .foregroundStyle(change.won ? SettingsChrome.ornamentGold : Color(red: 1, green: 0.7, blue: 0.62))
            .accessibilityIdentifier("game-over.rating-delta")
    }

    private func signedDelta(_ change: PlayerRatingChange) -> String {
        let value = change.displayedDelta
        return value >= 0 ? "+\(value)" : "−\(abs(value))"
    }

    private func loadChange() async {
        let snapshot = await PlayerRatingSnapshot.load()
        guard !Task.isCancelled else { return }
        change = snapshot.ratings.changes.first { $0.match == matchID }
        if let change {
            ownerTitle = change.playerID == snapshot.me ? "Your Elo" : "\(snapshot.name(for: change.playerID))’s Elo"
            if !loaded { RatingPoolPreference.save(change.pool) }
        }
        loaded = true
    }
}
