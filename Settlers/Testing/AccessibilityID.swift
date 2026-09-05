import CatanEngine

/// Stable identifiers for behavior-driven UI tests.
///
/// Visible copy and artwork are product design; tests should survive those
/// changing. These identifiers name the action or screen the player reaches.
enum AccessibilityID {
    enum Screen {
        static let mainMenu = "screen.main-menu"
        static let newGame = "screen.new-game"
        static let game = "screen.game"
        static let inGameSettings = "screen.in-game-settings"
    }

    enum MainMenu {
        static let newGame = "main-menu.new-game"
        static let resume = "main-menu.resume"
        static let settings = "main-menu.settings"
    }

    enum NewGame {
        static let cancel = "new-game.cancel"
        static let start = "new-game.start"
        static let confirmOverwrite = "new-game.confirm-overwrite"
    }

    enum Board {
        static let stagedRoadPreview = "board.road-preview"

        static func tile(_ tile: HexCoordinate) -> String {
            "board.tile.\(tile.q)_\(tile.r)"
        }

        static func vertex(_ vertex: VertexID) -> String {
            "board.vertex." + vertex.touchingTiles.map(coordinate).joined(separator: ".")
        }

        static func edge(_ edge: EdgeID) -> String {
            "board.edge.\(vertex(edge.a)).\(vertex(edge.b))"
        }

        private static func coordinate(_ coordinate: HexCoordinate) -> String {
            "\(coordinate.q)_\(coordinate.r)"
        }
    }

    enum Game {
        static let settings = "game.settings"

        static func humanResource(_ resource: Resource) -> String {
            "human-resource.\(resource.rawValue)"
        }
    }

    enum Build {
        static let devCard = "build.dev-card"
    }

    enum DevCards {
        static let shelf = "dev-cards.shelf"
        static let overlay = "dev-cards.overlay"
        static let status = "dev-cards.status"
        static let viewHand = "dev-cards.view-hand"
        static let continueAction = "dev-cards.continue"
        static let close = "dev-cards.close"
        static let result = "dev-cards.result"
        static let resultContinue = "dev-cards.result.continue"

        static func tile(_ type: DevCardType) -> String { "dev-cards.tile.\(type.rawValue)" }
        static func detail(_ type: DevCardType) -> String { "dev-cards.detail.\(type.rawValue)" }
        static func play(_ type: DevCardType) -> String { "dev-cards.play.\(type.rawValue)" }
        static func resource(_ resource: Resource) -> String { "dev-cards.resource.\(resource.rawValue)" }
    }

    enum InGameSettings {
        static let close = "in-game-settings.close"
    }

    enum Handoff {
        static let ready = "handoff.ready"
    }

    enum Robber {
        static func victim(_ seat: PlayerID) -> String { "robber.victim.\(seat.index)" }
    }

    enum IncomingTrade {
        static let reject = "incoming-trade.reject"
        static let accept = "incoming-trade.accept"
    }

    enum Trade {
        static func giveChip(_ resource: Resource) -> String { "trade.give.\(resource.rawValue)" }
        static func wantChip(_ resource: Resource) -> String { "trade.want.\(resource.rawValue)" }
    }

    enum GameOver {
        static let newGame = "game-over.new-game"
    }
}
