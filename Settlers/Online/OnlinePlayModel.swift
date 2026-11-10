import Foundation
import Observation
import CatanEngine
import EmpiresOnline

private struct OnlineSubmission: Codable {
    let accountID: UUID
    let matchID: UUID
    let command: OnlineCommand
}

/// The online shell owns one fixed account and no local game save. A move
/// becomes visible only when the authority returns its committed view.
@MainActor
@Observable
final class OnlinePlayModel {
    private static let submissionRetryInterval: Duration = .seconds(3)

    private(set) var account: OnlineAccount?
    private(set) var match: OnlineMatchView?
    private(set) var games: [OnlineGameSummary] = []
    private(set) var isWorking = false
    private(set) var isOffline = false
    private(set) var needsRecovery = false
    private(set) var isChangingAccount = false
    private(set) var receivedAt = ContinuousClock.now
    var message: String?

    var hasPendingSubmission: Bool { pending != nil }
    var isConfirmingMoveInAnotherMatch: Bool {
        guard let pending, let match else { return false }
        return pending.matchID != match.id
    }
    var hasStoredSession: Bool { bearer != nil }
    var recoveryKey: String? { bearer }

    @ObservationIgnored private let sendRequest: (@Sendable (OnlineRequest, String?) async throws -> OnlineResponse)?
    @ObservationIgnored private let storage: OnlineSecureStore?
    private var bearer: String?
    private var pending: OnlineSubmission?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isPolling = false
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var nextSubmissionRetry: ContinuousClock.Instant?
    @ObservationIgnored private(set) var lastRequestError: OnlineClientError?

    init() {
        let endpoint = OnlineTransport.configuredEndpoint
        storage = endpoint.map { OnlineSecureStore(endpoint: $0) }
        if let endpoint {
            let transport = OnlineTransport(endpoint: endpoint)
            sendRequest = { request, bearer in try await transport.send(request, bearer: bearer) }
        } else {
            sendRequest = nil
        }
    }

    init(storage: OnlineSecureStore, sendRequest: @escaping @Sendable (OnlineRequest, String?) async throws -> OnlineResponse) {
        self.storage = storage
        self.sendRequest = sendRequest
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        await perform {
            bearer = try requireStorage().readString(OnlineStorageKey.bearer)
            guard let bearer else { return }
            try await authenticate(using: bearer)
        }
        if account != nil { await retrySubmission() }
    }

    func reconnect() async {
        restored = false
        await restore()
    }

    func createAccount(named name: String) async {
        await perform {
            let response: OnlineResponse
            do {
                response = try await send(.createAccount(name: name), bearer: nil)
            } catch OnlineClientError.rejected(401, _) {
                throw OnlineClientError.accountEnrollmentRequired
            }
            guard case .account(let profile) = response, let key = profile.bearer, Self.isBearer(key) else {
                throw OnlineClientError.unexpectedResponse
            }
            try await adoptProfile(profile, key: key)
        }
    }

    func recover(using key: String) async {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isBearer(candidate) else {
            message = "Enter the complete recovery key."
            return
        }
        await perform { try await authenticate(using: candidate) }
        if account != nil { await retrySubmission() }
    }

    func signOut() async {
        await performAccountExit {
            try await OnlineDeviceRegistrar.shared.whilePaused {
                try await detachPriorDeviceIfNeeded()
                try clearSession()
            }
        }
    }

    func deleteAccount() async {
        await performAccountExit {
            try await OnlineDeviceRegistrar.shared.whilePaused {
                try requireOK(await send(.deleteAccount))
                invalidateSessionView()
                try clearSession()
            }
        }
    }

    private func performAccountExit(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isChangingAccount = true
        defer { isChangingAccount = false }
        await perform(operation)
    }

