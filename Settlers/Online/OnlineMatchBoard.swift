import SwiftUI
import CatanEngine
import EmpiresOnline

struct OnlineMatchBoard: View {
    let position: OnlineMatchView
    let gameplay: OnlineGameplayView
    let model: OnlinePlayModel
    let leave: () -> Void
    @State private var coordinator = BoardDecisionCoordinator()
    @State private var editor: OnlineMoveEditor?
    @Environment(\.dynamicTypeSize) private var textSize

    private var state: GameState { gameplay.boardPresentationState }
    private var moves: [GameMove] { gameplay.legalMoves }
    private var ownAction: OnlinePendingAction? { position.pending.first { $0.seat == gameplay.viewer } }
    private var canAct: Bool { ownAction != nil && !model.isWorking && !model.hasPendingSubmission && !model.isOffline }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                OnlineMatchStatusBar(position: position, gameplay: gameplay, receivedAt: model.receivedAt, name: name)
                scoreStrip
                board.frame(height: max(210, min(430, geometry.size.height * 0.52)))
                ScrollView {
                    controls
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onChange(of: position.revision, initial: true) { _, _ in coordinator.reconcile(with: context) }
        .onChange(of: ownAction?.id) { _, _ in editor = nil }
        .sheet(item: $editor) { selection in
            OnlineMoveEditorView(editor: selection, gameplay: gameplay, position: position,
                                 name: name, onClose: { editor = nil },
                                 onSubmit: { move in editor = nil; submit(move) })
        }
    }

    private var board: some View {
        BoardView(state: state, playerIdentity: identity,
                  decision: canAct ? decision : nil,
                  onSelectTarget: select, allowsGameCommands: canAct)
            .clipped()
    }

    private var decision: BoardDecisionPresentation? {
        guard var decision = coordinator.presentation else { return nil }
        if decision.intent == .sailShip,
           let ship = gameplay.ships.first(where: { $0.id == decision.selectedShip }),
           decision.legalTiles.allSatisfy({ Naval.sailingRoute(for: ship, to: $0, in: state) != nil }) {
            decision.sailing = NavalSailingPresentation(state: state, decision: decision)
        }
        decision.blockadedTiles = NavalBlockadePresentation.tiles(in: state, decision: decision)
        return decision
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            connectionStatus
            if let decision, canAct {
                dock(decision)
                if decision.intent == .deployArmy, let tile = decision.selectedTile {
                    GoldRowButton(title: "Choose Other Army Cards", systemImage: "shield") { editor = .deploy(tile) }
                }
            }
            if let winner = gameplay.winner {
                OnlineInformation(title: "\(name(winner)) wins", detail: "This result is saved in Your Games.")
            } else if decision == nil {
                OnlineMatchActions(gameplay: gameplay, moves: moves, isEnabled: canAct,
                                   name: name, onBegin: begin, onEditor: { editor = $0 }, onSubmit: submit)
            }
            OnlineHandView(gameplay: gameplay)
            if position.status == .playing {
                settings
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if model.hasPendingSubmission {
            GoldRowButton(title: "Retry Pending Move", subtitle: "Empires will check whether it already went through.",
                          systemImage: "clock.arrow.circlepath", isEnabled: !model.isWorking) {
                Task { await model.retrySubmission() }
            }
        } else if model.isOffline {
            OnlineInformation(title: "Reconnecting", detail: "Moves resume when the current position is available.")
        }
        if let message = model.message {
            OnlineInformation(title: "Match update", detail: message)
        }
    }

    private var settings: some View {
        HStack {
            Button(position.isMuted ? "Unmute Alerts" : "Mute Alerts") {
                Task { await model.run(.mute(matchID: position.id, muted: !position.isMuted)) }
            }
            Spacer()
            Button("Leave Game", role: .destructive, action: leave)
        }
        .font(.footnote)
        .padding(6)
        .frame(minHeight: 44)
        .disabled(model.isWorking || model.hasPendingSubmission)
    }

    private var scoreStrip: some View {
        Group {
            if textSize.isAccessibilitySize {
                ScrollView(.horizontal) { scoreCards }
            } else {
                scoreCards
            }
        }
        .padding(.horizontal, 12)
    }

    private var scoreCards: some View {
        HStack(spacing: 6) {
            ForEach(gameplay.players, content: scoreCard)
        }
    }

    private func scoreCard(_ player: OnlineGameplayPlayer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(player.id == gameplay.viewer ? "You" : name(player.id))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                CivilizationCrest(civilization: identity(player.id).civilization, size: 16)
                    .accessibilityHidden(true)
                Text("\(player.victoryPoints) VP").foregroundStyle(SettingsChrome.ornamentGold)
                if player.id != gameplay.viewer {
                    Label("\(player.resourceCount)", systemImage: "square.stack")
                        .accessibilityLabel("\(player.resourceCount) resource cards")
                }
            }
            .font(.caption2.monospacedDigit())
            .lineLimit(1)
        }
        .fixedSize(horizontal: textSize.isAccessibilitySize, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func dock(_ decision: BoardDecisionPresentation) -> some View {
        BoardDecisionDockView(
            presentation: decision, identity: identity,
            resourceCount: { seat in gameplay.players.first { $0.id == seat }?.resourceCount ?? 0 },
            onSelectVictim: { select(.victim($0)) },
            onUndo: { _ = coordinator.undoSelection() },
            onClear: { coordinator.clearSelection() },
            onCancel: { _ = coordinator.cancel() },
            onConfirm: confirm,
            onSelectArmyCards: { select(.armyCards($0)) },
            ships: gameplay.ships,
            onSelectShip: { select(.ship($0)) },
            onSkipCapture: { submit(.skipShipCapture) }
        )
    }

    private var context: BoardDecisionContext {
        BoardDecisionContext(matchID: position.id, committedMoveCount: position.revision,
                             actor: gameplay.viewer, state: state, authorizedMoves: moves)
    }

    private func begin(_ intent: BoardDecisionIntent) {
        guard canAct else { return }
        _ = coordinator.begin(intent, with: context)
    }

    private func select(_ target: BoardTarget) {
        guard canAct else { return }
        if case .ship = target, coordinator.presentation == nil { begin(.sailShip) }
        _ = coordinator.select(target)
    }

    private func confirm() {
        guard let move = coordinator.confirmableMove else { return }
        submit(move)
    }

    private func submit(_ move: GameMove) {
        guard canAct else { return }
        Task { await model.submit(move, in: position) }
    }

    private func name(_ player: PlayerID) -> String { seat(player)?.name ?? "Seat \(player.index + 1)" }

    private func seat(_ player: PlayerID) -> OnlineSeat? {
        position.seats.indices.contains(player.index) ? position.seats[player.index] : nil
    }

    private func identity(_ player: PlayerID) -> PlayerIdentity {
        let seat = seat(player)
        let civilization = seat?.civilization.flatMap(Civilization.init(rawValue:)) ?? .medieval
        return PlayerIdentity(seat: player, displayName: name(player), civilization: civilization,
                              controller: seat?.role == .human ? .human : .computer)
    }
}

private struct OnlineMatchStatusBar: View {
    let position: OnlineMatchView
    let gameplay: OnlineGameplayView
    let receivedAt: ContinuousClock.Instant
    let name: (PlayerID) -> String

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(turnLabel).font(.system(.subheadline, design: .serif, weight: .semibold))
                Spacer(minLength: 4)
                if let roll = gameplay.lastDiceRoll { Label("\(roll)", systemImage: "dice") }
                Text("To \(gameplay.victoryPointTarget) VP").foregroundStyle(SettingsChrome.ornamentGold)
            }
            .font(.caption)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            timerLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var timer: OnlinePendingAction? {
        let timed = position.pending.filter { $0.deadline != nil }
        return timed.first { $0.seat == gameplay.viewer } ?? timed.min {
            ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
        }
    }

