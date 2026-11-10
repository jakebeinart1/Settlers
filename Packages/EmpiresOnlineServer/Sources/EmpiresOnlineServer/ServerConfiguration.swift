import Foundation
import Vapor

enum ServerConfigurationError: String, Error {
    case missingDataDirectory
    case invalidPort
    case invalidLoopbackSignupConfiguration
    case invalidProvisioningTokenFile
    case incompletePushConfiguration
    case invalidPushKey
}

struct ServerConfiguration {
    let dataDirectory: URL
    let hostname: String
    let port: Int
    let signup: OnlineSignupAdmission
    let push: PushConfiguration?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard let path = environment["EMPIRES_ONLINE_DATA_DIRECTORY"], path.hasPrefix("/") else {
            throw ServerConfigurationError.missingDataDirectory
        }
        guard let port = Int(environment["PORT"] ?? "8080"), (1...65_535).contains(port) else {
            throw ServerConfigurationError.invalidPort
        }
        dataDirectory = URL(fileURLWithPath: path, isDirectory: true)
        let bindAddress = environment["EMPIRES_ONLINE_BIND_ADDRESS"] ?? "127.0.0.1"
        hostname = bindAddress
        self.port = port
        signup = try OnlineSignupAdmission.load(environment, bindAddress: bindAddress)
        push = try PushConfiguration.load(environment)
    }
}

/// Only the HTTP boundary admits new accounts. The provisioning credential
/// is separate from player recovery keys and stays out of authority storage.
struct OnlineSignupAdmission: Sendable {
    static let closed = Self(allowsLoopback: false, provisioningDigest: nil)
    private static let tokenLength = 64

    private let allowsLoopback: Bool
    private let provisioningDigest: Data?

    static func load(_ environment: [String: String], bindAddress: String) throws -> Self {
        let localMode = environment["EMPIRES_ONLINE_ALLOW_LOOPBACK_SIGNUP"]
        if let localMode, localMode != "1" || !isLoopback(bindAddress) {
            throw ServerConfigurationError.invalidLoopbackSignupConfiguration
        }
        return Self(allowsLoopback: localMode != nil,
                    provisioningDigest: try loadDigest(from: environment["EMPIRES_ONLINE_PROVISIONING_TOKEN_FILE"]))
    }

    func permits(bearer: String?, directPeer: String?, listener: String?, forwarded: Bool) -> Bool {
        if let bearer {
            guard let provisioningDigest, Self.isProvisioningToken(bearer) else { return false }
            // Swift Crypto compares digest bytes in constant time.
            return SHA256.hash(data: Data(bearer.utf8)) == provisioningDigest
        }
        return allowsLoopback && !forwarded && Self.isLoopback(directPeer) && Self.isLoopback(listener)
    }

    private static func loadDigest(from path: String?) throws -> Data? {
        guard let path else { return nil }
        guard path.hasPrefix("/"), let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ServerConfigurationError.invalidProvisioningTokenFile
        }
        let token = content.trimmingCharacters(in: .newlines)
        guard isProvisioningToken(token) else { throw ServerConfigurationError.invalidProvisioningTokenFile }
        return Data(SHA256.hash(data: Data(token.utf8)))
    }

    private static func isProvisioningToken(_ token: String) -> Bool {
        token.utf8.count == tokenLength && token.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    private static func isLoopback(_ address: String?) -> Bool {
        address == "127.0.0.1" || address == "::1"
    }
}

struct PushConfiguration {
    let keyID: String
    let teamID: String
    let topic: String
    let keyFile: URL
    let isProduction: Bool

    static func load(_ environment: [String: String]) throws -> Self? {
        let keys = ["EMPIRES_APNS_KEY_ID", "EMPIRES_APNS_TEAM_ID", "EMPIRES_APNS_TOPIC",
                    "EMPIRES_APNS_KEY_FILE", "EMPIRES_APNS_ENVIRONMENT"]
        guard keys.contains(where: { environment[$0] != nil }) else { return nil }
        guard let keyID = environment["EMPIRES_APNS_KEY_ID"], !keyID.isEmpty,
              let teamID = environment["EMPIRES_APNS_TEAM_ID"], !teamID.isEmpty,
              let topic = environment["EMPIRES_APNS_TOPIC"], !topic.isEmpty,
              let keyFile = environment["EMPIRES_APNS_KEY_FILE"], keyFile.hasPrefix("/"),
              let mode = environment["EMPIRES_APNS_ENVIRONMENT"],
              mode == "production" || mode == "development" else {
            throw ServerConfigurationError.incompletePushConfiguration
        }
        return Self(keyID: keyID, teamID: teamID, topic: topic,
                    keyFile: URL(fileURLWithPath: keyFile), isProduction: mode == "production")
    }
}
