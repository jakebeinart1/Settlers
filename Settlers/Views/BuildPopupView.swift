import SwiftUI
import CatanEngine

/// Build popup - same card chrome as `TradePopupView`/`DevCardPopupView`
/// (replaces the old `BuildMenuView` native `Menu`). Road/Settlement/City
/// arm `placementMode` so `GameView` puts `BoardView` into placement mode
/// and the next vertex/edge tap performs the actual build; Dev Card buys
/// immediately (there's no placement step). Each row shows its resource
/// cost and disables itself when `RulesEngine.legalMoves` has no matching
/// move for the current state (covers both "can't afford" and "no legal
/// spot" in one check).
public struct BuildPopupView: View {
    public let viewModel: GameViewModel
    @Binding public var placementMode: PlacementMode?
    public let onDismiss: () -> Void

    public init(viewModel: GameViewModel, placementMode: Binding<PlacementMode?>, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self._placementMode = placementMode
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

        PopupCard(onDismiss: onDismiss) {
            VStack(spacing: 12) {
                Text("Build")
                    .font(.headline)

                VStack(spacing: 8) {
                    buildRow(title: "Road", icon: "line.diagonal", color: .brown, cost: Building.roadCost, isEnabled: canBuildRoad) {
                        placementMode = .road
                        onDismiss()
                    }
                    buildRow(title: "Settlement", icon: "house.fill", color: .green, cost: Building.settlementCost, isEnabled: canBuildSettlement) {
                        placementMode = .settlement
                        onDismiss()
                    }
                    buildRow(title: "City", icon: "building.2.fill", color: .indigo, cost: Building.cityCost, isEnabled: canBuildCity) {
                        placementMode = .city
                        onDismiss()
                    }
                    buildRow(title: "Dev Card", icon: "rectangle.stack.fill", color: .purple, cost: Building.devCardCost, isEnabled: canBuyDevCard) {
                        perform(.buyDevCard)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Button("Close", action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .padding(16)
            .frame(maxWidth: 320)
        }
    }

    private func buildRow(title: String, icon: String, color: Color, cost: [Resource: Int], isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.callout)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.bold())
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(Resource.allCases.filter { (cost[$0] ?? 0) > 0 }, id: \.self) { resource in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(CatanTheme.color(for: resource))
                                .frame(width: 10, height: 10)
                            Text("\(cost[resource] ?? 0)")
                                .font(.caption2.bold())
                                .foregroundStyle(CatanTheme.color(for: resource))
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(color.opacity(isEnabled ? 0.55 : 0.25), in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func perform(_ move: GameMove) {
        do {
            try viewModel.apply(move)
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }
}
