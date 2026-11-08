import SwiftUI
import CatanEngine
import EmpiresOnline

struct OnlineAccountEntry: View {
    let model: OnlinePlayModel
    let onAuthenticated: () async -> Void
    @State private var name = ""
    @State private var key = ""
    @State private var recovery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnlineInformation(title: "A table wherever you are",
                              detail: "Play with friends on their own devices. Create a private table for asynchronous or timed live games.")
            if model.hasStoredSession && model.needsRecovery {
                GoldRowButton(title: "Reconnect to Account", systemImage: "arrow.clockwise", isEnabled: !model.isWorking) {
                    Task {
                        await model.reconnect()
                        await onAuthenticated()
                    }
                }
            }
            if recovery {
                OnlineTextField(title: "Recovery key", text: $key, secret: true)
            } else {
                OnlineTextField(title: "Your player name", text: $name)
                    .accessibilityIdentifier("online.account.name")
            }
            GoldRowButton(title: recovery ? "Use Recovery Key" : "Create Online Account",
                          systemImage: recovery ? "key.horizontal" : "person.badge.plus",
                          iconColor: SettingsChrome.ornamentGold,
                          isEnabled: canContinue) {
                Task {
                    if recovery { await model.recover(using: key) } else { await model.createAccount(named: name) }
                    if model.account != nil {
                        key = ""
                        await onAuthenticated()
                    }
                }
            }
            .accessibilityIdentifier("online.account.submit")
            Button(recovery ? "Create a new account" : "Already have a recovery key?") {
                recovery.toggle()
                key = ""
            }
            .frame(minHeight: 44)
            .tint(SettingsChrome.ornamentGold)
            .disabled(model.isWorking)
        }
    }

    private var canContinue: Bool {
        if model.isWorking { return false }
        if recovery { return key.trimmingCharacters(in: .whitespacesAndNewlines).count == 72 }
        return (1 ... 24).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }
}

struct OnlineAccountPanel: View {
    let model: OnlinePlayModel
    let router: OnlineNotificationRouter
    let onClose: () -> Void
    let copyKey: () -> Void
    @State private var confirmingCopy = false
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false

    var body: some View {
        OnlineFormPage(title: "Online Account", onClose: onClose) {
            if model.isChangingAccount {
                ProgressView("Updating online account…")
            } else {
                accountOptions
            }
        }
        .confirmationDialog("Copy your recovery key?", isPresented: $confirmingCopy, titleVisibility: .visible) {
            Button("Copy recovery key", action: copyKey)
        } message: {
            Text("Anyone who has this key can use your online account. It is never included in room invitations.")
        }
        .confirmationDialog("Sign out of online play?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { finishAccountAction { await model.signOut() } }
        } message: {
            Text("Save your recovery key first so you can return to this account and its matches.")
        }
        .confirmationDialog("Delete online account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { finishAccountAction { await model.deleteAccount() } }
        } message: {
            Text("This removes your online account and recovery key. In-progress opponents continue with an AI in your seat.")
        }
    }

    private var accountOptions: some View {
        Group {
            OnlineInformation(title: model.account?.name ?? "Player",
                              detail: "Save your recovery key privately to resume this account on another device.")
            GoldRowButton(title: "Copy Recovery Key", systemImage: "key.horizontal") { confirmingCopy = true }
            GoldRowButton(title: "Enable Turn Alerts", systemImage: "bell") {
                Task { await OnlineAlertPermission.request(model: model, router: router) }
            }
            GoldRowButton(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right",
                          isEnabled: !model.isWorking) { confirmingSignOut = true }
            GoldRowButton(title: "Delete Online Account", systemImage: "trash",
                          iconColor: .red, isEnabled: !model.isWorking) { confirmingDelete = true }
            if let message = model.message { Text(message).font(.footnote) }
        }
    }

    private func finishAccountAction(_ action: @escaping @MainActor () async -> Void) {
        Task {
            await action()
            if model.account == nil { onClose() }
        }
    }
}

