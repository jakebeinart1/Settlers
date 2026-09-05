import Foundation
import CatanEngine

/// Every spatial choice the player can stage on the board.
///
/// Mandatory intents are reconstructed from `GamePhase`; optional intents are
/// explicitly started from Build or the development-card hand. None of these
/// values enter `GameState` because a proposal is not part of the match yet.
public enum BoardDecisionIntent: Sendable, Equatable {
    case initialSettlement
    case initialRoad
    case buildRoad
    case buildSettlement
    case buildCity
    case roadBuilding
    case robberAfterSeven
    case knight

    public var canCancel: Bool {
        switch self {
        case .initialSettlement, .initialRoad, .robberAfterSeven: false
        case .buildRoad, .buildSettlement, .buildCity, .roadBuilding, .knight: true
        }
    }

    public var isRobber: Bool { self == .robberAfterSeven || self == .knight }
}

/// One input vocabulary for taps, drags, VoiceOver, and UI automation.
public enum BoardTarget: Sendable, Hashable {
    case vertex(VertexID)
    case edge(EdgeID)
    case tile(HexCoordinate)
    case victim(PlayerID)
}

/// Semantic projection consumed by the board and its command dock.
///
/// It deliberately exposes no `GameMove`: views can render and send targets,
/// but only `GameViewModel.confirmBoardDecision()` can reach durable commit.
public struct BoardDecisionPresentation: Sendable, Equatable {
    public let intent: BoardDecisionIntent
    public let actor: PlayerID
    /// One-based setup pass for initial pieces; `nil` for every other intent.
    public let setupRound: Int?
    public let legalVertices: [VertexID]
    public let legalEdges: [EdgeID]
    public let legalTiles: [HexCoordinate]
    public let legalVictims: [PlayerID]
    public let selectedVertex: VertexID?
    public let selectedEdges: [EdgeID]
    public let selectedTile: HexCoordinate?
    public let selectedVictim: PlayerID?
    public let canConfirm: Bool
    public let canCancel: Bool
    public let errorMessage: String?
}

/// Identifies the canonical position a thought belongs to. A failed move keeps
/// the same count, while a committed move or new match changes it and
/// invalidates stale optional intent. Checkpoint-only writes such as elapsed
/// time deliberately do not count, so backgrounding cannot erase a proposal.
struct BoardDecisionContext: Sendable {
    let matchID: UUID?
    let committedMoveCount: Int
    let actor: PlayerID
    let state: GameState

    var position: Position { Position(matchID: matchID, committedMoveCount: committedMoveCount) }

    struct Position: Sendable, Equatable {
        let matchID: UUID?
        let committedMoveCount: Int
    }
}

/// Owns every uncommitted spatial proposal and narrows complete legal moves.
///
/// The engine remains the only rules authority. This coordinator never asks
/// whether a vertex, edge, tile, or victim is legal by recreating a rule; it
/// projects complete `RulesEngine.legalMoves` into partial choices and returns
/// one of those exact moves only after the proposal is complete.
struct BoardDecisionCoordinator: Sendable {
    private struct Draft: Sendable {
        let intent: BoardDecisionIntent
        let actor: PlayerID
        let position: BoardDecisionContext.Position
        var setupRound: Int?
        var candidates: [GameMove]
        var selection: [BoardTarget]
        var errorMessage: String?
    }

    private var draft: Draft?

    var presentation: BoardDecisionPresentation? {
        guard let draft else { return nil }
        let boardTargets = boardTargets(for: draft)
        return BoardDecisionPresentation(
            intent: draft.intent,
            actor: draft.actor,
            setupRound: draft.setupRound,
            legalVertices: boardTargets.compactMap(\.vertex),
            legalEdges: boardTargets.compactMap(\.edge),
            legalTiles: firstTargets(in: draft).compactMap(\.tile),
            legalVictims: victimTargets(in: draft),
            selectedVertex: draft.selection.compactMap(\.vertex).first,
            selectedEdges: draft.selection.compactMap(\.edge),
            selectedTile: draft.selection.compactMap(\.tile).first,
            selectedVictim: draft.selection.compactMap(\.victim).first,
            canConfirm: confirmableMove != nil,
            canCancel: draft.intent.canCancel,
            errorMessage: draft.errorMessage
        )
    }

