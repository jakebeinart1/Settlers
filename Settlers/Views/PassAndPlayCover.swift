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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var claimBelowPrompt: Bool {
        recipient != nil && retryTitle == nil && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ScrollView {
                    prompt
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 440)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .clipped()
            }
            // At accessibility sizes the claim stays reachable while long prompts scroll.
            controls
                .padding(.horizontal, 24)
                .frame(maxWidth: 440)
                .padding(.bottom, 12)
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
        .onChange(of: retryTitle) { _, _ in isPromptFocused = true }
    }

    private var prompt: some View {
        VStack(spacing: 12) {
            heading
            if claimBelowPrompt, let recipient {
                claimButton(for: recipient)
            }
        }
    }

    private var heading: some View {
        VStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text("Pass & Play")
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(SettingsChrome.ornamentGold)
                    .accessibilityAddTraits(.isHeader)
            }

            if let recipient, retryTitle == nil {
                CivilizationCrest(civilization: recipient.civilization, size: 72)
                    .accessibilityHidden(true)
                Text("Pass to \(recipient.displayName)")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isPromptFocused)
                    .accessibilityIdentifier(AccessibilityID.Handoff.recipient)
            } else {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: retryTitle == nil ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 32, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(retryTitle == nil ? "Waiting for the next player" : "Game paused")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isPromptFocused)
            }

            if let turnTitle, turnTitle != context {
                Text(turnTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SettingsChrome.ornamentGold)
            }
            Text(context)
                .font(.footnote)
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
            } else if !claimBelowPrompt, let recipient {
                claimButton(for: recipient)
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

    private func claimButton(for recipient: PlayerIdentity) -> some View {
        Button(action: onReady) {
            HStack(spacing: 12) {
                Image(systemName: "hand.tap.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SettingsChrome.ornamentGold)
                VStack(spacing: 3) {
                    Text(dynamicTypeSize.isAccessibilitySize ? "Continue" : "I'm \(recipient.displayName)")
                        .font(.title3.bold())
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Continue privately")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.86))
                    }
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Rectangle())
            .background(PaintedChromeBackground(textureImageName: "button-fill-turn", cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I'm \(recipient.displayName). Continue privately.")
        .accessibilityIdentifier(AccessibilityID.Handoff.ready)
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
        let context = failure ?? seat.map(localHandoffContext) ?? "The game is catching up."
        return PassAndPlayCover(
            recipient: recipient,
            context: context,
            turnTitle: failure == nil && seat != viewModel.localTurnOwner ? localTurnTitle : nil,
            retryTitle: failure.map { _ in viewModel.persistenceBlocked ? "Reload save" : "Retry" },
            onReady: {
                guard let seat, viewModel.claimLocalDevice(for: seat) else { return }
                Task { await viewModel.runBotTurnIfNeeded() }
            },
            onRetry: viewModel.retryBotProgress,
            onMenu: onExitToMenu
        )
    }

    private var localHandoffRecoveryMessage: String? {
        if viewModel.persistenceBlocked {
            return "The game couldn’t save."
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
        case .rollDice: return "Roll the dice to start your turn."
        case .mainTurn: return "Continue your turn."
        default: return "Your decision is ready."
        }
    }
}
