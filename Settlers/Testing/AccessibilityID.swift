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
        static let surface = "board.surface"
        static let stagedRoadPreview = "board.road-preview"
        static let stagedBuildingPreview = "board.building-preview"
        static let stagedRobberPreview = "board.robber-preview"
        static let robberOrigin = "board.robber-origin"
        static let dragCradle = "board.drag-cradle"
        /// Shown only while the camera is off its fitted resting position,
        /// so its presence is also the assertion that a gesture moved it.
        static let recenter = "board.recenter"

        static func tile(_ tile: HexCoordinate) -> String {
            "board.tile.\(tile.q)_\(tile.r)"
        }

        static func vertex(_ vertex: VertexID) -> String {
            "board.vertex." + vertex.touchingTiles.map(coordinate).joined(separator: ".")
        }

        static func edge(_ edge: EdgeID) -> String {
            "board.edge.\(vertex(edge.a)).\(vertex(edge.b))"
        }

        static func inspectionTile(_ tile: HexCoordinate) -> String {
            "board.inspect.tile.\(coordinate(tile))"
        }

        static func inspectionPort(_ index: Int) -> String {
            "board.inspect.port.\(index)"
        }

        static func inspectionBuilding(_ vertex: VertexID) -> String {
            "board.inspect.building." + vertex.touchingTiles.map(coordinate).joined(separator: ".")
        }

        static func inspectionRoad(_ edge: EdgeID) -> String {
            "board.inspect.road.\(vertex(edge.a)).\(vertex(edge.b))"
        }

        private static func coordinate(_ coordinate: HexCoordinate) -> String {
            "\(coordinate.q)_\(coordinate.r)"
        }
    }

    enum BoardDecision {
        static let dock = "board-decision.dock"
        static let confirm = "board-decision.confirm"
        static let clear = "board-decision.clear"
        static let cancel = "board-decision.cancel"
        static let undo = "board-decision.undo"
    }

    enum Game {
        static let settings = "game.settings"

        static func humanResource(_ resource: Resource) -> String {
            "human-resource.\(resource.rawValue)"
        }
    }

    enum Build {
        static let road = "build.road"
        static let settlement = "build.settlement"
        static let city = "build.city"
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

    enum Discard {
        static let editor = "discard.editor"
        static let progress = "discard.progress"
        static let minimize = "discard.minimize"
        static let dock = "discard.dock"
        static let submit = "discard.submit"

        static func hand(_ resource: Resource) -> String {
            "discard.hand.\(resource.rawValue)"
        }
    }

    enum InGameSettings {
        static let close = "in-game-settings.close"
    }

    enum Handoff {
        static let ready = "handoff.ready"
    }

    enum Robber {
        static func victim(_ seat: PlayerID) -> String { "robber.victim.\(seat.index)" }
        static func victimCivilization(_ seat: PlayerID) -> String {
            "robber.victim.civilization.\(seat.index)"
        }
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
