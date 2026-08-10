import SwiftUI
import CatanEngine

/// One "Build" button (matching `UniformActionButton`'s look, so it sits
/// flush in the same button row as Trade/Dev Cards/turn action) that reveals
/// Road/Settlement/City/Dev Card as a native `Menu` rather than four
/// permanent buttons. Road/settlement/city options don't build directly -
/// picking one arms `placementMode` so `GameView` puts `BoardView` into
/// placement mode and the next vertex/edge tap performs the actual build.
/// The dev-card option acts immediately (buying isn't a placement). Each
/// option disables itself when `RulesEngine.legalMoves` has no matching move
/// for the current state (covers both "can't afford" and "no legal spot" in
/// one check) - unchanged from the four-button version, just relocated into
/// menu items.
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
        // per option quadruples that cost for no benefit.
        let legalMoves = RulesEngine.legalMoves(for: viewModel.state)
        let canBuildRoad = legalMoves.contains { if case .buildRoad = $0 { true } else { false } }
        let canBuildSettlement = legalMoves.contains { if case .buildSettlement = $0 { true } else { false } }
        let canBuildCity = legalMoves.contains { if case .buildCity = $0 { true } else { false } }
        let canBuyDevCard = legalMoves.contains { if case .buyDevCard = $0 { true } else { false } }
        let anyBuildAvailable = canBuildRoad || canBuildSettlement || canBuildCity || canBuyDevCard

        VStack(spacing: 4) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Menu {
                if placementMode != nil {
                    Button(role: .destructive) {
                        placementMode = nil
                    } label: {
                        Label("Cancel \(placementMode!.label)", systemImage: "xmark.circle")
                    }
                }
                Button {
                    placementMode = (placementMode == .road) ? nil : .road
                } label: {
                    Label("Road", systemImage: "line.diagonal")
                }
                .disabled(!canBuildRoad)

                Button {
                    placementMode = (placementMode == .settlement) ? nil : .settlement
                } label: {
                    Label("Settlement", systemImage: "house.fill")
                }
                .disabled(!canBuildSettlement)

                Button {
                    placementMode = (placementMode == .city) ? nil : .city
                } label: {
                    Label("City", systemImage: "building.2.fill")
                }
                .disabled(!canBuildCity)

                Button {
                    perform(.buyDevCard)
                } label: {
                    Label("Dev Card", systemImage: "rectangle.stack.fill")
                }
                .disabled(!canBuyDevCard)
            } label: {
                buildButtonLabel
            }
            .disabled(!anyBuildAvailable && placementMode == nil)
        }
    }

    /// Mirrors `UniformActionButton`'s icon-over-title look so the Build
    /// button reads as part of the same button row, with the armed
    /// (yellow-tinted) treatment while a placement mode is active - the
    /// label doubles as a reminder of *what* is armed rather than just
    /// staying "Build".
    private var buildButtonLabel: some View {
        VStack(spacing: 2) {
            Image(systemName: placementMode == nil ? "hammer.fill" : "hammer.circle.fill")
                .font(.title3)
            Text(placementMode == nil ? "Build" : placementMode!.label)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(placementMode != nil ? Color.yellow.opacity(0.35) : Color(white: 0.18))
        )
        .foregroundStyle(.white)
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

extension PlacementMode {
    var label: String {
        switch self {
        case .road: return "Road"
        case .settlement: return "Settlement"
        case .city: return "City"
        }
    }
}
