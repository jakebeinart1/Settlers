import Foundation
import Testing
@testable import CatanEngine

struct NavalDeterminismTests {
    @Test func mapFingerprintsRemainStableAcrossTestProcesses() {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for family in NavalMapFamily.allCases {
            for seed in [0, 1, 7, 42, 999] {
                let state = Naval.newGame(seed: UInt64(seed), options: NavalOptions(mapFamily: family))
                for tile in state.board.tiles {
                    mix("\(tile.coordinate.q),\(tile.coordinate.r):\(tile.kind):\(tile.numberToken ?? 0);", into: &hash)
                }
                for port in state.board.ports {
                    for vertex in [port.vertexA, port.vertexB] {
                        for hex in vertex.touchingTiles { mix("\(hex.q),\(hex.r);", into: &hash) }
                    }
                    mix("\(port.kind);", into: &hash)
                }
                for hex in state.naval!.islandByHex.keys.sorted() { mix("\(hex.q),\(hex.r):\(state.naval!.islandByHex[hex]!);", into: &hash) }
                for card in state.devCardDeck { mix("\(card);", into: &hash) }
            }
        }
        print("NAVAL DETERMINISM FINGERPRINT \(hash)")
        #expect(hash == 9_763_491_777_621_528_290)
    }

    private func mix(_ value: String, into hash: inout UInt64) {
        for byte in value.utf8 { hash ^= UInt64(byte); hash = hash &* 1_099_511_628_211 }
    }
}