    func refresh() async {
        guard account != nil, !isWorking, !isPolling else { return }
        let requestedGeneration = generation
        let requestedMatch = match?.id
        isPolling = true
        defer { isPolling = false }
        do {
            let request = requestedMatch.map { OnlineRequest.view(matchID: $0) } ?? .list
            let response = try await send(request)
            guard requestedGeneration == generation else { return }
            try consume(response)
            isOffline = false
            await retrySubmissionIfDue()
        } catch is CancellationError {
            return
        } catch {
            guard requestedGeneration == generation, !Task.isCancelled else { return }
            handleRefreshError(error, matchID: requestedMatch)
        }
    }

    @discardableResult
    func run(_ request: OnlineRequest) async -> Bool {
        let succeeded = await perform { try consume(await send(request)) }
        if match == nil { await refresh() }
        return succeeded
    }

    func leave(_ id: UUID) async {
        guard await run(.leave(matchID: id)) else { return }
        await showGames()
    }

    func showGames(keepingMessage: Bool = false) async {
        generation += 1
        match = nil
        if !keepingMessage { message = nil }
        await refresh()
    }

    func submit(_ move: GameMove, in position: OnlineMatchView) async {
        guard let account, match?.id == position.id, match?.revision == position.revision,
              let viewer = position.gameplay?.viewer, pending == nil, !isWorking, !isOffline,
              let action = action(for: move, player: viewer, in: position) else { return }
        let command = OnlineCommand(decisionID: action.id, revision: position.revision, move: move)
        let submission = OnlineSubmission(accountID: account.id, matchID: position.id, command: command)
        do {
            try requireStorage().write(JSONEncoder().encode(submission), key: OnlineStorageKey.submission)
            pending = submission
        } catch {
            message = error.localizedDescription
            return
        }
        await retrySubmission()
    }

    private func retrySubmissionIfDue() async {
        guard !isWorking, pending != nil,
              nextSubmissionRetry.map({ $0 <= ContinuousClock.now }) ?? true else { return }
        nextSubmissionRetry = ContinuousClock.now.advanced(by: Self.submissionRetryInterval)
        await retrySubmission()
    }

    func retrySubmission() async {
        guard let submission = pending, submission.accountID == account?.id else { return }
        await perform {
            do {
                let response = try await send(.submit(matchID: submission.matchID, command: submission.command))
                guard case .match(let position) = response,
                      position.id == submission.matchID,
                      position.acknowledgedCommandID == submission.command.id else {
                    throw OnlineClientError.unexpectedResponse
                }
                try clearSubmission()
                // A notification or Your Games may have opened another match.
                // A receipt settles the durable command without changing navigation.
                if match?.id == submission.matchID { try consume(response) }
            } catch let error as OnlineClientError where error.definitelyRejected {
                try clearSubmission()
                if case .rejected(401, _) = error { throw error }
                if match?.id == submission.matchID {
                    try consume(await send(.view(matchID: submission.matchID)))
                    throw error
                }
                message = "A pending move in another match was not accepted. Open that match to see its current position."
            }
        }
    }

    private func action(for move: GameMove, player: PlayerID, in position: OnlineMatchView) -> OnlinePendingAction? {
        position.pending.first { action in
            guard action.seat == player else { return false }
            if case .respondToTrade = move { return action.kind == .trade }
            return action.kind != .trade
        }
    }

    private func authenticate(using key: String) async throws {
        guard case .account(let profile) = try await send(.profile, bearer: key) else {
            throw OnlineClientError.unexpectedResponse
        }
        try await adoptProfile(profile, key: key)
    }

    private func detachPriorDeviceIfNeeded() async throws {
        let storage = try requireStorage()
        guard let previousKey = try storage.readString(OnlineStorageKey.bearer) else { return }
        do {
            try await OnlineDeviceRegistrar.shared.unregister(from: storage.endpoint, bearer: previousKey)
        } catch OnlineClientError.rejected(401, _) {
            // The authority has already invalidated the old account key.
        }
    }

