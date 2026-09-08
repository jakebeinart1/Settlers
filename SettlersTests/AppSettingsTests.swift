import Foundation
import SwiftUI
import Testing
import UIKit
@testable import CatanEngine
@testable import Settlers

@Suite struct CivilizationPreferenceTests {
    @Test func legacyThreeCivilizationPoolIsExpandedForFourRandomSeats() throws {
        let suiteName = "CivilizationPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = LegacyCivilizationSettings(
            yourCivilization: .medieval,
            includedBotCivilizations: [.greece, .rome, .japan]
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: "civilizationSettings")

        let loaded = CivilizationSettingsStore(defaults: defaults).load()

        #expect(loaded.eligibleRandomCivilizations.count >= 4)
        #expect(loaded.eligibleRandomCivilizations.isSuperset(of: legacy.includedBotCivilizations))
    }

    @Test func preferredCivilizationAndRandomPoolAreIndependent() {
        var settings = CivilizationSettings.default
        let pool = settings.eligibleRandomCivilizations

        settings.yourCivilization = .norse

        #expect(settings.eligibleRandomCivilizations == pool)
    }

    @MainActor
    @Test func allRandomSeatsDrawOnlyFromTheSelectedPool() {
        let pool: Set<Civilization> = [.greece, .rome, .japan, .norse]
        let resolved = GameViewModel.resolveRandomCivilizations(
            configured: Array(repeating: nil, count: 4),
            eligiblePool: pool
        )

        #expect(Set(resolved) == pool)
        #expect(resolved.count == 4)
    }
}

@MainActor
@Suite struct CivilizationIdentityColorTests {
    private static let swatchSize = CGSize(width: 120, height: 90)
    /// A painted texture may shift luminance substantially, but a chromatic
    /// distance this small keeps it visibly in the source material's family.
    private static let maximumPaintedChromaticDistance = 0.11
    /// Neutral source art should have near-equal channels; rendering gets a
    /// little extra allowance for texture antialiasing and color conversion.
    private static let maximumSourceNeutralSpread = 0.03
    private static let maximumRenderedNeutralSpread = 0.08

    @Test func paintedCardTextureKeepsEachCivilizationsColorFamily() throws {
        for civilization in Civilization.allCases {
            let accent = Self.rgb(of: civilization.accentColor)
            let card = try Self.renderedMeanRGB(
                TintedTextureBackground(tint: civilization.cardBackgroundColor(active: false))
            )

            #expect(
                Self.chromaticDistance(accent, card) < Self.maximumPaintedChromaticDistance,
                "\(civilization.displayName) changed color family: accent \(accent), painted card \(card)"
            )
        }
    }

    @Test func columbiaStaysNeutralInsteadOfInventingAHue() throws {
        let accent = Self.rgb(of: Civilization.columbia.accentColor)
        let card = try Self.renderedMeanRGB(
            TintedTextureBackground(tint: Civilization.columbia.cardBackgroundColor(active: false))
        )

        #expect(Self.channelSpread(accent) < Self.maximumSourceNeutralSpread)
        #expect(
            Self.channelSpread(card) < Self.maximumRenderedNeutralSpread,
            "Columbia's white identity became \(card)"
        )
    }

    private static func renderedMeanRGB<V: View>(_ view: V) throws -> SIMD3<Double> {
        let renderer = ImageRenderer(content: view.frame(width: swatchSize.width, height: swatchSize.height))
        renderer.scale = 1
        return try meanRGB(of: #require(renderer.cgImage))
    }

    private static func meanRGB(of image: CGImage) -> SIMD3<Double> {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        }
        let sums = stride(from: 0, to: bytes.count, by: 4).reduce(into: SIMD3<Double>(repeating: 0)) {
            $0 += SIMD3(Double(bytes[$1]), Double(bytes[$1 + 1]), Double(bytes[$1 + 2]))
        }
        return sums / Double(width * height * 255)
    }

    private static func rgb(of color: Color) -> SIMD3<Double> {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        precondition(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return SIMD3(Double(red), Double(green), Double(blue))
    }

    private static func chromaticDistance(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let difference = lhs / lhs.sum - rhs / rhs.sum
        return sqrt(difference.x * difference.x + difference.y * difference.y + difference.z * difference.z)
    }

    private static func channelSpread(_ color: SIMD3<Double>) -> Double {
        color.max() - color.min()
    }
}

private extension SIMD3 where Scalar == Double {
    var sum: Double { x + y + z }
}

private struct LegacyCivilizationSettings: Codable {
    let yourCivilization: Civilization
    let includedBotCivilizations: Set<Civilization>
}
