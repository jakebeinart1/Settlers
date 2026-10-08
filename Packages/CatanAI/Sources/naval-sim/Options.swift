import CatanAI
import CatanEngine
import Foundation

struct Options {
    var games = 1
    var seed: UInt64 = 700_000
    var players = 4
    var family = NavalMapFamily.archipelago
    var fog = true
    var wild = true
    var shipStealing = false
    var brainRevision: NavalPolicy.Revision?
    var seats: [String] = []
    var buildID = "working-tree"
    var arm = "diagnostic"
    var focalChair = 0
    var traceDirectory: String?
    var auditDirectory: String?

    static func parse(_ arguments: [String]) -> Options {
        var result = Options()
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            guard index + 1 < arguments.count else { fail("Missing value for \(flag)") }
            let value = arguments[index + 1]
            switch flag {
            case "--games": result.games = Int(value) ?? 0
            case "--seed": guard let seed = UInt64(value) else { fail("Invalid seed") }; result.seed = seed
            case "--players": result.players = Int(value) ?? 0
            case "--family": guard let family = NavalMapFamily(rawValue: value) else { fail("Unknown family") }; result.family = family
            case "--fog": result.fog = boolean(value)
            case "--wild": result.wild = boolean(value)
            case "--ship-stealing": result.shipStealing = boolean(value)
            case "--brain-revision":
                guard let revision = NavalPolicy.Revision(rawValue: value) else { fail("Unknown naval brain revision") }
                result.brainRevision = revision
            case "--seats": result.seats = value.split(separator: ",").map {
                guard ["traditional", "expert", "land-control"].contains(String($0)) else { fail("Unknown policy \($0)") }
                return String($0)
            }
            case "--build-id": result.buildID = value
            case "--arm": result.arm = value
            case "--focal-chair": result.focalChair = Int(value) ?? -1
            case "--trace-directory": result.traceDirectory = value
            case "--audit-directory": result.auditDirectory = value
            default: fail("Unknown option \(flag)")
            }
            index += 2
        }
        guard (3...4).contains(result.players), result.games > 0,
              (0..<result.players).contains(result.focalChair),
              result.seed <= UInt64.max - UInt64(result.games - 1) else { fail("Invalid games, players, chair, or seed range") }
        if result.seats.isEmpty { result.seats = Array(repeating: "traditional", count: result.players) }
        guard result.seats.count == result.players else { fail("Roster must match player count") }
        return result
    }

    static func boolean(_ value: String) -> Bool {
        switch value {
        case "on": true
        case "off": false
        default: fail("Toggle must be on or off")
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("naval-sim: \(message)\n").utf8))
        exit(2)
    }

    func policy(at index: Int, in state: GameState) -> any Policy {
        switch seats[index] {
        case "traditional": NavalPolicy(tier: .traditional, revision: revision(in: state))
        case "expert": NavalPolicy(tier: .expert, revision: revision(in: state))
        case "land-control": NavalLandControl()
        default: Self.fail("Unknown policy")
        }
    }

    func revision(in state: GameState) -> NavalPolicy.Revision {
        brainRevision ?? .forGame(state)
    }
}
