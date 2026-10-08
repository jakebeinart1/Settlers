import CatanAI
import SwiftUI

/// Jake, 2026-10-08: see the ghost being trained and how many games until
/// it is playable, pause and resume training, rename, reset and remove it,
/// manage old ghosts, and keep other players' ghosts out of the picker.
/// Every action is one `GhostStore` call; own-ghost changes then sync, and
/// `revision` carries them to every phone (`LiveSync.accepts`).
struct ManageGhostsView: View {
    var store = GhostStore.shared
    var me = PlayerDirectory.shared.me
    let onClose: () -> Void

    private enum Pending: Equatable { case reset, removeMine, removeOld(String) }

    /// Bumped after every edit: the store is files, not observable state.
    @State private var generation = 0
    @State private var renaming: String?
    @State private var draftName = ""
    @State private var pending: Pending?
    @State private var problem: String?

    private var mine: GhostProfile? {
        _ = generation
        return store.ghost(id: me, includingRemoved: true)
    }

    var body: some View {
        ZStack {
            SettingsChrome.screenBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 22) {
                        Text("Ghosts").font(.system(size: 29, weight: .bold, design: .serif))
                        yourGhostSection
                        oldGhostsSection
                        othersSection
                        if let problem {
                            Text(problem).font(.footnote).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                closeBar
            }
            if let pending { confirmation(for: pending) }
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.manageGhosts)
    }

    // MARK: - Your ghost

    @ViewBuilder
    private var yourGhostSection: some View {
        VStack(spacing: 12) {
            SettingsSectionHeader(title: "Your Ghost")
            if let ghost = mine, !ghost.isRemoved {
                ghostCard(ghost, detail: GhostStatusText.line(
                    for: ghost, isTraining: GhostTrainingStatus.shared.trainingIDs.contains(me)))
                trainingRow(ghost)
                HStack(spacing: 10) {
                    smallButton("Reset", identifier: AccessibilityID.Ghosts.reset) { pending = .reset }
                    smallButton("Remove", identifier: AccessibilityID.Ghosts.remove) { pending = .removeMine }
                }
            } else {
                Text("You have no ghost yet. Play a rated Classic game to start one.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                if mine?.isRemoved == true {
                    smallButton("Start a new ghost", identifier: AccessibilityID.Ghosts.restart) {
                        act(syncs: true) {
                            try store.reset(me, keepingOld: false)
                            try store.setTrainingPaused(me, false)
                        }
                    }
                }
            }
        }
    }

    private func trainingRow(_ ghost: GhostProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Training").font(.headline)
            PaintedChoiceRow(options: [false, true], title: { $0 ? "On" : "Off" }, selection: !ghost.isTrainingPaused,
                             optionIdentifier: AccessibilityID.Ghosts.training,
                             onSelect: { on in act(syncs: true) { try store.setTrainingPaused(me, !on) } })
        }
    }

    // MARK: - Old and other ghosts

    @ViewBuilder
    private var oldGhostsSection: some View {
        let old = { _ = generation; return store.oldGhosts(of: me) }()
        if !old.isEmpty {
            VStack(spacing: 12) {
                SettingsSectionHeader(title: "Old Ghosts")
                ForEach(old) { ghost in
                    ghostCard(ghost, detail: "\(ghost.gamesLearned) games learned. Stays on this phone.")
                    smallButton("Remove", identifier: AccessibilityID.Ghosts.removeOld(ghost.id)) {
                        pending = .removeOld(ghost.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var othersSection: some View {
        let hidden = { _ = generation; return store.hiddenIDs() }()
        let others = store.all().filter { $0.id != me && !$0.id.contains("~") }
        if !others.isEmpty {
            VStack(spacing: 12) {
                SettingsSectionHeader(title: "Other Players' Ghosts")
                ForEach(others) { ghost in
                    let isHidden = hidden.contains(ghost.id)
                    HStack {
                        Text(ghost.name).opacity(isHidden ? 0.5 : 1)
                        Spacer()
                        smallButton(isHidden ? "Show" : "Hide", identifier: AccessibilityID.Ghosts.hide(ghost.id)) {
                            act(syncs: false) { try store.setHidden(ghost.id, !isHidden) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    /// Name (tap Rename to edit inline) and one line under it.
    @ViewBuilder
    private func ghostCard(_ ghost: GhostProfile, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if renaming == ghost.id {
                HStack {
                    TextField("Ghost name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(.black)
                        .accessibilityIdentifier(AccessibilityID.Ghosts.nameField)
                    smallButton("Save", identifier: AccessibilityID.Ghosts.saveName) {
                        act(syncs: ghost.id == me) { try store.rename(ghost.id, to: draftName) }
                        renaming = nil
                    }
                }
            } else {
                HStack {
                    Text(ghost.name).font(.title3.bold())
                    Spacer()
                    smallButton("Rename", identifier: AccessibilityID.Ghosts.rename(ghost.id)) {
                        draftName = ghost.name
                        renaming = ghost.id
                    }
                }
            }
            Text(detail).font(.subheadline).foregroundStyle(CatanTheme.cityPennantGold)
                .accessibilityIdentifier(AccessibilityID.Ghosts.status(ghost.id))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 9, notchScale: 0.5))
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
    }

    private var closeBar: some View {
        UniformActionButton(title: "Close", systemImage: "xmark", isEnabled: true,
                            backgroundImageName: "button-fill-trade", action: onClose)
            .accessibilityIdentifier(AccessibilityID.Ghosts.close)
            .frame(height: 62)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    private func confirmation(for action: Pending) -> some View {
        let copy: (title: String, message: String, button: String) = switch action {
        case .reset: ("Reset Your Ghost?",
                      "It starts learning again from your next game. The current one is kept as an Old Ghost on this phone.",
                      "Reset")
        case .removeMine: ("Remove Your Ghost?",
                           "Other players can no longer pick it, and training stops. You can start a new one later.",
                           "Remove")
        case .removeOld: ("Remove Old Ghost?", "It leaves the picker. Its files are archived on this phone.", "Remove")
        }
        return ConfirmationPopupCard(
            title: copy.title, message: copy.message, confirmTitle: copy.button,
            confirmIdentifier: AccessibilityID.Ghosts.confirm,
            onConfirm: {
                // Old ghosts never leave this phone, so removing one has nothing to send.
                let syncs: Bool = if case .removeOld = action { false } else { true }
                act(syncs: syncs) {
                    switch action {
                    case .reset: try store.reset(me, keepingOld: true)
                    case .removeMine:
                        try store.reset(me, keepingOld: false)
                        try store.setRemoved(me)
                    case .removeOld(let id): try store.removeOld(id)
                    }
                }
                pending = nil
            },
            onCancel: { pending = nil })
    }

    /// One edit, then a re-read; the player's own changes sync at once.
    private func act(syncs: Bool, _ edit: () throws -> Void) {
        do {
            try edit()
            problem = nil
        } catch GhostStore.ManagementError.emptyName {
            problem = "A ghost needs a name."
        } catch {
            problem = "That could not be saved: \(error.localizedDescription)"
        }
        generation += 1
        if syncs { Task.detached { await LiveSync.shared?.sync() } }
    }
}
