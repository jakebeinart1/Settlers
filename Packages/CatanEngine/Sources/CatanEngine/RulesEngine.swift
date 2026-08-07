public enum RulesEngine {
    public static func legalMoves(for state: GameState) -> [GameMove] {
        switch state.phase {
        case .setupForward, .setupBackward:
            return SetupPhase.legalMoves(for: state)
        default:
            // Later tasks extend this switch for the other phases.
            return []
        }
    }

    public static func apply(_ move: GameMove, by player: PlayerID, to state: inout GameState) throws {
        switch state.phase {
        case .setupForward, .setupBackward:
            switch move {
            case .placeInitialSettlement, .placeInitialRoad:
                try SetupPhase.apply(move, by: player, to: &state)
            default:
                throw MoveError.wrongPhase
            }
        default:
            // Later tasks extend this switch for the other phases.
            throw MoveError.wrongPhase
        }
    }
}
