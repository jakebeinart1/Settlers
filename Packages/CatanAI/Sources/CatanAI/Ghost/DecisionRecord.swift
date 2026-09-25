import CatanEngine

/// Which part of the game a decision belongs to. Accuracy is reported per
/// facet, because "plays like me" is judged facet by facet.
public enum Facet: String, Codable, CaseIterable, Sendable {
    case opening, turn, tradeResponse, robber, discard
}

public struct CandidateRecord: Codable, Sendable, Equatable {
    public let move: GameMove
    /// Expert's value at the anchor weights.
    public let score: Double
    /// d score / d weight, per `EvaluationWeights.vectorLabels` slot.
    public let gradient: [Double]
    public let style: [Double]

    public init(move: GameMove, score: Double, gradient: [Double], style: [Double]) {
        self.move = move
        self.score = score
        self.gradient = gradient
        self.style = style
    }
}

/// One decision a person made, with everything they could have done instead.
public struct DecisionRecord: Codable, Sendable, Equatable {
    public let game: String
    public let facet: Facet
    /// The weights `score` and `gradient` were taken at.
    public let anchor: [Double]
    public let candidates: [CandidateRecord]
    public let chosen: Int

    public init(game: String, facet: Facet, anchor: [Double], candidates: [CandidateRecord], chosen: Int) {
        self.game = game
        self.facet = facet
        self.anchor = anchor
        self.candidates = candidates
        self.chosen = chosen
    }
}

public struct LoggedMove: Sendable {
    public let player: PlayerID
    public let move: GameMove

    public init(player: PlayerID, move: GameMove) {
        self.player = player
        self.move = move
    }
}

/// A recorded game, independent of where it was stored.
public struct LoggedGame: Sendable {
    public let id: String
    public let initialState: GameState
    public let humanSeats: Set<PlayerID>
    public let events: [LoggedMove]

    public init(id: String, initialState: GameState, humanSeats: Set<PlayerID>, events: [LoggedMove]) {
        self.id = id
        self.initialState = initialState
        self.humanSeats = humanSeats
        self.events = events
    }
}
