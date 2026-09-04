import Testing
import Foundation
@testable import CatanEngine

/// Pins that an enumerated offer's id actually identifies it.
///
/// This is not a hash-quality nicety. `.respondToTrade` names an offer by id,
/// so two pending offers sharing one means the player accepts a trade they did
/// not pick - and `ActionSpace` and `StateEncoding` both address offers, so a
/// collision corrupts everything built on top.
///
/// The first implementation collided badly: of the 320 offers the enumeration
/// can produce, only 164 ids were distinct, and `wool1>lumber1` shared an id
/// with `wool1>lumber2`. It sampled the top byte of an FNV-1a state right after
/// XORing each input byte into the low bits, so the trailing characters of the
/// descriptor - which is where the want quantity lives - barely reached the
/// digest at all.

/// Every offer the enumeration can produce, which is the set that actually
/// ends up in `pendingTradeOffers` together.
private func everyEnumeratedOffer() -> [(offer: TradeOffer, label: String)] {
    var result: [(TradeOffer, String)] = []
    for seat in 0..<4 {
        for give in Resource.allCases {
            for giveCount in 1...RulesEngine.maxGenerousGiveQuantity {
                for want in Resource.allCases where want != give {
                    for wantCount in 1...RulesEngine.maxEnumeratedTradeQuantity {
                        let offer = TradeOffer.enumerated(
                            from: PlayerID(index: seat),
                            give: [give: giveCount], want: [want: wantCount])
                        result.append((offer, "P\(seat) \(give.rawValue)x\(giveCount)>\(want.rawValue)x\(wantCount)"))
                    }
                }
            }
        }
    }
    return result
}

@Test func distinctOffersGetDistinctIdentifiers() {
    let all = everyEnumeratedOffer()
    var byID: [UUID: [String]] = [:]
    for (offer, label) in all { byID[offer.id, default: []].append(label) }

    let collisions = byID.values.filter { $0.count > 1 }.sorted { $0[0] < $1[0] }
    let detail = collisions.first.map { "e.g. \($0.sorted().joined(separator: " and "))" } ?? ""
    #expect(collisions.isEmpty,
            "\(collisions.count) groups of offers share an id, so accepting one accepts another; \(detail)")
    #expect(byID.count == all.count, "\(byID.count) distinct ids for \(all.count) distinct offers")
}

@Test func theIdentifierDependsOnEveryPartOfTheOffer() {
    // Each of the four fields, changed one at a time. The original digest was
    // blind to the last of them, because the descriptor ends with it.
    let base = TradeOffer.enumerated(from: PlayerID(index: 1), give: [.wool: 1], want: [.lumber: 1])
    let variants: [(String, TradeOffer)] = [
        ("proposer", .enumerated(from: PlayerID(index: 2), give: [.wool: 1], want: [.lumber: 1])),
        ("give kind", .enumerated(from: PlayerID(index: 1), give: [.ore: 1], want: [.lumber: 1])),
        ("give count", .enumerated(from: PlayerID(index: 1), give: [.wool: 2], want: [.lumber: 1])),
        ("want kind", .enumerated(from: PlayerID(index: 1), give: [.wool: 1], want: [.grain: 1])),
        ("want count", .enumerated(from: PlayerID(index: 1), give: [.wool: 1], want: [.lumber: 2])),
    ]
    for (field, variant) in variants {
        #expect(variant.id != base.id, "changing the \(field) must change the id")
    }
}

@Test func theSameOfferAlwaysCarriesTheSameIdentifier() {
    // The property `legalMoves` purity rests on: enumerate twice, get equal
    // offers. Before ids were content-derived at all, `legalMoves` minted a
    // fresh UUID per call and was not a pure function of the state.
    let first = TradeOffer.enumerated(from: PlayerID(index: 3), give: [.grain: 2], want: [.brick: 1])
    let second = TradeOffer.enumerated(from: PlayerID(index: 3), give: [.grain: 2], want: [.brick: 1])
    #expect(first.id == second.id)
}

@Test func identifiersDoNotShareLongPrefixes() {
    // The old digest kept one byte per descriptor character and then took the
    // last sixteen, so descriptors of different lengths produced shifted copies
    // of one byte sequence - handles that were visible rotations of each other
    // (0c622f, 0c62bf, 622fab). Anything that abbreviates an id for display
    // needs this not to be true.
    let ids = everyEnumeratedOffer().map { $0.offer.id.uuidString.replacingOccurrences(of: "-", with: "") }
    let prefixes = Set(ids.map { $0.prefix(6) })
    #expect(prefixes.count == ids.count,
            "\(ids.count - prefixes.count) offers share a 6-character id prefix")
}
