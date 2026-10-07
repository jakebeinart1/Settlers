import Testing
import UIKit
import CatanEngine
@testable import Settlers

/// Missing catalog names or an opaque generated backdrop survive a successful
/// build. Check the actual app-bundle images rather than the reference folder.
@MainActor
@Suite struct NavalShipArtworkTests {
    @Test(arguments: Civilization.allCases)
    func everyControllerHasACompleteTransparentRuntimeVessel(civilization: Civilization) throws {
        let image = try #require(UIImage(named: civilization.shipAssetName))
        let raster = try #require(image.cgImage)
        #expect(raster.width >= 1_000 && raster.height >= 1_000)
        let alpha = try alphaBytes(of: raster)
        let visible = alpha.filter { $0 >= 128 }.count
        let clear = alpha.filter { $0 == 0 }.count
        #expect(visible > alpha.count / 4, "The vessel silhouette is missing")
        #expect(clear > alpha.count / 5, "A solid backdrop would obscure the sea")
    }

    @Test func allEightControllerStylesAreDistinctRuntimeImages() throws {
        let names = Civilization.allCases.map(\.shipAssetName)
        #expect(Set(names).count == 8)
        let pixels = try names.map { try #require(UIImage(named: $0)?.pngData()) }
        #expect(Set(pixels).count == 8)
    }

    @Test func scarcityHandPreservesRealSetupAndEveryResourceSupply() throws {
        var state = try NavalQAFixture.make(.voyage)
        NavalQAFixture.replaceHand([.lumber: 1, .wool: 10], for: state.players[0].id, in: &state)
        #expect(state.players.allSatisfy { $0.settlements.count == 2 && $0.roads.count == 2 })
        let expected: [Resource: Int] = [.lumber: 1, .wool: 10]
        #expect(Resource.allCases.allSatisfy {
            state.players[0].resources[$0, default: 0] == expected[$0, default: 0]
        })
        for resource in Resource.allCases {
            let total = state.bank[resource, default: 0] + state.players.reduce(0) {
                $0 + $1.resources[resource, default: 0]
            }
            #expect(total == 38)
        }
        try GameSession(state: state, policies: [:], policySeed: 0).checkpoint.validate()
    }

    private func alphaBytes(of image: CGImage) throws -> [UInt8] {
        let stride = image.width * 4
        var pixels = [UInt8](repeating: 0, count: stride * image.height)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Swift.stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
