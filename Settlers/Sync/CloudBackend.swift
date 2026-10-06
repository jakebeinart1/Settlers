import CatanAI
import Foundation

/// A name on the shared ladder and the Apple ID that holds it.
struct NameClaim: Codable, Equatable, Sendable {
    /// The name as first claimed.
    let name: String
    /// The opaque CloudKit user id of the claimant.
    let owner: String
}

/// A record as downloaded: its content, who created it, and when the server
/// last changed it.
struct Downloaded<Value: Sendable>: Sendable {
    let value: Value
    let owner: String
    let modified: Date
}

enum CloudSyncError: Error, Equatable {
    /// No iCloud account on this device, or it is restricted.
    case noAccount
    /// No network, or the service is busy; the next sync retries.
    case unavailable
    case failed(String)
}

/// What `LiveSync` needs from the shared database.
///
/// CloudKit in the app (`CloudKitBackend`); an in-memory one in the tests,
/// because CloudKit cannot run inside a test process. Everything that decides
/// anything - who owns a name, whether a game is real, what the ratings are -
/// lives in `LiveSync` and `SharedMatch`, so the tests exercise it all.
///
/// ## The one guarantee the backend must give
/// A record can be changed only by the Apple ID that created it. That is
/// CloudKit's default for the public database ("Creator: write"), and it is
/// what makes a name claim mean something: the first Apple ID to create
/// `name-jake` owns "Jake" for good. It is also why a record's owner is its
/// uploader's player id: nobody can post a game or a ghost as someone else.
protocol CloudBackend: Sendable {
    /// This device's iCloud user id.
    func currentUser() async throws -> String
    /// Claims `slug` for the current user under `name`, or returns the claim
    /// someone already holds.
    func claim(slug: String, name: String) async throws -> NameClaim
    /// Sets the name the current user goes by on the ladder. A rename is
    /// this one write: their games, rating and ghost are filed under their
    /// user id, which does not change.
    func setName(_ name: String) async throws
    /// The ladder names of `ids`, each as set by that user; an id that has
    /// never set one is absent.
    func names(of ids: [String]) async throws -> [String: String]
    /// The account holding each claimed name slug; an unclaimed slug is absent.
    /// Read-only, unlike `claim`.
    func claimants(of slugs: [String]) async throws -> [String: String]
    /// Idempotent by match id.
    func upload(_ match: SharedMatch) async throws
    /// Every game changed after `date`, or all of them for `nil`.
    func matches(modifiedAfter date: Date?) async throws -> [Downloaded<SharedMatch>]
    /// Creates or replaces the current user's copy of this ghost.
    func upload(_ ghost: GhostProfile) async throws
    func ghosts() async throws -> [Downloaded<GhostProfile>]
}