    var confirmableMove: GameMove? {
        guard let draft else { return nil }
        return draft.candidates.first { path(for: $0, intent: draft.intent) == draft.selection }
    }

    mutating func reconcile(with context: BoardDecisionContext) {
        if draft?.position != context.position || draft?.actor != context.actor {
            draft = nil
        }
        let required = requiredIntent(in: context)
        if let required {
            reconcileRequired(required, context: context)
        } else if draft?.intent.canCancel == false {
            draft = nil
        } else {
            refreshOptionalDraft(in: context)
        }
    }

    @discardableResult
    mutating func begin(_ intent: BoardDecisionIntent, with context: BoardDecisionContext) -> Bool {
        guard intent.canCancel, requiredIntent(in: context) == nil else { return false }
        let candidates = candidateMoves(for: intent, in: context)
        guard !candidates.isEmpty else { return false }
        draft = Draft(intent: intent, actor: context.actor, position: context.position,
                      setupRound: nil, candidates: candidates,
                      selection: [], errorMessage: nil)
        return true
    }

    @discardableResult
    mutating func select(_ target: BoardTarget) -> Bool {
        guard var draft else { return false }
        let didSelect = select(target, in: &draft)
        if didSelect { draft.errorMessage = nil; self.draft = draft }
        return didSelect
    }

    mutating func clearSelection() {
        guard var draft else { return }
        draft.selection = []
        draft.errorMessage = nil
        self.draft = draft
    }

    @discardableResult
    mutating func undoSelection() -> Bool {
        guard var draft, !draft.selection.isEmpty else { return false }
        draft.selection.removeLast()
        draft.errorMessage = nil
        self.draft = draft
        return true
    }

    @discardableResult
    mutating func cancel() -> Bool {
        guard draft?.intent.canCancel == true else { return false }
        draft = nil
        return true
    }

    mutating func clear() { draft = nil }

    mutating func reportFailure(_ message: String) {
        guard var draft else { return }
        draft.errorMessage = message
        self.draft = draft
    }

    private mutating func reconcileRequired(
        _ intent: BoardDecisionIntent,
        context: BoardDecisionContext
    ) {
        let candidates = candidateMoves(for: intent, in: context)
        precondition(!candidates.isEmpty, "mandatory board decision has no legal move")
        if var current = draft, current.intent == intent {
            current.setupRound = setupRound(in: context.state)
            current.candidates = candidates
            current.selection = validPrefix(current.selection, candidates: candidates, intent: intent)
            draft = current
        } else {
            draft = Draft(intent: intent, actor: context.actor, position: context.position,
                          setupRound: setupRound(in: context.state), candidates: candidates,
                          selection: [], errorMessage: nil)
        }
    }

    private func setupRound(in state: GameState) -> Int? {
        switch state.phase {
        case .setupForward: 1
        case .setupBackward: 2
        default: nil
        }
    }

    private mutating func refreshOptionalDraft(in context: BoardDecisionContext) {
        guard var current = draft else { return }
        let candidates = candidateMoves(for: current.intent, in: context)
        guard !candidates.isEmpty else { draft = nil; return }
        current.candidates = candidates
        current.selection = validPrefix(
            current.selection, candidates: candidates, intent: current.intent)
        draft = current
    }

    private func requiredIntent(in context: BoardDecisionContext) -> BoardDecisionIntent? {
        guard context.state.phase.awaitingSeatIndex == context.actor.index else { return nil }
        let moves = RulesEngine.legalMoves(for: context.state, seat: context.actor)
        switch context.state.phase {
        case .setupForward, .setupBackward:
            if moves.contains(where: { if case .placeInitialSettlement = $0 { true } else { false } }) {
                return .initialSettlement
            }
            if moves.contains(where: { if case .placeInitialRoad = $0 { true } else { false } }) {
                return .initialRoad
            }
            return nil
        case .movingRobber:
            return .robberAfterSeven
        default:
            return nil
        }
    }

    private func candidateMoves(
        for intent: BoardDecisionIntent,
        in context: BoardDecisionContext
    ) -> [GameMove] {
        guard context.state.phase.awaitingSeatIndex == context.actor.index else { return [] }
        return RulesEngine.legalMoves(for: context.state, seat: context.actor).filter {
            path(for: $0, intent: intent) != nil
        }
    }

