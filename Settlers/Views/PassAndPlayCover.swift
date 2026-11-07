import CatanEngine
import SwiftUI

/// The receiver gets a public prompt and an explicit reveal action before any
/// private hand, card or decision is visible on the shared device.
struct PassAndPlayCover: View {
    let recipient: PlayerIdentity?
    let context: String
    let turnTitle: String?
    let retryTitle: String?
    let onReady: () -> Void
    let onRetry: () -> Void
    let onMenu: () -> Void
    @AccessibilityFocusState private var isPromptFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 20)
                    heading
                    Spacer(minLength: 20)
                    controls
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            GeometryReader { geometry in
                ThemedBackgroundImage()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay(.black.opacity(0.66))
            }
            .background(CatanTheme.waterBackground)
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .onChange(of: recipient?.id, initial: true) { _, _ in isPromptFocused = true }
    }

    private var heading: some View {
        VStack(spacing: 12) {
            Text("Pass & Play")
                .font(.subheadline.weight(.semibold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(SettingsChrome.ornamentGold)
                .accessibilityAddTraits(.isHeader)

            if let recipient, retryTitle == nil {
                CivilizationCrest(civilization: recipient.civilization, size: 88)
                    .accessibilityHidden(true)
                Text("Pass to \(recipient.displayName)")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isPromptFocused)
                    .accessibilityIdentifier(AccessibilityID.Handoff.recipient)
            } else {
                Image(systemName: "hourglass")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text(retryTitle == nil ? "Waiting for the next player" : "Game paused")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isPromptFocused)
            }

            if let turnTitle, turnTitle != context {
                Text(turnTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SettingsChrome.ornamentGold)
            }
            Text(context)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.86))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 14))
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let retryTitle {
                GoldRowButton(title: retryTitle, systemImage: "arrow.clockwise", action: onRetry)
                    .accessibilityIdentifier(AccessibilityID.Game.retryBotProgress)
            } else if let recipient {
                GoldRowButton(title: "I'm \(recipient.displayName)",
                              subtitle: "Show my hand",
                              systemImage: "hand.tap",
                              iconColor: SettingsChrome.ornamentGold, action: onReady)
                    .accessibilityIdentifier(AccessibilityID.Handoff.ready)
            }
            Button(action: onMenu) {
                Text("Main Menu")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }
}

extension GameView {
    var localTurnTitle: String? {
        guard let owner = viewModel.localTurnOwner else { return nil }
        let name = viewModel.playerIdentity(for: owner).displayName
        return state.phase.isSetup ? "\(name) is placing" : "\(name)'s turn"
    }

    func localTurnStatus(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(SettingsChrome.ornamentGold)
                .accessibilityIdentifier(AccessibilityID.Game.localTurn)
            if let reply = viewModel.latestLocalTradeReply(for: viewModel.humanPlayer) {
                let name = viewModel.playerIdentity(for: reply.responder).displayName
                Text(reply.accepted ? "\(name) accepted the trade" : "\(name) declined the trade")
            } else if let actor = viewModel.seatOwedATurn, actor != viewModel.localTurnOwner {
                Text(localHandoffContext(for: actor))
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
    }

    var localHandoffCover: some View {
        let seat = viewModel.seatOwedATurn
        let recipient = seat.map { viewModel.playerIdentity(for: $0) }
        let failure = localHandoffRecoveryMessage
        return PassAndPlayCover(
            recipient: recipient,
            context: failure ?? seat.map(localHandoffContext) ?? localTurnTitle ?? "The game is catching up.",
            turnTitle: localTurnTitle,
            retryTitle: failure.map { _ in viewModel.persistenceBlocked ? "Reload saved game" : "Retry" },
            onReady: {
                guard let seat else { return }
                claimLocalSeat(seat)
            },
            onRetry: viewModel.retryBotProgress,
            onMenu: onExitToMenu
        )
    }

    private var localHandoffRecoveryMessage: String? {
        if viewModel.persistenceBlocked {
            return viewModel.persistenceErrorMessage ?? "Reload to continue from the last saved move."
        }
        if case .failed(_, let message) = viewModel.botTurnProgress { return message }
        return nil
    }

    private func localHandoffContext(for seat: PlayerID) -> String {
        if viewModel.pendingDevCardReveal?.owner == seat || viewModel.pendingDevCardResolution?.owner == seat {
            return "Review your development card."
        }
        if viewModel.pendingShipCapture?.reader == seat { return "Review the ship transfer." }
        if viewModel.tradeResponseOffer(for: seat) != nil { return "Answer a trade offer." }
        switch state.phase {
        case .discarding: return "Choose cards to discard."
        case .choosingResource: return "Collect your island resources."
        case .setupForward, .setupBackward: return "Place your settlement and road."
        default: return localTurnTitle ?? "Your decision is ready."
        }
    }
}
