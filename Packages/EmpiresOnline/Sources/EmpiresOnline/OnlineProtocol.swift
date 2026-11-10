import CatanEngine
import Foundation

/// Version 1 requests travel in a JSON POST. A separate Authorization header
/// authenticates every operation except account creation.
public enum OnlineRequest: Codable, Sendable {
    case createAccount(name: String)
    case profile
    case deleteAccount
    case list
    case createRoom(configuration: OnlineConfiguration, civilization: String)
    case join(code: String, civilization: String)
    case view(matchID: UUID)
    case configure(matchID: UUID, configuration: OnlineConfiguration, revision: Int)
    case ready(matchID: UUID, isReady: Bool, revision: Int)
    case start(matchID: UUID, revision: Int)
    case submit(matchID: UUID, command: OnlineCommand)
    case leave(matchID: UUID)
    case mute(matchID: UUID, muted: Bool)
    case registerDevice(installationID: UUID, token: String, environment: OnlinePushEnvironment)
    case unregisterDevice(installationID: UUID)
}

public enum OnlineResponse: Codable, Sendable {
    case account(OnlineAccount)
    case games([OnlineGameSummary])
    case match(OnlineMatchView)
    case ok
}

public enum OnlineError: String, Codable, Sendable, Error, LocalizedError {
    case unauthorized, forbidden, notFound, conflict, invalidRequest, unavailable, bankStockUnavailable

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Your online key is invalid or has been deleted."
        case .forbidden: "You do not have access to that action."
        case .notFound: "That room or game could not be found."
        case .conflict: "The game changed. Review the latest position before acting."
        case .invalidRequest: "That choice is unavailable. Check the current game and try again."
        case .unavailable: "Online play is temporarily unavailable. Try again shortly."
        case .bankStockUnavailable: "The bank cannot supply that many cards. Try requesting fewer cards or a different resource."
        }
    }
}

public struct OnlineAccount: Codable, Sendable {
    public let id: UUID
    public let name: String
    /// Returned only when an account is created.
    public let bearer: String?
}

public enum OnlinePace: String, Codable, CaseIterable, Sendable {
    case asynchronous, timedLive
}

public enum OnlineSeatRole: String, Codable, CaseIterable, Sendable {
    case open, human, classicAI, expertAI

    var isBot: Bool { self == .classicAI || self == .expertAI }
}

public enum OnlineMatchStatus: String, Codable, Sendable {
    case lobby, playing, finished, cancelled
}

public enum OnlineDeadlineKind: String, Codable, Sendable {
    case setup, turn, response, trade

    public func seconds(in pace: OnlinePace) -> TimeInterval? {
        switch (self, pace) {
        case (.trade, .asynchronous): 12 * 60 * 60
        case (.setup, .timedLive): 60
        case (.turn, .timedLive): 90
        case (.response, .timedLive): 45
        case (.trade, .timedLive): 30
        default: nil
        }
    }
}

public struct OnlineConfiguration: Codable, Equatable, Sendable {
    public let pace: OnlinePace
    public let mode: GameMode
    public let rules: GameVariant
    /// A slot can be open (nil) or filled with a bot. Human reservations are
    /// server-owned, and the first slot is reserved for the initial host.
    public let aiSeats: [OnlineSeatRole?]

    public init(pace: OnlinePace, mode: GameMode, rules: GameVariant, aiSeats: [OnlineSeatRole?]) {
        self.pace = pace
        self.mode = mode
        self.rules = rules
        self.aiSeats = aiSeats
    }
}

public struct OnlineSeat: Codable, Sendable {
    public let role: OnlineSeatRole
    public let name: String?
    public let civilization: String?
    public let ready: Bool
    public let isYou: Bool

    public init(role: OnlineSeatRole, name: String?, civilization: String?, ready: Bool, isYou: Bool) {
        self.role = role
        self.name = name
        self.civilization = civilization
        self.ready = ready
        self.isYou = isYou
    }
}

public struct OnlineGameSummary: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let status: OnlineMatchStatus
    public let pace: OnlinePace
    public let needsYou: Bool
    public let turnName: String?
}

public struct OnlineMatchView: Codable, Sendable, Identifiable {
    public let id: UUID
    public let code: String
    public let configuration: OnlineConfiguration
    public let seats: [OnlineSeat]
    public let host: Bool
    public let viewer: PlayerID
    public let revision: Int
    public let lobbyRevision: Int
    public let gameplay: OnlineGameplayView?
    public let pending: [OnlinePendingAction]
    public let serverTime: Date
    public let isMuted: Bool
    public let status: OnlineMatchStatus
    public let acknowledgedCommandID: UUID?
}

public struct OnlinePendingAction: Codable, Sendable, Identifiable {
    public let id: UUID
    public let seat: PlayerID
    public let kind: OnlineDeadlineKind
    public let deadline: Date?
}

public struct OnlineCommand: Codable, Equatable, Sendable {
    public let id: UUID
    public let decisionID: UUID
    public let revision: Int
    public let move: GameMove

    public init(id: UUID = UUID(), decisionID: UUID, revision: Int, move: GameMove) {
        self.id = id
        self.decisionID = decisionID
        self.revision = revision
        self.move = move
    }
}

public enum OnlinePushEnvironment: String, Codable, Sendable {
    case development, production
}

public enum OnlinePushResult: Sendable {
    case sent, retry, invalidToken
}

public struct OnlinePush: Sendable, Identifiable {
    public let id: UUID
    public let matchID: UUID
    public let decisionID: UUID
    public let token: String
    public let environment: OnlinePushEnvironment
    public let expiresAt: Date?
}
