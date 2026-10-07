import CatanEngine
import Foundation

enum Rendering {
    static func table(_ amounts: [Resource: Int]) -> String {
        Resource.allCases.compactMap { resource in
            amounts[resource].map { "\(resource)=\($0)" }
        }.joined(separator: ",")
    }

    static func canonical(_ move: GameMove) -> String {
        switch move {
        case .discard(let amounts): return "discard[\(table(amounts))]"
        case .bankTrade(let give, let get): return "bankTrade[\(table(give))->\(table(get))]"
        case .buyArmyCard(let paying): return "buyArmyCard[\(table(paying))]"
        case .proposeTrade(let offer): return "proposeTrade[p\(offer.from.index):\(table(offer.give))->\(table(offer.want))]"
        default: return "\(move)"
        }
    }

    static func fingerprint(_ trace: [String]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for move in trace {
            for byte in move.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = String(data: try encoder.encode(value), encoding: .utf8) else {
            preconditionFailure("JSONEncoder did not emit UTF-8")
        }
        return json
    }
}