    private func adoptProfile(_ profile: OnlineAccount, key: String) async throws {
        let previousKey = try requireStorage().readString(OnlineStorageKey.bearer)
        try await OnlineDeviceRegistrar.shared.whilePaused {
            if previousKey != nil, previousKey != key { try await detachPriorDeviceIfNeeded() }
            try storeProfile(profile, key: key, changedAccount: previousKey != key)
        }
    }

    private func storeProfile(_ profile: OnlineAccount, key: String, changedAccount: Bool) throws {
        let storage = try requireStorage()
        if changedAccount { try storage.remove(OnlineStorageKey.submission) }
        pending = nil
        if let data = try storage.read(OnlineStorageKey.submission) {
            let saved = try JSONDecoder().decode(OnlineSubmission.self, from: data)
            if saved.accountID == profile.id { pending = saved }
        }
        try storage.write(Data(key.utf8), key: OnlineStorageKey.bearer)
        bearer = key
        account = profile
        needsRecovery = false
    }

    @discardableResult
    private func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !isWorking else { return false }
        generation += 1
        isWorking = true
        message = nil
        lastRequestError = nil
        defer { isWorking = false }
        do {
            try await operation()
            isOffline = false
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            lastRequestError = error as? OnlineClientError
            if case OnlineClientError.rejected(401, _) = error { invalidateSessionView() }
            if account == nil { needsRecovery = true }
            isOffline = isConnectionFailure(error)
            message = isOffline ? "Connection interrupted. Reconnect to check the current match." : error.localizedDescription
            return false
        }
    }

    private func handleRefreshError(_ error: any Error, matchID: UUID?) {
        if let client = error as? OnlineClientError {
            switch client {
            case .rejected(401, _):
                invalidateSessionView()
                message = client.localizedDescription
                return
            case .rejected(let code, _) where (code == 403 || code == 404) && matchID != nil:
                match = nil
                message = client.localizedDescription
                return
            default: break
            }
        }
        isOffline = true
    }

    private func send(_ request: OnlineRequest) async throws -> OnlineResponse {
        try await send(request, bearer: bearer)
    }

    private func send(_ request: OnlineRequest, bearer: String?) async throws -> OnlineResponse {
        guard let sendRequest else { throw OnlineClientError.unavailable }
        return try await sendRequest(request, bearer)
    }

    private func consume(_ response: OnlineResponse) throws {
        switch response {
        case .games(let list): games = list
        case .match(let position):
            match = position
            receivedAt = ContinuousClock.now
        case .ok: break
        case .account: throw OnlineClientError.unexpectedResponse
        }
    }

    private func requireOK(_ response: OnlineResponse) throws {
        guard case .ok = response else { throw OnlineClientError.unexpectedResponse }
    }

    private func clearSession() throws {
        let storage = try requireStorage()
        try storage.remove(OnlineStorageKey.bearer)
        invalidateSessionView()
        bearer = nil
        needsRecovery = false
        try clearSubmission()
    }

    private func invalidateSessionView() {
        generation += 1
        account = nil
        match = nil
        games = []
        pending = nil
        nextSubmissionRetry = nil
        needsRecovery = true
    }

    private func isConnectionFailure(_ error: any Error) -> Bool {
        if case OnlineClientError.rejected(let code, _) = error { return code >= 500 || code == 408 }
        return error is URLError
    }

    private func clearSubmission() throws {
        try requireStorage().remove(OnlineStorageKey.submission)
        pending = nil
        nextSubmissionRetry = nil
    }

    private func requireStorage() throws -> OnlineSecureStore {
        guard let storage else { throw OnlineClientError.unavailable }
        return storage
    }

    private static func isBearer(_ value: String) -> Bool {
        value.utf8.count == 72
            && UUID(uuidString: String(value.prefix(36))) != nil
            && UUID(uuidString: String(value.suffix(36))) != nil
    }

}
