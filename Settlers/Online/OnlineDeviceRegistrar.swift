import Foundation
import EmpiresOnline

/// The installation identifier survives a relaunch. The APNs token does not:
/// each process obtains the current token from iOS before using it.
@MainActor
final class OnlineDeviceRegistrar {
    static let shared = OnlineDeviceRegistrar()

    private struct Registration: Equatable {
        let endpoint: URL
        let bearer: String
        let token: String
    }

    private var registered: Registration?
    private var inFlight: Task<Void, Never>?
    private var paused = 0
    private var retryAt = ContinuousClock.now

    func resume() async {
        guard let endpoint = OnlineTransport.configuredEndpoint, pushEnvironment != nil,
              let bearer = try? OnlineSecureStore(endpoint: endpoint).readString(OnlineStorageKey.bearer),
              !bearer.isEmpty else { return }
        await OnlineNotificationRouter.shared.registerIfAlreadyAuthorized()
        if let token = OnlineNotificationRouter.shared.deviceToken { await register(token: token) }
    }

    func register(token: String) async {
        guard paused == 0, inFlight == nil, ContinuousClock.now >= retryAt,
              let endpoint = OnlineTransport.configuredEndpoint, let environment = pushEnvironment,
              let bearer = try? OnlineSecureStore(endpoint: endpoint).readString(OnlineStorageKey.bearer),
              !bearer.isEmpty else { return }
        let registration = Registration(endpoint: endpoint, bearer: bearer, token: token)
        guard registered != registration else { return }
        let task = Task { await post(registration, environment: environment) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Account changes wait for any possible old registration before unbinding
    /// it. A delayed APNs callback cannot reattach the previous account.
    func whilePaused(_ operation: @MainActor () async throws -> Void) async rethrows {
        paused += 1
        defer { paused -= 1 }
        _ = await inFlight?.value
        try await operation()
    }

    func unregister(from endpoint: URL, bearer: String) async throws {
        let store = OnlineSecureStore(endpoint: endpoint)
        guard let raw = try store.readString(OnlineStorageKey.installation) else { return }
        guard let id = UUID(uuidString: raw) else { throw OnlineClientError.secureStorage }
        let response = try await OnlineTransport(endpoint: endpoint)
            .send(.unregisterDevice(installationID: id), bearer: bearer)
        guard case .ok = response else { throw OnlineClientError.unexpectedResponse }
        registered = nil
        retryAt = ContinuousClock.now
    }

    private func post(_ registration: Registration, environment: OnlinePushEnvironment) async {
        do {
            let id = try installationID(for: registration.endpoint)
            let request = OnlineRequest.registerDevice(installationID: id, token: registration.token, environment: environment)
            let response = try await OnlineTransport(endpoint: registration.endpoint)
                .send(request, bearer: registration.bearer)
            guard case .ok = response else { throw OnlineClientError.unexpectedResponse }
            registered = registration
            OnlineNotificationRouter.shared.registrationDidSucceed()
        } catch {
            retryAt = ContinuousClock.now.advanced(by: .seconds(20))
            OnlineNotificationRouter.shared.registrationDidFail()
        }
    }

    private func installationID(for endpoint: URL) throws -> UUID {
        let store = OnlineSecureStore(endpoint: endpoint)
        if let raw = try store.readString(OnlineStorageKey.installation) {
            guard let id = UUID(uuidString: raw) else { throw OnlineClientError.secureStorage }
            return id
        }
        let id = UUID()
        try store.write(Data(id.uuidString.utf8), key: OnlineStorageKey.installation)
        return id
    }

    private var pushEnvironment: OnlinePushEnvironment? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "EmpiresOnlinePushEnvironment") as? String
        return raw.flatMap(OnlinePushEnvironment.init(rawValue:))
    }
}
