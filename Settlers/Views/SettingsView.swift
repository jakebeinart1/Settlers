import SwiftUI
import CatanEngine

/// The civilization picker: choose your own civilization, and which of the
/// other 7 are in the mix for the 3 bot seats. Both write straight to
/// `CivilizationSettingsStore` on change and only take effect on the next
/// "New Game" - the in-progress game (if any) keeps whatever it was dealt
/// when it started (see `CivilizationAssignmentStore`). Matches
/// `MainMenuView`'s flat, dark, colonist.io-style look.
public struct SettingsView: View {
    public let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    @State private var settings = CivilizationSettingsStore.shared.load()
    @State private var playerName = PlayerNameStore.shared.load()
    @State private var isShowingResetStatsConfirmation = false

    private var otherCivilizations: [Civilization] {
        Civilization.allCases.filter { $0 != settings.yourCivilization }
    }

    /// Below this many included bots, `SettingsView` won't let the player
    /// uncheck any more - see `CivilizationSettings.minimumIncludedBots`.
    private var isAtMinimumRoster: Bool {
        settings.includedBotCivilizations.count <= CivilizationSettings.minimumIncludedBots
    }

    public var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 28) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        yourNameSection
                        yourCivilizationSection
                        botRosterSection
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
                GameStatsStore.shared.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your games played, win rate, and average VP/time. It can't be undone.")
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

    /// The name shown everywhere `CatanTheme.playerLabel(for:)` is read for
    /// the human seat - bot trade offers, the robber victim picker, the
    /// end-game standings, and the "You" row of your own HUD panel. Saves
    /// on every keystroke via `onChange` rather than only on dismiss/blur -
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
        // Your own civilization can't also be drawn for a bot seat.
        settings.includedBotCivilizations.remove(civilization)
        if settings.includedBotCivilizations.count < CivilizationSettings.minimumIncludedBots {
            let topUp = Civilization.allCases.filter { $0 != civilization && !settings.includedBotCivilizations.contains($0) }
            settings.includedBotCivilizations.formUnion(topUp.prefix(CivilizationSettings.minimumIncludedBots - settings.includedBotCivilizations.count))
        }
        persist()
    }

    // MARK: - Bot roster

    private var botRosterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bot Roster")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            Text("Who's in the mix for the 3 bot seats - drawn at random each new game. At least \(CivilizationSettings.minimumIncludedBots) must stay checked.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: 10) {
                ForEach(otherCivilizations, id: \.self) { civilization in
                    let isIncluded = settings.includedBotCivilizations.contains(civilization)
                    // Once at the minimum roster size, the still-checked
                    // rows can't be unchecked further - dim them so that's
                    // visible rather than just silently ignoring the tap.
                    let isLockedIn = isIncluded && isAtMinimumRoster

                    Button {
                        toggleBotRoster(civilization)
                    } label: {
                        civilizationRow(
                            civilization,
                            subtitle: civilization.generalName,
                            isSelected: isIncluded
                        )
                        .opacity(isLockedIn ? 0.5 : 1)
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

    private func toggleBotRoster(_ civilization: Civilization) {
        if settings.includedBotCivilizations.contains(civilization) {
            guard !isAtMinimumRoster else { return }
            settings.includedBotCivilizations.remove(civilization)
        } else {
            settings.includedBotCivilizations.insert(civilization)
        }
        persist()
    }

    private func persist() {
        CivilizationSettingsStore.shared.save(settings)
    }

    // MARK: - Shared row

    private func civilizationRow(
        _ civilization: Civilization,
        subtitle: String,
        isSelected: Bool,
        selectionSymbol: String = "checkmark.circle.fill"
    ) -> some View {
        HStack(spacing: 12) {
            CivilizationBadge(civilization: civilization, isCity: false, size: 34)

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