    private func select(_ target: BoardTarget, in draft: inout Draft) -> Bool {
        switch draft.intent {
        case .robberAfterSeven, .knight:
            return selectRobber(target, in: &draft)
        case .roadBuilding:
            return selectRoadBuilding(target, in: &draft)
        default:
            guard firstTargets(in: draft).contains(target) else { return false }
            draft.selection = [target]
            return true
        }
    }

    private func selectRobber(_ target: BoardTarget, in draft: inout Draft) -> Bool {
        switch target {
        case .tile where firstTargets(in: draft).contains(target):
            draft.selection = [target]
            return true
        case .victim:
            guard draft.selection.first?.tile != nil,
                  nextTargets(in: draft, after: 1).contains(target) else { return false }
            draft.selection = [draft.selection[0], target]
            return true
        default:
            return false
        }
    }

    private func selectRoadBuilding(_ target: BoardTarget, in draft: inout Draft) -> Bool {
        guard case .edge = target else { return false }
        if draft.selection.isEmpty {
            guard firstTargets(in: draft).contains(target) else { return false }
            draft.selection = [target]
            return true
        }
        let secondTargets = nextTargets(in: draft, after: 1)
        if secondTargets.contains(target) {
            draft.selection = [draft.selection[0], target]
            return true
        }
        guard firstTargets(in: draft).contains(target) else { return false }
        draft.selection = [target]
        return true
    }

    private func boardTargets(for draft: Draft) -> [BoardTarget] {
        switch draft.intent {
        case .roadBuilding where !draft.selection.isEmpty:
            return nextTargets(in: draft, after: 1)
        default:
            return firstTargets(in: draft)
        }
    }

    private func victimTargets(in draft: Draft) -> [PlayerID] {
        guard draft.intent.isRobber, !draft.selection.isEmpty else { return [] }
        return nextTargets(in: draft, after: 1).compactMap(\.victim)
    }

    private func firstTargets(in draft: Draft) -> [BoardTarget] {
        uniqueTargets(draft.candidates.compactMap { path(for: $0, intent: draft.intent)?.first })
    }

    private func nextTargets(in draft: Draft, after count: Int) -> [BoardTarget] {
        let prefix = Array(draft.selection.prefix(count))
        return uniqueTargets(draft.candidates.compactMap { move in
            guard let path = path(for: move, intent: draft.intent), path.count > count,
                  Array(path.prefix(count)) == prefix else { return nil }
            return path[count]
        })
    }

    private func validPrefix(
        _ selection: [BoardTarget],
        candidates: [GameMove],
        intent: BoardDecisionIntent
    ) -> [BoardTarget] {
        var retained: [BoardTarget] = []
        for target in selection {
            let proposed = retained + [target]
            guard candidates.contains(where: {
                guard let path = path(for: $0, intent: intent) else { return false }
                return Array(path.prefix(proposed.count)) == proposed
            }) else { break }
            retained = proposed
        }
        return retained
    }

    private func uniqueTargets(_ values: [BoardTarget]) -> [BoardTarget] {
        var seen: Set<BoardTarget> = []
        return values.filter { seen.insert($0).inserted }
    }

    private func path(for move: GameMove, intent: BoardDecisionIntent) -> [BoardTarget]? {
        switch (intent, move) {
        case (.initialSettlement, .placeInitialSettlement(let vertex)),
             (.buildSettlement, .buildSettlement(let vertex)),
             (.buildCity, .buildCity(let vertex)):
            return [.vertex(vertex)]
        case (.initialRoad, .placeInitialRoad(let edge)),
             (.buildRoad, .buildRoad(let edge)):
            return [.edge(edge)]
        case (.roadBuilding, .playRoadBuilding(let first, let second)):
            return [.edge(first), .edge(second)]
        case (.robberAfterSeven, .moveRobber(let tile, let victim)),
             (.knight, .playKnight(let tile, let victim)):
            return [.tile(tile)] + (victim.map { [.victim($0)] } ?? [])
        default:
            return nil
        }
    }
}

private extension BoardTarget {
    var vertex: VertexID? { if case .vertex(let value) = self { value } else { nil } }
    var edge: EdgeID? { if case .edge(let value) = self { value } else { nil } }
    var tile: HexCoordinate? { if case .tile(let value) = self { value } else { nil } }
    var victim: PlayerID? { if case .victim(let value) = self { value } else { nil } }
}
