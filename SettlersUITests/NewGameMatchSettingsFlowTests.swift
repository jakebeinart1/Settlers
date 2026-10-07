import XCTest

/// Measure the real controls and tap the shipping help buttons. A wider
/// painted row is only useful when its touch regions and descriptions agree.
@MainActor
final class NewGameMatchSettingsFlowTests: XCTestCase {
    /// CGRect may report a 44pt target as 43.99999999999994 after conversion.
    private static let framePrecision: CGFloat = 0.001
    func testSettingsSelectorsShareWiderAlignedColumns() {
        let app = launch()
        let choices = [app.buttons["new-game.mode.classic"], app.buttons["new-game.rules.standard"],
                       app.buttons["new-game.board.standard"], app.buttons["new-game.difficulty.classic"],
                       app.buttons["new-game.seating.shown"]]
        let topics = ["Game Mode", "Rules", "Board", "AI Opponents", "Turn Order"]
        let expectedStart = app.frame.minX + 20 + 114 + 8
        for (choice, topic) in zip(choices, topics) {
            XCTAssertTrue(choice.isHittable)
            XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
            let heading = app.buttons["About \(topic)"]
            XCTAssertGreaterThanOrEqual(heading.frame.height + Self.framePrecision, 44)
            XCTAssertFalse(heading.frame.intersects(choice.frame))
            XCTAssertEqual(choice.frame.minX, expectedStart, accuracy: 1)
        }
        let rules = ["standard", "conquest", "naval"].map { app.buttons["new-game.rules.\($0)"] }
        for choice in rules { XCTAssertEqual(choice.frame.width, rules[0].frame.width, accuracy: 1) }
        retain("Match Settings — wider aligned selectors", app: app)
    }

    func testRulesHelpExplainsEveryOptionWithoutMovingFooterOrChangingSelection() {
        let app = launch()
        let start = app.buttons["new-game.start"].frame
        let cancel = app.buttons["new-game.cancel"].frame
        let standard = app.buttons["new-game.rules.standard"]
        app.buttons["About Rules"].tap()
        let help = app.otherElements["new-game.help.rules"]
        XCTAssertTrue(help.waitForExistence(timeout: 3))
        for title in ["Standard", "Conquest", "Naval"] { XCTAssertTrue(help.staticTexts[title].exists) }
        XCTAssertTrue(help.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 wood")).firstMatch.exists)
        let navalDescription = help.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 wood")).firstMatch
        XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(navalDescription.frame),
                      "Opening Rules help must bring the complete Naval explanation into view")
        XCTAssertTrue(standard.isSelected)
        XCTAssertEqual(app.buttons["new-game.start"].frame, start)
        XCTAssertEqual(app.buttons["new-game.cancel"].frame, cancel)
        retain("Match Settings — Standard Conquest Naval explained", app: app)
        app.buttons["About Rules"].tap()
        XCTAssertFalse(help.exists)
        for _ in 0..<3 where !app.buttons["About Game Mode"].isHittable { app.scrollViews.firstMatch.swipeDown() }
        app.buttons["About Game Mode"].tap()
        XCTAssertTrue(app.otherElements["new-game.help.mode"].waitForExistence(timeout: 3))
        XCTAssertFalse(help.exists)
        XCTAssertTrue(standard.isSelected)
    }

