import CatanEngine

/// Frozen Eli6th v1 wire values shared by observation and action translation.
/// These are model-contract constants, not Empires enum ordinals or tunable
/// rules. Keep the numeric values and resource order stable across refactors.
enum UpstreamCodec {
    static let resources: [Resource] = [.grain, .wool, .lumber, .brick, .ore]

    enum GamePhase {
        static let setupForward = 0
        static let setupBackward = 1
        static let playing = 2
        static let finished = 3
        static let validRange = 0..<4
    }

    enum TurnPhase {
        static let beforeRoll = 0
        static let rollDice = 1
        static let discarding = 2
        static let movingRobber = 3
        static let choosingVictim = 4
        static let mainTurn = 5
        static let roadBuilding = 6
        // Preserve validation of all nine upstream slots, including trade
        // phases handled outside this adapter's neural decision path.
        static let validRange = 0..<9
    }

    enum Action {
        static let count = 299
        static let cityOffset = 54
        static let roadOffset = 108
        static let robberTiles = 180..<199
        // Relative opponents are numbered from one, so the first victim is 199.
        static let victimRelativeOffset = 198
        static let noVictim = 202
        static let discardOffset = 203
        static let monopolyOffset = 208
        static let yearOfPlenty = 213..<228
        static let bankTradeOffset = 228
        static let rollDice = 294
        static let buyDevelopmentCard = 295
        static let knight = 296
        static let roadBuilding = 297
        static let endTurn = 298
    }
}
