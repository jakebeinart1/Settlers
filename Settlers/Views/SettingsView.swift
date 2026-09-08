import SwiftUI
import CatanEngine

/// Surface C: next-match defaults and the running totals they produce. Nothing
/// edited here is the source of truth for a running match.
///
/// The archive of played games used to live here too, as a "Game Logs" section
/// opening a list of `String(describing:)` move dumps. It is now `Game History`
/// on the main menu, one tap from the title screen and shown as a replayable
/// board - a thing a player looks at, rather than a diagnostic buried behind a
/// gear icon (2026-09-07).
public struct SettingsView: View {
    public let onDismiss: () -> Void

    private let onResetStatistics: () -> Bool

    public init(onDismiss: @escaping () -> Void, statistics: GameStats = GameStats(),
                onResetStatistics: @escaping () -> Bool = { false }) {
        self.onDismiss = onDismiss
        self.onResetStatistics = onResetStatistics
        _stats = State(initialValue: statistics)
    }

    @State private var settings = CivilizationSettingsStore.shared.load()
    @State private var playerName = PlayerNameStore.shared.load()
    @State private var stats: GameStats
    @State private var resetFailed = false
    @State private var isShowingResetStatsConfirmation = false
    @State private var poolRefusal: String?

    public var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 28) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        yourNameSection
                        yourCivilizationSection
                        randomPoolSection
                        resetStatsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .confirmationDialog(
            "Reset all stats?",
            isPresented: $isShowingResetStatsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Stats", role: .destructive) {
                if onResetStatistics() { stats = GameStats() } else { resetFailed = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your games played, win rate, and average VP/time. It can't be undone.")
        }
        .alert("Stats could not be reset", isPresented: $resetFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your recorded totals have not been changed. Please try again.")
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: - Your name

    /// The name prefilled for the first human on the next New Game screen.
    /// Active matches keep the name they started with. Saves on every
    /// keystroke via `onChange` rather than only on dismiss/blur -
    /// there's no separate "Done" step in this screen for a text field to
    /// wait for, and `PlayerNameStore.save` is cheap enough (one
    /// `UserDefaults` write) that debouncing isn't worth the complexity.
    private var yourNameSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Name")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            TextField("You", text: $playerName)
                .textFieldStyle(.plain)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
                .autocorrectionDisabled()
                .onChange(of: playerName) { _, newValue in
                    PlayerNameStore.shared.save(newValue)
                }
        }
    }

    // MARK: - Your civilization

    private var yourCivilizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Civilization")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            Text("Used for your seat the next time you configure a new game.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: 10) {
                ForEach(Civilization.allCases, id: \.self) { civilization in
                    Button {
                        selectYourCivilization(civilization)
                    } label: {
                        civilizationRow(
                            civilization,
                            subtitle: "General \(civilization.generalName)",
                            isSelected: civilization == settings.yourCivilization
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func selectYourCivilization(_ civilization: Civilization) {
        settings.yourCivilization = civilization
        persist()
    }

    // MARK: - Random civilization pool

    private var randomPoolSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Random Civilization Pool")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            Text("Every seat left on Random draws only from this pool. Keep at least \(CivilizationSettings.minimumEligibleCivilizations) available.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            if let poolRefusal {
                Text(poolRefusal)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 10) {
                ForEach(Civilization.allCases, id: \.self) { civilization in
                    let isIncluded = settings.eligibleRandomCivilizations.contains(civilization)

                    Button {
                        toggleRandomPool(civilization)
                    } label: {
                        civilizationRow(
                            civilization,
                            subtitle: civilization.generalName,
                            isSelected: isIncluded
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Reset stats

    private var resetStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stats")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 8) {
                stat(value: "\(stats.gamesPlayed)", label: "Played")
                stat(value: "\(Int((stats.winRate * 100).rounded()))%", label: "Win Rate")
                stat(value: formattedDuration(stats.averageDurationSeconds), label: "Avg Time")
                stat(value: String(format: "%.1f", stats.averageFinalVP), label: "Avg VP")
            }

            Button {
                isShowingResetStatsConfirmation = true
            } label: {
                Text("Reset Stats")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleRandomPool(_ civilization: Civilization) {
        let isIncluded = settings.eligibleRandomCivilizations.contains(civilization)
        poolRefusal = settings.setRandomEligibility(civilization, isEligible: !isIncluded)
        guard poolRefusal == nil else { return }
        persist()
    }

    private func persist() {
        CivilizationSettingsStore.shared.save(settings)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.14)))
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: - Shared row

    private func civilizationRow(
        _ civilization: Civilization,
        subtitle: String,
        isSelected: Bool,
        selectionSymbol: String = "checkmark.circle.fill"
    ) -> some View {
        HStack(spacing: 12) {
            // Settlement and city side by side (city slightly larger, same
            // proportion as they read against each other on the board) so
            // picking a civilization shows off both tiers of its piece art
            // at once, not just the settlement.
            HStack(spacing: 6) {
                CivilizationBadge(civilization: civilization, isCity: false, size: 34)
                CivilizationBadge(civilization: civilization, isCity: true, size: 34)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(civilization.displayName)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: isSelected ? selectionSymbol : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? civilization.accentColor : .white.opacity(0.3))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
    }
}

#Preview {
    SettingsView(onDismiss: {})
}