    func testNavalAdvancedSettingsKeepsDraftChoicesWhenReopenedAndRestoresLandMode() {
        let app = launch()
        app.buttons["new-game.mode.vast"].tap()
        app.buttons["new-game.rules.naval"].tap()
        XCTAssertFalse(app.buttons["new-game.naval.family.surprise"].exists)
        XCTAssertFalse(app.buttons["new-game.naval.fog"].exists)
        openAdvanced(in: app)
        selectEveryIslandFamily(in: app)
        for identifier in ["new-game.naval.fog", "new-game.naval.resources"] {
            let toggle = app.buttons[identifier]
            reveal(toggle, in: app)
            XCTAssertEqual(toggle.value as? String, "On")
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "Off")
        }
        app.buttons["new-game.naval.advanced.done"].tap()
        assertAdvancedDraft(in: app)
        openAdvanced(in: app)
        XCTAssertTrue(app.buttons["new-game.naval.family.twinIslands"].isSelected)
        for identifier in ["new-game.naval.fog", "new-game.naval.resources"] {
            XCTAssertEqual(app.buttons[identifier].value as? String, "Off")
        }
        app.buttons["new-game.naval.advanced.done"].tap()
        assertLandModeRestored(in: app)
        retain("Naval — compact advanced settings entry", app: app)
    }

    func testNavalDefaultSetupFitsWithoutScrollingOnRegularPhone() throws {
        let app = launch(scrollToBottom: false)
        guard app.frame.height >= 800 else { throw XCTSkip("Short phones retain accessible scrolling") }
        app.buttons["new-game.rules.naval"].tap()
        let scroll = app.scrollViews.firstMatch
        retain("Naval — default setup before fit assertions", app: app)
        XCTAssertTrue(scroll.frame.contains(app.otherElements["screen.new-game"].staticTexts["New Game"].frame))
        for identifier in ["new-game.rules.naval", "new-game.naval.advanced",
                           "new-game.difficulty.expert", "new-game.seating.random"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.isHittable)
            XCTAssertTrue(scroll.frame.contains(control.frame), "A default Naval row requires scrolling: \(identifier)")
        }
        XCTAssertTrue(app.buttons["new-game.start"].isHittable)
        XCTAssertTrue(app.buttons["new-game.cancel"].isHittable)
        XCTAssertEqual(app.buttons["new-game.naval.advanced"].frame.minX,
                       app.buttons["new-game.rules.standard"].frame.minX, accuracy: 1)
        retain("Naval — complete setup without scrolling", app: app)
    }

    func testAdvancedSettingsHelpAndDoneRemainReachableAtMaximumText() {
        let app = launch(scrollToBottom: false,
                         extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        reveal(app.buttons["new-game.rules.naval"], in: app)
        app.buttons["new-game.rules.naval"].tap()
        openAdvanced(in: app)
        let done = app.buttons["new-game.naval.advanced.done"]
        let footer = done.frame
        app.buttons["About Islands"].tap()
        let help = app.otherElements["new-game.naval.advanced.island-help"]
        for title in ["Surprise me", "Archipelago", "Peninsula", "Twin Islands"] {
            XCTAssertTrue(help.staticTexts[title].exists)
        }
        for identifier in ["new-game.naval.fog", "new-game.naval.resources"] {
            let toggle = app.buttons[identifier]
            revealWhole(toggle, in: app)
            XCTAssertTrue(toggle.isHittable)
            XCTAssertLessThanOrEqual(toggle.frame.maxY, app.scrollViews.firstMatch.frame.maxY)
            toggle.tap()
        }
        XCTAssertEqual(done.frame, footer)
        XCTAssertTrue(done.isHittable)
        retain("Naval — advanced settings at maximum text", app: app)
        done.tap()
        XCTAssertTrue(app.buttons["new-game.start"].isHittable)
    }

    private func selectEveryIslandFamily(in app: XCUIApplication) {
        let choices = [("surprise", "Surprise me"), ("archipelago", "Archipelago"),
                       ("peninsula", "Peninsula"), ("twinIslands", "Twin Islands")]
        for (key, title) in choices {
            let family = app.buttons["new-game.naval.family.\(key)"]
            XCTAssertTrue(family.isHittable)
            XCTAssertGreaterThanOrEqual(family.frame.height, 44)
            family.tap()
            XCTAssertTrue(family.isSelected)
            XCTAssertTrue(app.otherElements["new-game.naval.advanced.island-help"].staticTexts[title].exists)
        }
        retain("Naval — dedicated island and discovery settings", app: app)
    }

    private func assertAdvancedDraft(in app: XCUIApplication) {
        let advanced = app.buttons["new-game.naval.advanced"]
        XCTAssertTrue(advanced.isHittable)
        XCTAssertEqual(advanced.value as? String, "Twin Islands · Mist off · Resources off")
        XCTAssertFalse(app.buttons["new-game.naval.family.twinIslands"].exists)
        XCTAssertFalse(app.buttons["new-game.naval.resources"].exists)
        XCTAssertTrue(app.buttons["new-game.rules.naval"].isSelected)
    }

    private func assertLandModeRestored(in app: XCUIApplication) {
        app.buttons["new-game.rules.standard"].tap()
        XCTAssertTrue(app.buttons["new-game.mode.vast"].isSelected)
        XCTAssertFalse(app.buttons["new-game.naval.advanced"].exists)
        app.buttons["new-game.rules.conquest"].tap()
        XCTAssertTrue(app.buttons["new-game.mode.vast"].isSelected)
        app.buttons["new-game.rules.naval"].tap()
        assertAdvancedDraft(in: app)
    }

    private func openAdvanced(in app: XCUIApplication) {
        let advanced = app.buttons["new-game.naval.advanced"]
        reveal(advanced, in: app)
        advanced.tap()
        XCTAssertTrue(app.buttons["new-game.naval.advanced.done"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["new-game.start"].isHittable)
        XCTAssertFalse(app.buttons["new-game.cancel"].isHittable)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable, "The setting cannot be reached: \(element.identifier)")
    }

    private func revealWhole(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["new-game.naval.advanced.content"]
        for _ in 0..<20 where !scroll.frame.contains(element.frame) {
            let above = element.frame.minY < scroll.frame.minY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.4 : 0.65))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.65 : 0.4))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        retain("Naval — advanced control \(element.identifier) viewport", app: app)
        XCTAssertTrue(scroll.frame.contains(element.frame), "The advanced setting remains cropped: \(element.identifier)")
        XCTAssertTrue(element.isHittable)
    }

    private func launch(scrollToBottom: Bool = true, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"] + extra
        if scrollToBottom { app.launchArguments.append("-qaScrollNewGameToBottom") }
        app.launch()
        XCTAssertTrue(app.buttons["new-game.rules.naval"].waitForExistence(timeout: 10))
        return app
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
