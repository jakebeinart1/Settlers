import Foundation
import Security
import EmpiresOnline

struct OnlineTransport: Sendable {
    let endpoint: URL
    private let session = URLSession(configuration: .ephemeral, delegate: OnlineNoRedirects(), delegateQueue: nil)

    static var configuredEndpoint: URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-empiresOnlineServer"),
           let url = arguments.dropFirst(flag + 1).first.flatMap(URL.init(string:)),
           ["127.0.0.1", "localhost"].contains(url.host ?? ""), url.scheme == "http",
           validOrigin(url) {
            return url
        }
        #endif
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "EmpiresOnlineServerURL") as? String,
              let url = URL(string: raw), url.scheme == "https", validOrigin(url) else { return nil }
        return url
    }

    private static func validOrigin(_ url: URL) -> Bool {
        url.host != nil && url.user == nil && url.password == nil
            && url.query == nil && url.fragment == nil
    }

    func send(_ value: OnlineRequest, bearer: String?) async throws -> OnlineResponse {
        var request = URLRequest(url: endpoint.appendingPathComponent("v1").appendingPathComponent("online"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(value)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnlineClientError.unexpectedResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OnlineClientError.rejected(http.statusCode, try? decoder.decode(OnlineError.self, from: data))
        }
        return try decoder.decode(OnlineResponse.self, from: data)
    }
}

/// A configured HTTPS origin owns the credential. Redirects cannot forward it
/// to another host or send a command to a different endpoint.
private final class OnlineNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum OnlineClientError: LocalizedError {
    case unavailable
    case unexpectedResponse
    case rejected(Int, OnlineError?)
    case secureStorage

    var errorDescription: String? {
        switch self {
        case .unavailable: "Online play is unavailable in this build."
        case .unexpectedResponse: "Empires received an unexpected reply."
        case .secureStorage: "Empires could not access its secure storage."
        case .rejected(400, .some(.bankStockUnavailable)): OnlineError.bankStockUnavailable.errorDescription
        case .rejected(401, _): "That recovery key or session is no longer valid."
        case .rejected(403, _): "You do not have access to that game or action."
        case .rejected(404, _): "That room or game is unavailable."
        case .rejected(409, _): "The game changed. Review its current state and try again."
        case .rejected(429, _): "Too many requests. Try again in a moment."
        case .rejected(let code, _) where code >= 500: "The match server is temporarily unavailable."
        case .rejected: "The match server could not accept that action."
        }
    }

    var definitelyRejected: Bool {
        if case .rejected(let code, _) = self { return (400 ..< 500).contains(code) && code != 408 && code != 429 }
        return false
    }

    var matchUnavailable: Bool {
        if case .rejected(let code, _) = self { return code == 403 || code == 404 }
        return false
    }
}

struct OnlineSecureStore {
    let endpoint: URL

    func read(_ key: String) throws -> Data? {
        var query = attributes(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw OnlineClientError.secureStorage }
        return data
    }

    func write(_ value: Data, key: String) throws {
        var query = attributes(for: key)
        let updates = [kSecValueData as String: value]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw OnlineClientError.secureStorage }
        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw OnlineClientError.secureStorage
        }
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(attributes(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OnlineClientError.secureStorage
        }
    }

    func readString(_ key: String) throws -> String? {
        guard let data = try read(key) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw OnlineClientError.secureStorage }
        return value
    }

    private func attributes(for key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Empires.Online.\(endpoint.absoluteString)\(testNamespace)",
         kSecAttrAccount as String: key]
    }

    private var testNamespace: String {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing"), endpoint.scheme == "http",
           let index = arguments.firstIndex(of: "-empiresOnlineTestSession"),
           let raw = arguments.dropFirst(index + 1).first,
           let id = UUID(uuidString: raw) {
            return ".test.\(id)"
        }
        #endif
        return ""
    }
}

enum OnlineStorageKey {
    static let bearer = "bearer"
    static let submission = "pending-move"
    static let installation = "push-installation"
}
