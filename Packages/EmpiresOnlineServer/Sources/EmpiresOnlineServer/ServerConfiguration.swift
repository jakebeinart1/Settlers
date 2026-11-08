import Foundation

enum ServerConfigurationError: String, Error {
    case missingDataDirectory
    case invalidPort
    case incompletePushConfiguration
    case invalidPushKey
}

struct ServerConfiguration {
    let dataDirectory: URL
    let hostname: String
    let port: Int
    let push: PushConfiguration?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard let path = environment["EMPIRES_ONLINE_DATA_DIRECTORY"], path.hasPrefix("/") else {
            throw ServerConfigurationError.missingDataDirectory
        }
        guard let port = Int(environment["PORT"] ?? "8080"), (1...65_535).contains(port) else {
            throw ServerConfigurationError.invalidPort
        }
        dataDirectory = URL(fileURLWithPath: path, isDirectory: true)
        hostname = environment["EMPIRES_ONLINE_BIND_ADDRESS"] ?? "127.0.0.1"
        self.port = port
        push = try PushConfiguration.load(environment)
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
