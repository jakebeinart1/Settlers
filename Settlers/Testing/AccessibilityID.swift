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

    enum InGameSettings {
        static let close = "in-game-settings.close"
    }

    enum Handoff {
        static let ready = "handoff.ready"
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
