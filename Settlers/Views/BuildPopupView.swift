import SwiftUI
import CatanEngine

/// Painted build chooser for starting construction or buying a development card.
///
/// Road, Settlement, and City hand control to the shared board-decision
/// coordinator. Closing the popup therefore exposes a reversible preview;
/// resources are not spent until that proposal is explicitly confirmed.
/// Development cards have no board target, so their existing durable purchase
/// and private reveal remain immediate. Every row is disabled when the engine
/// exposes no matching legal move, covering both cost and board availability.
public struct BuildPopupView: View {
    public let viewModel: GameViewModel
    public let onDismiss: () -> Void

    public init(viewModel: GameViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    @State private var errorMessage: String?

    public var body: some View {
        // Computed once per render and reused for all four affordability
        // checks below - see `BuildMenuView`'s old version of this same
        // comment for why (`RulesEngine.legalMoves` is expensive).
        let legalMoves = RulesEngine.legalMoves(for: viewModel.state)
        let canBuildRoad = legalMoves.contains { if case .buildRoad = $0 { true } else { false } }
        let canBuildSettlement = legalMoves.contains { if case .buildSettlement = $0 { true } else { false } }
        let canBuildCity = legalMoves.contains { if case .buildCity = $0 { true } else { false } }
        let canBuyDevCard = legalMoves.contains { if case .buyDevCard = $0 { true } else { false } }
        let devCardsRemaining = viewModel.state.devCardDeck.count

        PopupCard(onDismiss: onDismiss) {
            VStack(spacing: 12) {
                Text("Build")
                    .font(.headline)

                VStack(spacing: 8) {
                    buildRow(title: "Road", icon: "line.diagonal", color: .brown, cost: Building.roadCost, isEnabled: canBuildRoad) {
                        beginBoardDecision(.buildRoad, pieceName: "road")
                    }
                    .accessibilityIdentifier(AccessibilityID.Build.road)
                    buildRow(title: "Settlement", icon: "house.fill", color: .green, cost: Building.settlementCost, isEnabled: canBuildSettlement) {
                        beginBoardDecision(.buildSettlement, pieceName: "settlement")
                    }
                    .accessibilityIdentifier(AccessibilityID.Build.settlement)
                    buildRow(title: "City", icon: "building.2.fill", color: .indigo, cost: Building.cityCost, isEnabled: canBuildCity) {
                        beginBoardDecision(.buildCity, pieceName: "city")
                    }
                    .accessibilityIdentifier(AccessibilityID.Build.city)
                    buildRow(
                        title: "Dev Card",
                        icon: "rectangle.stack.fill",
                        color: .purple,
                        cost: Building.devCardCost,
                        isEnabled: canBuyDevCard,
                        // Otherwise a player who can afford the cost but hits
                        // the empty deck sees the row go dim with no
                        // explanation - easy to mistake for a bug rather than
                        // the standard 25-card deck (14 knight/5 VP/2 each of
                        // the other three) running out.
                        subtitle: devCardsRemaining == 0 ? "Deck is empty" : "\(devCardsRemaining) left"
                    ) {
                        perform(.buyDevCard)
                    }
                    .accessibilityIdentifier(AccessibilityID.Build.devCard)
                    if viewModel.state.variant == .conquest {
                        let me = viewModel.humanPlayer
                        let hand = viewModel.state.armyHands[me, default: []].sorted()
                        GoldRowButton(
                            title: "Army Card",
                            subtitle: (hand.isEmpty ? "No cards" : "Yours: " + hand.map(String.init).joined(separator: ", "))
                                + " · \(viewModel.state.armyDeck.count) left",
                            systemImage: "shield.lefthalf.filled",
                            iconColor: .red,
                            isEnabled: legalMoves.contains(.buyArmyCard),
                            trailing: {
                                Text("Any 3").font(.caption2.bold()).foregroundStyle(CatanTheme.cityPennantGold)
                            },
                            action: { perform(.buyArmyCard) }
                        )
                        .accessibilityIdentifier(AccessibilityID.Build.armyCard)
                        GoldRowButton(
                            title: "Deploy Army",
                            subtitle: "Tap a hex to take or hold it",
                            systemImage: "flag.fill",
                            iconColor: .red,
                            isEnabled: !Conquest.deployMoves(for: me, in: viewModel.state).isEmpty,
                            action: { beginBoardDecision(.deployArmy, pieceName: "army") }
                        )
                        .accessibilityIdentifier(AccessibilityID.Build.deployArmy)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                GoldRowButton(title: "Close", systemImage: "xmark", action: onDismiss)
            }
            .padding(16)
            .frame(maxWidth: 320)
        }
    }

    private func buildRow(title: String, icon: String, color: Color, cost: [Resource: Int], isEnabled: Bool, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        GoldRowButton(
            title: title,
            subtitle: subtitle,
            systemImage: icon,
            iconColor: color,
            isEnabled: isEnabled,
            trailing: {
                HStack(spacing: 4) {
                    ForEach(Resource.allCases.filter { (cost[$0] ?? 0) > 0 }, id: \.self) { resource in
                        HStack(spacing: 3) {
                            // Rounded square, not a circle - matches the
                            // resource swatches everywhere else in the app.
                            RoundedRectangle(cornerRadius: 2)
                                .fill(CatanTheme.color(for: resource))
                                .frame(width: 10, height: 10)
                            Text("\(cost[resource] ?? 0)")
                                .font(.caption2.bold())
                                .foregroundStyle(CatanTheme.color(for: resource))
                        }
                    }
                }
            },
            action: action
        )
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
