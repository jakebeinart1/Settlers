import XCTest
import UIKit

/// A replay once updated its caption and accessibility counts while keeping
/// opening fog and an empty map on screen. Compare pixels at real piece and
/// sea positions, so current model values cannot make that failure pass.
@MainActor
final class NavalReplayRenderingTests: XCTestCase {
    private static let minimumPieceDifference = 0.10
    private static let unchangedFrameTolerance = 0.02

    /// Inject hidden and known same-number production directly into the
    /// renderer. A producer-only fix cannot make this pixel counterexample
    /// pass, and the known ring proves the overbroad input was exercised.
    func testProductionRingsCannotRevealFoggedIslandPerimeters() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalVoyagePosition", "-qaNavalSeed=7501", "-qaNavalProductionHighlights"]
        app.launch()
        XCTAssertTrue(app.buttons["qa.production.show"].waitForExistence(timeout: 15))
        app.buttons["naval.overview"].tap()
        waitForWorldCamera(in: app)
        let known = productionProbes(in: app, role: "known")
        let hidden = productionProbes(in: app, role: "hidden")
        XCTAssertEqual(known.count, 6)
        XCTAssertEqual(hidden.count, 6)
        let knownNumber = try XCTUnwrap(known[0].value as? String)
        XCTAssertEqual(knownNumber, try XCTUnwrap(hidden[0].value as? String),
                       "The hidden counterexample must carry the known producing tile's actual number")
        let plain = try ReplayBoardPixels.capture(in: app)
        app.buttons["qa.production.show"].tap()
        let highlighted = try waitForProductionRing(in: app, opening: plain, known: known)
        let knownDifference = try perimeterDifference(at: known, from: plain, to: highlighted)
        let hiddenDifference = try perimeterDifference(at: hidden, from: plain, to: highlighted)
        XCTAssertGreaterThan(knownDifference, Self.minimumPieceDifference,
                             "The positive control did not paint a real producing ring")
        XCTAssertLessThan(hiddenDifference, Self.unchangedFrameTolerance,
                          "A white production perimeter disclosed terrain through opaque fog")
        XCTAssertEqual(plain.screenFrame, highlighted.screenFrame)
        retain("Voyages — hidden production has no painted perimeter", app: app)
    }

    private func waitForWorldCamera(in app: XCUIApplication) {
        let marker = app.otherElements["naval.camera.reference"]
        let fitted = NSPredicate { _, _ in (marker.value as? String)?.contains("zoom=1.000000") == true }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: fitted, object: nil)], timeout: 3), .completed)
    }

    private func productionProbes(in app: XCUIApplication, role: String) -> [XCUIElement] {
        (0..<6).map { app.otherElements["qa.production.\(role).\($0)"] }.filter(\.exists)
    }

    /// Accessibility can update before Canvas paints. Wait only for the
    /// known positive control; inspect hidden fog in that exact same frame.
    /// On timeout, return the last frame so the positive assertion still fails.
    private func waitForProductionRing(in app: XCUIApplication, opening: ReplayBoardPixels,
                                       known: [XCUIElement]) throws -> ReplayBoardPixels {
        let deadline = Date().addingTimeInterval(3)
        var pixels = try ReplayBoardPixels.capture(in: app)
        while Date() < deadline {
            if try perimeterDifference(at: known, from: opening, to: pixels) > Self.minimumPieceDifference { return pixels }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            pixels = try ReplayBoardPixels.capture(in: app)
        }
        return pixels
    }

    private func perimeterDifference(at probes: [XCUIElement], from plain: ReplayBoardPixels,
                                     to highlighted: ReplayBoardPixels) throws -> Double {
        try probes.map { element in
            try highlighted.difference(from: plain, at: CGPoint(x: element.frame.midX, y: element.frame.midY))
        }.max() ?? 0
    }

    func testScrubbingRestoresPaintedPiecesAndDiscoveredSea() throws {
        let app = openCompletedNavalReplay()
        app.buttons["replay.start"].tap()
        app.buttons["naval.overview"].tap()
        let opening = try ReplayBoardPixels.capture(in: app)
        app.buttons["replay.end"].tap()
        let sites = paintedSites(in: app)
        XCTAssertFalse(sites.buildings.isEmpty, "The finished match has no interior home buildings to inspect")
        XCTAssertGreaterThanOrEqual(sites.roads.count, 2)
        XCTAssertGreaterThanOrEqual(sites.sea.count, 3)
        let finished = try waitForPaintedFinal(in: app, opening: opening, sites: sites)
        assertPaintedFinal(finished, opening: opening, sites: sites)
        retain("Voyages — painted final replay", app: app)
        app.buttons["replay.start"].tap()
        let rewound = try ReplayBoardPixels.capture(in: app)
        XCTAssertLessThan(try rewound.difference(from: opening), Self.unchangedFrameTolerance,
                          "Rewinding left later pieces or discovery painted over the opening")
        app.buttons["replay.end"].tap()
        let repeated = try waitForPaintedFinal(in: app, opening: opening, sites: sites)
        assertPaintedFinal(repeated, opening: opening, sites: sites)
        XCTAssertLessThan(try repeated.difference(from: finished), Self.unchangedFrameTolerance,
                          "The same historical frame painted differently after a backward scrub")
    }

    private func openCompletedNavalReplay() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalExpert", "-qaPlayToEnd", "-qaNavalSeed=7501"]
        app.launch()
        let skip = app.buttons["game-over.cutscene.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 360), "The match must end in the victory cutscene")
        skip.tap()
        XCTAssertTrue(app.buttons["game-over.replay"].waitForExistence(timeout: 10))
        app.buttons["game-over.replay"].tap()
        XCTAssertTrue(app.buttons["replay.end"].waitForExistence(timeout: 30))
        return app
    }

    private struct PaintedSites {
        let buildings: [CGPoint]
        let roads: [CGPoint]
        let sea: [CGPoint]
    }

    private func paintedSites(in app: XCUIApplication) -> PaintedSites {
        let markers = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.inspect.")).allElementsBoundByIndex
        let homePieces = markers.filter { marker in
            let coordinates = marker.identifier.split(separator: ".").compactMap { part -> (Int, Int)? in
                let values = part.split(separator: "_").compactMap { Int($0) }
                return values.count == 2 ? (values[0], values[1]) : nil
            }
            return !coordinates.isEmpty && coordinates.allSatisfy { max(abs($0.0), abs($0.1), abs($0.0 + $0.1)) <= 2 }
        }
        func center(_ element: XCUIElement) -> CGPoint { CGPoint(x: element.frame.midX, y: element.frame.midY) }
        return PaintedSites(
            buildings: homePieces.filter { $0.identifier.hasPrefix("board.inspect.building.") }.map(center),
            roads: homePieces.filter { $0.identifier.hasPrefix("board.inspect.road.") }.map(center),
            sea: markers.filter { $0.identifier.hasPrefix("board.inspect.tile.") && $0.label == "Sea tile" }.prefix(12).map(center)
        )
    }

    private func waitForPaintedFinal(in app: XCUIApplication, opening: ReplayBoardPixels,
                                     sites: PaintedSites) throws -> ReplayBoardPixels {
        let deadline = Date().addingTimeInterval(3)
        var pixels = try ReplayBoardPixels.capture(in: app)
        while Date() < deadline {
            if try changed(at: sites.buildings, pixels: pixels, opening: opening) >= 1,
               try changed(at: sites.roads, pixels: pixels, opening: opening) >= 2,
               try sites.sea.filter({ try pixels.isSea(at: $0) }).count >= 3 { return pixels }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            pixels = try ReplayBoardPixels.capture(in: app)
        }
        return pixels
    }

    private func assertPaintedFinal(_ pixels: ReplayBoardPixels, opening: ReplayBoardPixels,
                                    sites: PaintedSites, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pixels.screenFrame, opening.screenFrame, "Scrubbing moved the board viewport", file: file, line: line)
        XCTAssertGreaterThanOrEqual(try changed(at: sites.buildings, pixels: pixels, opening: opening), 1,
                                   "Buildings exist in semantics but are absent from the painted map", file: file, line: line)
        XCTAssertGreaterThanOrEqual(try changed(at: sites.roads, pixels: pixels, opening: opening), 2,
                                   "Roads exist in semantics but are absent from the painted map", file: file, line: line)
        XCTAssertGreaterThanOrEqual(try sites.sea.filter { try pixels.isSea(at: $0) }.count, 3,
                                   "Discovered sea remains covered by opening fog", file: file, line: line)
    }

    private func changed(at points: [CGPoint], pixels: ReplayBoardPixels, opening: ReplayBoardPixels) throws -> Int {
        try points.filter { try pixels.difference(from: opening, at: $0) > Self.minimumPieceDifference }.count
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Normalise cropped screenshots into explicit RGBA. Device scale is derived
/// from the screenshot; position probes use the renderer's own screen markers.
@MainActor
private struct ReplayBoardPixels {
    let image: CGImage
    let screenFrame: CGRect
    let scale: CGFloat

    static func capture(in app: XCUIApplication) throws -> Self {
        let source = try XCTUnwrap(app.screenshot().image.cgImage)
        let frame = app.otherElements["board.surface"].frame
        let scale = CGFloat(source.width) / app.frame.width
        let rectangle = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                               width: frame.width * scale, height: frame.height * scale).integral
        return Self(image: try XCTUnwrap(source.cropping(to: rectangle)), screenFrame: frame, scale: scale)
    }

    func difference(from other: Self, at point: CGPoint? = nil) throws -> Double {
        let current = try pixels(at: point)
        let previous = try other.pixels(at: point)
        XCTAssertEqual(current.count, previous.count, "Pixel probes changed dimensions")
        let total = zip(current, previous).enumerated().reduce(0.0) { result, entry in
            entry.offset % 4 == 3 ? result : result + abs(Double(entry.element.0) - Double(entry.element.1))
        }
        return total / Double(max(1, current.count / 4 * 3)) / 255
    }

    func isSea(at point: CGPoint) throws -> Bool {
        let bytes = try pixels(at: point, radius: 0.65)
        let count = Double(max(1, bytes.count / 4)) * 255
        let red = stride(from: 0, to: bytes.count, by: 4).reduce(0.0) { $0 + Double(bytes[$1]) } / count
        let green = stride(from: 1, to: bytes.count, by: 4).reduce(0.0) { $0 + Double(bytes[$1]) } / count
        let blue = stride(from: 2, to: bytes.count, by: 4).reduce(0.0) { $0 + Double(bytes[$1]) } / count
        return red < 0.25 && green > red + 0.05 && blue > red + 0.12
    }

    private func pixels(at point: CGPoint?, radius: CGFloat = 2) throws -> [UInt8] {
        let sampled: CGImage
        if let point {
            let rect = CGRect(x: (point.x - screenFrame.minX - radius) * scale,
                              y: (point.y - screenFrame.minY - radius) * scale,
                              width: radius * 2 * scale, height: radius * 2 * scale).integral
            sampled = try XCTUnwrap(image.cropping(to: rect))
        } else {
            sampled = image
        }
        return try Self.rgba(of: sampled)
    }

    private static func rgba(of image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return bytes
    }
}
