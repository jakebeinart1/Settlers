import XCTest

/// Known harbors must stay public without stealing coastal placement touches.
/// Port trading is exercised through the actual editor, receipt and saved match.
@MainActor
final class NativeHarborFlowTests: XCTestCase {
    private static let timeout: TimeInterval = 5
    private static let resources = ["brick", "lumber", "ore", "grain", "wool"]

    func testFogKeepsFourHomeHarborsAndTheirMarkersDoNotInterceptCoastalSetup() throws {
        let app = launch()
        assertHarbors(count: 4, generic: 2, in: app)
        let labels = harborMarkers(in: app).map(\.label)
        XCTAssertTrue(labels.contains("Two grain for one port"))
        XCTAssertTrue(labels.contains("Two wool for one port"))
        app.buttons["naval.overview"].tap()
        assertHarbors(count: 4, generic: 2, in: app)
        retain("Naval harbors — four surveyed home ports, overseas ports fogged", app: app)
        app.buttons["naval.home"].tap()
        let coastal = try coastalCornerNearestToKnownHarbor(in: app)
        coastal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(coastal.value as? String, "Selected", "A read-only harbor marker intercepted the real settlement target")
        XCTAssertTrue(app.buttons["board-decision.confirm"].isEnabled)
        retain("Naval harbors — coastal setup remains physically selectable", app: app)
        app.buttons["board-decision.confirm"].tap()
        let roads = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.edge."))
        XCTAssertTrue(roads.firstMatch.waitForExistence(timeout: Self.timeout), "Coastal settlement did not actually commit")
    }

    func testFogOffExposesAllNineHarborsWithTheirActualRates() {
        let app = launch(extra: ["-qaNavalNoFog"])
        app.buttons["naval.overview"].tap()
        assertHarbors(count: 9, generic: 4, in: app)
        retain("Naval harbors — nine public ports with fog disabled", app: app)
    }

    func testOwnedGenericHarborTradesThreeLumberForOneOreOnlyAfterCommitAndResumes() throws {
        try assertBankJourney(flag: "-qaNavalGenericPortPosition", give: "lumber", rate: 3)
    }

    func testOwnedResourceHarborTradesTwoGrainForOneOreOnlyAfterCommitAndResumes() throws {
        try assertBankJourney(flag: "-qaNavalResourcePortPosition", give: "grain", rate: 2)
    }