struct OnlineLobby: View {
    let position: OnlineMatchView
    let model: OnlinePlayModel
    let router: OnlineNotificationRouter
    let edit: () -> Void
    let leave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            invite
            OnlineInformation(title: "\(position.configuration.mode.displayName) · \(position.configuration.rules.displayName)",
                              detail: position.configuration.pace.policyDescription)
            VStack(spacing: 8) {
                ForEach(Array(position.seats.enumerated()), id: \.offset) { index, seat in
                    seatRow(seat, index: index)
                }
            }
            readiness
            if position.configuration.pace == .asynchronous {
                GoldRowButton(title: "Enable Turn Alerts", subtitle: "Your Games always shows when you need to act.",
                              systemImage: "bell", iconColor: SettingsChrome.ornamentGold) {
                    Task { await OnlineAlertPermission.request(model: model, router: router) }
                }
            }
            GoldRowButton(title: "Leave Waiting Room", systemImage: "rectangle.portrait.and.arrow.right",
                          isEnabled: !model.isWorking, action: leave)
        }
        .accessibilityIdentifier("online.lobby")
    }

    private var invite: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PRIVATE INVITATION")
                .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(SettingsChrome.ornamentGold)
            ViewThatFits(in: .horizontal) {
                HStack { inviteCode; Spacer(); shareInvite }
                VStack(alignment: .leading) { inviteCode; shareInvite }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
    }

    private var inviteCode: some View {
        Text(position.code).font(.system(.title3, design: .monospaced, weight: .bold))
            .textSelection(.enabled)
            .accessibilityIdentifier("online.invite-code")
    }

    @ViewBuilder
    private var shareInvite: some View {
        if let url = URL(string: "empires://online/join/\(position.code)") {
            ShareLink(item: "Join my Empires table. Code: \(position.code)\n\(url.absoluteString)") {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(minHeight: 44)
            }
            .tint(SettingsChrome.ornamentGold)
        }
    }

    private func seatRow(_ seat: OnlineSeat, index: Int) -> some View {
        HStack(spacing: 10) {
            if let raw = seat.civilization, let civilization = Civilization(rawValue: raw) {
                CivilizationCrest(civilization: civilization, size: 32)
            } else {
                Image(systemName: "person.badge.plus").frame(width: 32, height: 32)
            }
            VStack(alignment: .leading) {
                Text(seat.name ?? seat.role.onlineLabel).font(.system(.subheadline, design: .serif, weight: .bold))
                Text(seat.isYou ? "Seat \(index + 1) · You" : "Seat \(index + 1) · \(seat.role.onlineLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if seat.role == .human {
                Text(seat.ready ? "Ready" : "Waiting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(seat.ready ? SettingsChrome.ornamentGold : .secondary)
            }
        }
        .padding(10)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var readiness: some View {
        let viewerReady = position.seats.first(where: \.isYou)?.ready == true
        return VStack(spacing: 8) {
            GoldRowButton(title: viewerReady ? "Unready" : "Ready", systemImage: "checkmark.circle",
                          iconColor: SettingsChrome.ornamentGold, isEnabled: !model.isWorking) {
                Task {
                    await model.run(.ready(matchID: position.id, isReady: !viewerReady, revision: position.lobbyRevision))
                }
            }
            .accessibilityIdentifier("online.ready")
            if position.host {
                GoldRowButton(title: "Start Match", subtitle: canStart ? nil : "Fill the seats and wait for every player to be ready.",
                              systemImage: "play.fill", iconColor: SettingsChrome.ornamentGold,
                              isEnabled: canStart && !model.isWorking) {
                    Task { await model.run(.start(matchID: position.id, revision: position.lobbyRevision)) }
                }
                .accessibilityIdentifier("online.start")
                GoldRowButton(title: "Table Settings", systemImage: "slider.horizontal.3",
                              isEnabled: !model.isWorking, action: edit)
            }
        }
    }

    private var canStart: Bool {
        position.seats.filter { $0.role == .human }.count >= 2
            && position.seats.allSatisfy { $0.role != .open && ($0.role != .human || $0.ready) }
    }
}

struct OnlineRoomForm: View {
    let position: OnlineMatchView?
    let model: OnlinePlayModel
    let joining: Bool
    let onClose: () -> Void
    @State private var code: String
    @State private var pace: OnlinePace
    @State private var mode: GameMode
    @State private var rules: GameVariant
    @State private var seatCount: Int
    @State private var choices: [OnlineSeatRole]
    @State private var civilization: Civilization

    init(position: OnlineMatchView?, initialCode: String, model: OnlinePlayModel, joining: Bool = false,
         onClose: @escaping () -> Void) {
        self.position = position
        self.model = model
        self.joining = joining
        self.onClose = onClose
        _code = State(initialValue: initialCode)
        _pace = State(initialValue: position?.configuration.pace ?? .asynchronous)
        _mode = State(initialValue: position?.configuration.mode ?? .classic)
        _rules = State(initialValue: position?.configuration.rules ?? .standard)
        _seatCount = State(initialValue: position?.seats.count ?? 3)
        let slots = position?.configuration.aiSeats.map { $0 ?? .open } ?? [.open, .open, .classicAI]
        _choices = State(initialValue: Array((slots + [.classicAI]).prefix(4)))
        _civilization = State(initialValue: joining ? .greece : .medieval)
    }

    var body: some View {
        OnlineFormPage(title: heading, onClose: onClose) {
            if joining {
                OnlineTextField(title: "Invitation code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .accessibilityIdentifier("online.invite-entry")
                Text("Choose a different civilization if a friend at the table has already reserved it.")
                    .font(.footnote)
            } else {
                matchOptions
                OnlineInformation(title: pace.onlineLabel, detail: pace.policyDescription)
            }
            if position == nil {
                OnlinePicker(title: "Civilization", selection: $civilization) {
                    ForEach(Civilization.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            GoldRowButton(title: heading, systemImage: joining ? "link" : "checkmark",
                          iconColor: SettingsChrome.ornamentGold,
                          isEnabled: !model.isWorking && isValid) {
                Task { if await model.run(request) { onClose() } }
            }
            .accessibilityIdentifier("online.room-submit")
            if let message = model.message { Text(message).font(.footnote) }
        }
    }

    private var matchOptions: some View {
        VStack(spacing: 10) {
            OnlinePicker(title: "Pace", selection: $pace) {
                ForEach(OnlinePace.allCases, id: \.self) { Text($0.onlineLabel).tag($0) }
            }
            OnlinePicker(title: "Board", selection: $mode) {
                ForEach(GameMode.newGameChoices, id: \.self) { Text($0.displayName).tag($0) }
            }
            if mode != .naval {
                OnlinePicker(title: "Rules", selection: $rules) {
                    ForEach(GameVariant.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            OnlinePicker(title: "Table size", selection: $seatCount) {
                ForEach(allowedSizes, id: \.self) { Text("\($0) seats").tag($0) }
            }
            ForEach(firstEditableSeat ..< seatCount, id: \.self) { index in
                if isReserved(index) {
                    Text("Seat \(index + 1) · \(position?.seats[index].name ?? "Player")")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                } else {
                    OnlinePicker(title: "Seat \(index + 1)", selection: $choices[index]) {
                        ForEach([OnlineSeatRole.open, .classicAI, .expertAI], id: \.self) { Text($0.onlineLabel).tag($0) }
                    }
                }
            }
        }
    }

    private var heading: String { joining ? "Join Table" : position == nil ? "Create Table" : "Save Table Settings" }

    private var allowedSizes: [Int] { isReserved(3) ? [4] : [3, 4] }
    private var firstEditableSeat: Int { position == nil ? 1 : 0 }

    private var isValid: Bool {
        if joining { return code.trimmingCharacters(in: .whitespacesAndNewlines).count == 10 }
        return aiSeats.filter { $0 == nil }.count >= 2
    }

    private var aiSeats: [OnlineSeatRole?] {
        (0 ..< seatCount).map { index in
            index < firstEditableSeat || isReserved(index) || choices[index] == .open ? nil : choices[index]
        }
    }

    private func isReserved(_ index: Int) -> Bool {
        guard let position, position.seats.indices.contains(index) else { return false }
        return position.seats[index].role == .human
    }

    private var request: OnlineRequest {
        if joining { return .join(code: code, civilization: civilization.rawValue) }
        let configuration = OnlineConfiguration(pace: pace, mode: mode, rules: mode == .naval ? .standard : rules,
                                                aiSeats: aiSeats)
        if let position {
            return .configure(matchID: position.id, configuration: configuration, revision: position.lobbyRevision)
        }
        return .createRoom(configuration: configuration, civilization: civilization.rawValue)
    }
}

extension OnlinePace {
    var policyDescription: String {
        switch self {
        case .asynchronous:
            let trade = seconds(for: .trade) / 3_600
            return "Play whenever you return. Required decisions wait for their player. A trade offer expires after \(trade) hours."
        case .timedLive:
            return "\(seconds(for: .setup)) seconds for setup, \(seconds(for: .turn)) for the turn, "
                + "\(seconds(for: .response)) for required responses, and \(seconds(for: .trade)) for trades. "
                + "The match continues when time expires."
        }
    }

    private func seconds(for kind: OnlineDeadlineKind) -> Int { Int(kind.seconds(in: self) ?? 0) }
}

private extension OnlineSeatRole {
    var onlineLabel: String {
        switch self {
        case .open: "Open for a Friend"
        case .human: "Human"
        case .classicAI: "Classic AI"
        case .expertAI: "Expert AI"
        }
    }
}

enum OnlineAlertPermission {
    static func request(model: OnlinePlayModel, router: OnlineNotificationRouter) async {
        do {
            let allowed = try await router.requestNotifications()
            model.message = allowed
                ? "Empires is setting up turn alerts."
                : "Alerts are off. Turn them on in iOS Settings, or check Your Games for pending actions."
        } catch {
            model.message = "Alerts could not be enabled. Your Games still shows your pending actions."
        }
    }
}

struct OnlineFormPage<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14, content: content)
                    .frame(maxWidth: 520)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { OnlineScenery() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: onClose) } }
        }
        .foregroundStyle(.white)
    }
}

private struct OnlineTextField: View {
    let title: String
    @Binding var text: String
    var secret = false

    var body: some View {
        Group {
            if secret {
                SecureField(title, text: $text)
                    .textInputAutocapitalization(.never)
            } else {
                TextField(title, text: $text)
            }
        }
        .autocorrectionDisabled()
        .padding(12)
        .frame(minHeight: 44)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 8))
    }
}

struct OnlinePicker<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder let options: () -> Options

    var body: some View {
        Picker(title, selection: $selection, content: options)
            .pickerStyle(.menu)
            .tint(SettingsChrome.ornamentGold)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 8)
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 8))
    }
}
