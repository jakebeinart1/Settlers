import SwiftUI

/// Claims a name on the online ladder: saves it as the player's name (the
/// same preference New Game prefills from, so every later game is played
/// under it) and syncs at once, so the claim is settled before the next game.
/// Jake, 2026-09-27: "I don't want to have users go to settings".
struct LadderNameEntry: View {
    /// Called with the status the claim left, or `nil` in a build without sync.
    let onJoined: (LiveSync.Status?) -> Void
    var liveSync = LiveSync.shared
    @State private var draft = Self.currentName
    @State private var isJoining = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text("Your name").foregroundColor(.white.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.join)
                .onSubmit(join)
                .onChange(of: draft) { _, new in draft = String(new.prefix(PlayerNameStore.maximumLength)) }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 8, notchScale: 0.45))
                .accessibilityIdentifier(AccessibilityID.Leaderboard.nameField)
            Button(isJoining ? "Joining…" : "Join", action: join)
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(SettingsChrome.ornamentGold)
                .disabled(isJoining || trimmed.isEmpty)
                .accessibilityIdentifier(AccessibilityID.Leaderboard.joinButton)
        }
    }

    /// The saved name, unless it is still the unnamed default.
    static var currentName: String {
        let name = PlayerNameStore.shared.load()
        return name.caseInsensitiveCompare(LiveSync.defaultName) == .orderedSame ? "" : name
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespaces) }

    private func join() {
        guard !isJoining, !trimmed.isEmpty else { return }
        PlayerNameStore.shared.save(trimmed)
        guard let liveSync else { return onJoined(nil) }
        isJoining = true
        Task {
            let status = await liveSync.sync()
            isJoining = false
            onJoined(status)
        }
    }
}

/// Asked once, on launch, of a player with no ladder name, so every game they
/// go on to play is theirs on the ladder (Jake, 2026-09-27). Changing it later
/// is on the leaderboard.
struct LadderNamePrompt: View {
    let onDone: () -> Void
    @State private var taken: String?

    var body: some View {
        ZStack {
            PaintedScreenBackground()
            VStack(spacing: 16) {
                Text("Choose your name")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                Text(taken.map { "“\($0)” is taken. Choose another name." }
                     ?? "It's how you appear on the online leaderboard. You can change it there later.")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                LadderNameEntry { status in
                    if case .nameTaken(let name) = status { taken = name } else { onDone() }
                }
                // Sync may still be waiting for CloudKit. Local play must not
                // depend on a network response or require an iCloud account.
                Button("Not now", action: onDone)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(SettingsChrome.ornamentGold)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(AccessibilityID.Leaderboard.skipName)
            }
            .padding(.horizontal, 28)
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.ladderName)
    }

    /// Only a build on the online ladder asks: elsewhere the name is only a
    /// seat label, which New Game already asks for.
    static var isNeeded: Bool {
        #if DEBUG
        if QALaunchFlag.askLadderName.isSet { return true }
        #endif
        return LiveSync.shared != nil && LadderNameEntry.currentName.isEmpty
    }
}