    private func assertBankJourney(flag: String, give: String, rate: Int) throws {
        let app = launch(extra: [flag])
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: Self.timeout))
        let hand = try humanResources(in: app)
        let discoveries = app.buttons["naval.overview"].value as? String
        let bank = try assertCancelledPreview(give: give, rate: rate, hand: hand, in: app)
        XCTAssertEqual(app.buttons["naval.overview"].value as? String, discoveries)
        openBank(in: app)
        XCTAssertEqual(try bankStock(in: app), bank, "Cancelling the preview changed the bank")
        composeOneBundle(give: give, rate: rate, hand: hand, in: app)
        app.buttons["Trade with Bank"].tap()
        assertReceipt(give: give, rate: rate, in: app)
        retain("Naval harbor — committed \(rate):1 receipt", app: app)
        app.buttons["Close trade"].tap()
        let expectedHand = exchanged(hand, give: give, rate: rate, isBank: false)
        let expectedBank = exchanged(bank, give: give, rate: rate, isBank: true)
        try assertCommittedExchange(hand: expectedHand, bank: expectedBank, give: give, rate: rate, in: app)
        coldResume(in: app)
        try assertCommittedExchange(hand: expectedHand, bank: expectedBank, give: give, rate: rate, in: app)
        XCTAssertEqual(app.buttons["naval.overview"].value as? String, discoveries)
        retain("Naval harbor — \(rate):1 exchange persists through cold resume", app: app)
    }

    private func assertCancelledPreview(give: String, rate: Int, hand: [String: Int],
                                        in app: XCUIApplication) throws -> [String: Int] {
        openBank(in: app)
        let bank = try bankStock(in: app)
        composeOneBundle(give: give, rate: rate, hand: hand, in: app)
        XCTAssertEqual(try bankStock(in: app), bank, "The preview changed the bank")
        retain("Naval harbor — \(rate):1 preview before any exchange", app: app)
        app.buttons["Close"].tap()
        XCTAssertEqual(try humanResources(in: app), hand, "Cancelling the harbor trade spent cards")
        return bank
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalSeed=7501", "-qaNavalFamily=archipelago"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: Self.timeout))
        return app
    }

    private func harborMarkers(in app: XCUIApplication) -> [XCUIElement] {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "naval.harbor.")).allElementsBoundByIndex
    }

    private func assertHarbors(count: Int, generic: Int, in app: XCUIApplication) {
        let query = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "naval.harbor."))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: Self.timeout), "The public map has no harbor semantics")
        let markers = query.allElementsBoundByIndex
        XCTAssertEqual(markers.count, count, "Known home harbors and fogged overseas harbors were confused")
        XCTAssertEqual(markers.filter { $0.value as? String == "3:1" }.count, generic)
        XCTAssertEqual(markers.filter { $0.value as? String == "2:1" }.count, count - generic)
        XCTAssertTrue(markers.allSatisfy { $0.label.hasSuffix("for one port") })
    }

    private func coastalCornerNearestToKnownHarbor(in app: XCUIApplication) throws -> XCUIElement {
        let harbor = try XCTUnwrap(harborMarkers(in: app).first)
        let corners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.vertex."))
        let coastal = corners.allElementsBoundByIndex.filter { $0.isHittable && isHomeCoast($0.identifier) }
        return try XCTUnwrap(coastal.min { distanceSquared($0.frame, harbor.frame) < distanceSquared($1.frame, harbor.frame) })
    }

    private func isHomeCoast(_ identifier: String) -> Bool {
        let radii = identifier.split(separator: ".").compactMap { part -> Int? in
            let values = part.split(separator: "_").compactMap { Int($0) }
            guard values.count == 2 else { return nil }
            return max(abs(values[0]), abs(values[1]), abs(values[0] + values[1]))
        }
        return radii.count == 3 && radii.contains(3) && radii.contains(where: { $0 <= 2 })
    }

    private func distanceSquared(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let dx = first.midX - second.midX
        let dy = first.midY - second.midY
        return dx * dx + dy * dy
    }

    private func openBank(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: Self.timeout))
        app.buttons["Trade"].tap()
        XCTAssertTrue(app.buttons["Bank"].waitForExistence(timeout: Self.timeout))
        app.buttons["Bank"].tap()
        XCTAssertTrue(app.buttons["trade.bank.give.lumber"].waitForExistence(timeout: Self.timeout))
    }

    private func composeOneBundle(give: String, rate: Int, hand: [String: Int], in app: XCUIApplication) {
        XCTAssertEqual(app.staticTexts["trade.bank.rate.\(give)"].label, "\(rate):1")
        let giveButton = app.buttons["trade.bank.give.\(give)"]
        let getButton = app.buttons["trade.bank.get.ore"]
        XCTAssertEqual(giveButton.value as? String, "0")
        XCTAssertEqual(getButton.value as? String, "0")
        XCTAssertFalse(app.buttons["Trade with Bank"].isEnabled)
        giveButton.tap()
        XCTAssertEqual(giveButton.value as? String, "\(rate)", "One give tap must add exactly the owned harbor bundle")
        getButton.tap()
        XCTAssertEqual(getButton.value as? String, "1")
        XCTAssertEqual(app.staticTexts["trade.inventory.\(give)"].label, "\(hand[give, default: 0] - rate) left")
        XCTAssertTrue(app.buttons["Trade with Bank"].isEnabled && app.buttons["Trade with Bank"].isHittable)
    }

    private func assertReceipt(give: String, rate: Int, in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Trade complete"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["Traded with the Bank. Your hand is updated."].exists)
        XCTAssertTrue(app.staticTexts["\(rate) \(give.capitalized)"].exists)
        XCTAssertTrue(app.staticTexts["1 Ore"].exists)
        XCTAssertFalse(app.buttons["Trade with Bank"].exists, "A committed receipt must not retain a second commit button")
        XCTAssertTrue(app.buttons["Close trade"].isHittable)
    }

    private func assertCommittedExchange(hand: [String: Int], bank: [String: Int], give: String,
                                         rate: Int, in app: XCUIApplication) throws {
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(try humanResources(in: app), hand, "The committed harbor exchange changed the wrong cards")
        openBank(in: app)
        XCTAssertEqual(try bankStock(in: app), bank, "The committed exchange must conserve the bank and hand")
        XCTAssertEqual(app.staticTexts["trade.bank.rate.\(give)"].label, "\(rate):1", "The owned harbor rate did not survive")
        XCTAssertFalse(app.staticTexts["Trade complete"].exists, "Reopening must not reuse an old receipt")
        XCTAssertEqual(app.buttons["trade.bank.give.\(give)"].value as? String, "0")
        XCTAssertEqual(app.buttons["trade.bank.get.ore"].value as? String, "0")
        app.buttons["Close"].tap()
    }

    private func humanResources(in app: XCUIApplication) throws -> [String: Int] {
        try Dictionary(uniqueKeysWithValues: Self.resources.map { resource in
            let value = try XCTUnwrap(app.otherElements["human-resource.\(resource)"].value as? String)
            return (resource, try XCTUnwrap(Int(value)))
        })
    }

    private func bankStock(in app: XCUIApplication) throws -> [String: Int] {
        try Dictionary(uniqueKeysWithValues: Self.resources.map { resource in
            let stock = app.staticTexts["trade.bank.stock.\(resource)"]
            XCTAssertTrue(stock.exists, "Bank stock evidence is missing for \(resource)")
            let counts = stock.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            XCTAssertEqual(counts.count, 1, "Bank stock has ambiguous quantities: \(stock.label)")
            return (resource, try XCTUnwrap(counts.first))
        })
    }

    private func exchanged(_ counts: [String: Int], give: String, rate: Int, isBank: Bool) -> [String: Int] {
        var result = counts
        result[give, default: 0] += isBank ? rate : -rate
        result["ore", default: 0] += isBank ? -1 : 1
        return result
    }

    private func coldResume(in app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: Self.timeout))
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: Self.timeout))
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
