import CatanEngine
import CatanAI
import SwiftUI

extension GameView {
    /// Kept outside the game layout: this Debug-only inspector cannot resize
    /// the board or replace a production action. It releases an ordinary
    /// policy-driven match only after native card inspection has finished.
    @ViewBuilder
    func qaCompleteMatchInspectionControl() -> some View {
        #if DEBUG
        if QACompleteMatchInspection.isEnabled, QACompleteMatchInspection.shared.isPaused {
            Button("Continue inspected match") { QACompleteMatchInspection.shared.resume() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(8)
                .background(.black)
                .accessibilityIdentifier("qa.complete-match.continue")
                .accessibilityValue(QACompleteMatchInspection.shared.message)
        }
        #endif
    }

    /// A held, deliberately overbroad highlight list lets native pixel tests
    /// exercise the renderer's fog guard independently of the roll producer.
    /// No move, discovery, production, or persistence is fabricated.
    @ViewBuilder
    func qaProductionHighlightControl(onToggle: @escaping (Set<HexCoordinate>) -> Void) -> some View {
        #if DEBUG
        if NavalProductionHighlightQA.isEnabled {
            Button("Show held production rings") {
                let sites = NavalProductionHighlightQA.sites(in: viewModel.state)
                onToggle([sites.known.coordinate, sites.hidden.coordinate])
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black)
            .accessibilityIdentifier("qa.production.show")
        }
        #endif
    }

    /// Autoplays setup and resolves the human's first roll until the ordinary
    /// main-turn controls are genuinely usable. A first roll of seven can add
    /// discard and robber decisions, so stopping immediately after `.rollDice`
    /// leaves visual and UI tests on a disabled action row intermittently.
    /// This remains a visual-QA route only; `QALaunchFlag.isSet` makes it
    /// unreachable in Release.
    func qaFastForwardToRollDiceIfRequested() async {
        #if DEBUG
        guard QALaunchFlag.fastForwardToRollDice.isSet else { return }
        let human = viewModel.humanPlayer
        let bot = Bot(personality: .balanced)
        for _ in 0..<20 {
            switch viewModel.state.phase {
            case .mainTurn(let playerIndex) where playerIndex == human.index:
                return
            case .rollDice(let playerIndex) where playerIndex == human.index:
                await applyQA(.rollDice)
            // Swift binds a `where` only to the pattern immediately before it,
            // so both snake-order cases need their own human-seat condition.
            case .setupForward(let playerIndex) where playerIndex == human.index,
                 .setupBackward(let playerIndex) where playerIndex == human.index:
                let move = bot.decide(for: viewModel.state, player: human)
                await applyQA(move)
            case .discarding(let pending) where pending.contains(human):
                let move = bot.decide(for: viewModel.state, player: human)
                await applyQA(move)
            case .movingRobber(let playerIndex) where playerIndex == human.index:
                let move = bot.decide(for: viewModel.state, player: human)
                await applyQA(move)
            case .choosingResource(let playerIndex) where playerIndex == human.index,
                 .capturingShip(let playerIndex) where playerIndex == human.index:
                let move = bot.decide(for: viewModel.state, player: human)
                await applyQA(move)
            default:
                await viewModel.runBotTurnIfNeeded()
            }
        }
        preconditionFailure("QA fast-forward did not reach the human's playable main turn")
        #endif
    }

    #if DEBUG
    private func applyQA(_ move: GameMove) async {
        do {
            try viewModel.apply(move)
            // The fixture has just supplied the exact confirmed move, but
            // SwiftUI has not rendered the cleared mandatory-decision state
            // back into this mirrored hold yet. Release that stale QA-only
            // value before asking the real policy loop to advance the bots.
            viewModel.isBlockingSurfaceOpen = false
            await viewModel.runBotTurnIfNeeded()
        } catch {
            preconditionFailure("QA fast-forward rejected \(move): \(error)")
        }
    }
    #endif
}

#if DEBUG
/// Kept beside its sole visual fixture. The raw argument is compiled out of
/// Release and changes only ephemeral highlight presentation in Debug.
private enum NavalProductionHighlightQA {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-qaNavalProductionHighlights") }

    static func sites(in state: GameState) -> (known: Tile, hidden: Tile) {
        guard let naval = state.naval else { preconditionFailure("Production probes require a naval world") }
        let tiles = state.board.tiles.sorted { $0.coordinate < $1.coordinate }
        let known = tiles.filter {
            $0.kind.produces && $0.numberToken != nil && naval.revealed.contains($0.coordinate)
                && $0.coordinate != state.board.robberTile && $0.coordinate.distance(to: .init(q: 0, r: 0)) <= 1
        }
        for hidden in tiles where hidden.kind.produces && !naval.revealed.contains(hidden.coordinate) {
            if let control = known.first(where: { $0.numberToken == hidden.numberToken }) {
                return (control, hidden)
            }
        }
        preconditionFailure("The naval visual fixture needs hidden and known production with the same number")
    }
}

extension BoardView {
    /// Sample six edge midpoints, where the white production stroke is
    /// painted. Center probes would miss this information leak completely.
    @ViewBuilder
    func qaProductionHighlightMarkers(geometry: HexGeometry) -> some View {
        if NavalProductionHighlightQA.isEnabled {
            let sites = NavalProductionHighlightQA.sites(in: state)
            ZStack {
                productionProbeMarkers(for: sites.known, role: "known", geometry: geometry)
                productionProbeMarkers(for: sites.hidden, role: "hidden", geometry: geometry)
            }
            .allowsHitTesting(false)
        }
    }

    private func productionProbeMarkers(for tile: Tile, role: String, geometry: HexGeometry) -> some View {
        let inset = HexGeometry(origin: geometry.origin, size: geometry.size * 0.93)
        let center = geometry.center(of: tile.coordinate)
        let insetCenter = inset.center(of: tile.coordinate)
        return ForEach(0..<6, id: \.self) { index in
            let first = inset.corner(of: tile.coordinate, index: index)
            let second = inset.corner(of: tile.coordinate, index: (index + 1) % 6)
            Color.white.opacity(0.001)
                .frame(width: 1, height: 1)
                .position(x: (first.x + second.x) / 2 + center.x - insetCenter.x,
                          y: (first.y + second.y) / 2 + center.y - insetCenter.y)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("qa.production.\(role).\(index)")
                .accessibilityLabel("\(role) production probe \(tile.coordinate.q)_\(tile.coordinate.r)")
                .accessibilityValue("number=\(tile.numberToken!)")
                .accessibilityRespondsToUserInteraction(false)
        }
    }
}
#endif
