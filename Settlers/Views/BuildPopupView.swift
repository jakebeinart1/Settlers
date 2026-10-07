import SwiftUI
import CatanEngine

/// Painted build chooser for starting construction or buying a development card.
///
/// Road, Settlement, and City hand control to the shared board-decision
/// coordinator. Closing the popup therefore exposes a reversible preview;
/// resources are not spent until that proposal is explicitly confirmed.
/// Development cards have no board target, so their existing durable purchase
/// and private reveal remain immediate. Readable availability and exact cost
/// shortages come from BuildActionPresentation; legal moves still govern every
/// button. On short screens or larger text, only the choices scroll: Close
/// remains in a fixed footer.
public struct BuildPopupView: View {
    public let viewModel: GameViewModel
    public let onDismiss: () -> Void
    /// Conquest: Army Card opens the payment chooser rather than buying outright.
    public let onRaiseArmy: () -> Void

    public init(viewModel: GameViewModel, onDismiss: @escaping () -> Void, onRaiseArmy: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onRaiseArmy = onRaiseArmy
    }

    @State private var errorMessage: String?
    @State private var partHeights: [BuildPopupPart: CGFloat] = [:]
    private static let contentSpacing: CGFloat = 12
    private static let contentPadding: CGFloat = 16
    private static let verticalClearance: CGFloat = 64

    public var body: some View {
        let choices = BuildActionPresentation.menu(in: viewModel.state, for: viewModel.humanPlayer)
        GeometryReader { geometry in
            PopupCard(onDismiss: onDismiss) {
                VStack(spacing: Self.contentSpacing) {
                    VStack(spacing: 3) {
                        Text("Build").font(.headline)
                        Text("Your cards / cost")
                            .font(.caption)
                            .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                    }
                    .measureBuildPopupPart(.header)
                    ScrollView {
                        buildChoices(choices).measureBuildPopupPart(.choices)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: choicesHeight(in: geometry.size.height))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("build.choices")
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                            .measureBuildPopupPart(.error)
                    }
                    GoldRowButton(title: "Close", systemImage: "xmark", action: onDismiss)
                        .measureBuildPopupPart(.footer)
                }
                .padding(Self.contentPadding)
                .frame(maxWidth: 340)
                .onPreferenceChange(BuildPopupHeightPreference.self) { partHeights = $0 }
            }
            .opacity(partHeights[.choices] == nil ? 0 : 1)
        }
    }

    /// One action tree serves every text size. Measure current content, not
    /// the largest historical frame: normal menus stay compact and only the
    /// choices scroll when real header/footer/text height exhausts the screen.
    private func choicesHeight(in height: CGFloat) -> CGFloat {
        let spacingCount: CGFloat = errorMessage == nil ? 2 : 3
        let chrome = [.header, .footer, .error].reduce(CGFloat.zero) {
            $0 + partHeights[$1, default: 0]
        } + Self.contentPadding * 2 + Self.contentSpacing * spacingCount
        let available = max(0, height - Self.verticalClearance - chrome)
        return min(partHeights[.choices] ?? available, available)
    }

    private func buildChoices(_ choices: [BuildActionPresentation]) -> some View {
        VStack(spacing: 8) {
            ForEach(choices) { choice in
                BuildChoiceRow(presentation: choice, identity: viewModel.playerIdentity(for: viewModel.humanPlayer)) {
                    select(choice.kind)
                }
            }
        }
    }

    private func select(_ kind: BuildActionPresentation.Kind) {
        switch kind {
        case .ship: beginBoardDecision(.buildShip, pieceName: "ship")
        case .road: beginBoardDecision(.buildRoad, pieceName: "road")
        case .settlement: beginBoardDecision(.buildSettlement, pieceName: "settlement")
        case .city: beginBoardDecision(.buildCity, pieceName: "city")
        case .devCard: perform(.buyDevCard)
        case .armyCard: onRaiseArmy()
        case .deployArmy: beginBoardDecision(.deployArmy, pieceName: "army")
        }
    }

    private func perform(_ move: GameMove) {
        do {
            try viewModel.apply(move)
            errorMessage = nil
            // The durable private receipt now owns the next screen. Leaving
            // Build open underneath it made Continue return to a stale menu
            // and invited a second purchase before the first was understood.
            if case .buyDevCard = move { onDismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginBoardDecision(_ intent: BoardDecisionIntent, pieceName: String) {
        guard viewModel.beginBoardDecision(intent) else {
            errorMessage = "Could not start \(pieceName) placement. The game changed; please try again."
            return
        }
        errorMessage = nil
        onDismiss()
    }
}
