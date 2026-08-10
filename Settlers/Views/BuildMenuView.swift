import SwiftUI
import CatanEngine

/// Bottom build bar: one button each for road/settlement/city/dev-card.
/// Road/settlement/city buttons don't build directly - tapping one arms
/// `placementMode` so `GameView` puts `BoardView` into placement mode and the
/// next vertex/edge tap performs the actual build. The dev-card button acts
/// immediately (buying isn't a placement). Each button disables+dims itself
/// when `RulesEngine.legalMoves` has no matching move for the current state
/// (covers both "can't afford" and "no legal spot" in one check).
public struct BuildMenuView: View {
    public let viewModel: GameViewModel
    @Binding public var placementMode: PlacementMode?

    public init(viewModel: GameViewModel, placementMode: Binding<PlacementMode?>) {
        self.viewModel = viewModel
        self._placementMode = placementMode
    }

    @State private var errorMessage: String?

    public var body: some View {
        // Computed once per render and reused for all four affordability
        // checks below - `RulesEngine.legalMoves` is expensive (in
        // particular the road-building-card branch, which is O(edges^2)
        // with a full state copy per outer edge), so calling it separately
        // per button quadruples that cost for no benefit.
        let legalMoves = RulesEngine.legalMoves(for: viewModel.state)
        let canBuildRoad = legalMoves.contains { if case .buildRoad = $0 { true } else { false } }
        let canBuildSettlement = legalMoves.contains { if case .buildSettlement = $0 { true } else { false } }
        let canBuildCity = legalMoves.contains { if case .buildCity = $0 { true } else { false } }
        let canBuyDevCard = legalMoves.contains { if case .buyDevCard = $0 { true } else { false } }

        VStack(spacing: 4) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 10) {
                buildButton(
                    title: "Road", systemImage: "line.diagonal",
                    isEnabled: canBuildRoad, isArmed: placementMode == .road
                ) {
                    placementMode = (placementMode == .road) ? nil : .road
                }
                buildButton(
                    title: "Settlement", systemImage: "house.fill",
                    isEnabled: canBuildSettlement, isArmed: placementMode == .settlement
                ) {
                    placementMode = (placementMode == .settlement) ? nil : .settlement
                }
                buildButton(
                    title: "City", systemImage: "building.2.fill",
                    isEnabled: canBuildCity, isArmed: placementMode == .city
                ) {
                    placementMode = (placementMode == .city) ? nil : .city
                }
                buildButton(
                    title: "Dev Card", systemImage: "rectangle.stack.fill",
                    isEnabled: canBuyDevCard, isArmed: false
                ) {
                    perform(.buyDevCard)
                }
            }
        }
    }

    private func buildButton(title: String, systemImage: String, isEnabled: Bool, isArmed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isArmed ? Color.yellow.opacity(0.35) : Color(white: 0.18))
            )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
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