    private var turnLabel: String {
        if let winner = gameplay.winner { return "\(name(winner)) wins" }
        if let owner = gameplay.turnOwner {
            return owner == gameplay.viewer ? "Your turn" : "\(name(owner))’s turn"
        }
        return "Waiting for the table"
    }

    private var timerLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack {
                if let timer, let deadline = timer.deadline {
                    let elapsed = receivedAt.duration(to: .now)
                    let seconds = Double(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
                    let remaining = Int(max(0, ceil(deadline.timeIntervalSince(position.serverTime) - seconds)))
                    Label(timer.seat == gameplay.viewer ? timer.kind.ownTitle : "\(name(timer.seat)) · \(timer.kind.otherTitle)",
                          systemImage: "timer")
                    Spacer()
                    Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                        .accessibilityLabel("Time remaining")
                        .accessibilityValue("\(remaining) seconds")
                        .accessibilityIdentifier("online.clock")
                } else if let action = position.pending.first(where: { $0.seat == gameplay.viewer }) {
                    Label(action.kind.ownTitle, systemImage: "bell")
                    Spacer()
                } else {
                    Text(position.configuration.pace.onlineLabel)
                    Spacer()
                }
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(height: 20)
            .foregroundStyle(SettingsChrome.ornamentGold)
        }
    }
}

private extension OnlineDeadlineKind {
    var ownTitle: String {
        switch self {
        case .setup: "Place your opening piece"
        case .turn: "Your turn timer"
        case .response: "Your response"
        case .trade: "Your trade response"
        }
    }

    var otherTitle: String {
        switch self {
        case .setup: "Opening placement"
        case .turn: "Turn timer"
        case .response: "Response"
        case .trade: "Trade response"
        }
    }
}

private struct OnlineHandView: View {
    let gameplay: OnlineGameplayView

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Your Hand").font(.system(.subheadline, design: .serif, weight: .bold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { resourceLabels }
                VStack(alignment: .leading) { resourceLabels }
            }
            Text("\(gameplay.devCards.count) development · \(gameplay.armyCards.count) army")
                .font(.caption2)
            if !gameplay.devCards.isEmpty || !gameplay.armyCards.isEmpty {
                DisclosureGroup("Private cards") {
                    ForEach(DevCardType.allCases, id: \.self) { card in
                        let quantity = gameplay.devCards.filter { $0 == card }.count
                        if quantity > 0 { Text("\(quantity) \(card.onlineTitle)") }
                    }
                    if !gameplay.armyCards.isEmpty {
                        Text("Army strength: " + gameplay.armyCards.sorted().map(String.init).joined(separator: ", "))
                    }
                }
                .font(.footnote)
                .tint(SettingsChrome.ornamentGold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
    }

    private var resourceLabels: some View {
        ForEach(Resource.allCases, id: \.self) { resource in
            Text("\(resource.rawValue.capitalized) \(gameplay.resources[resource, default: 0])")
                .font(.caption)
        }
    }
}
