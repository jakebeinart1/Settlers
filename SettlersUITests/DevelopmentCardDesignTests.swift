import XCTest

/// Rendered geometry and deliberate card inspection complement the existing
/// legality journeys. A complete match alone auto-dismisses card surfaces and
/// cannot detect a clipped resource row or counts on different baselines.
@MainActor
final class DevelopmentCardDesignTests: XCTestCase {
    private let cardTypes = ["knight", "roadBuilding", "yearOfPlenty", "monopoly", "victoryPoint"]
    private let resources = ["brick", "lumber", "ore", "grain", "wool"]

    func testAllFiveNavalCardDetailsKeepNormalTextChoicesAndActionsInsideThePanel() {
        let app = launchHand()
        for type in cardTypes {
            selectCard(type, in: app)
            assertPanelFits(in: app)
            assertVisible(app.staticTexts["dev-cards.detail.\(type)"], in: contentFrame(in: app))
            assertActionsFit(type, in: app)
            if type == "monopoly" || type == "yearOfPlenty" {
                for resource in resources {
                    assertVisible(app.buttons["dev-cards.resource.\(resource)"], in: contentFrame(in: app))
                }
            }
            if type == "monopoly" {
                XCTAssertFalse(app.staticTexts["Bank supply"].exists,
                               "Monopoly collects from rivals; bank counts are irrelevant")
            }
            capture("Naval card — \(type) normal text", in: app)
        }
        app.buttons["dev-cards.close"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 3),
                      "The card fixture must preserve a real Naval world")
    }

    func testHudCardAndResourceCountsShareOneBaselineWithoutReadyInCompactTitles() {
        let app = launchHand()
        app.buttons["dev-cards.close"].tap()
        let resourceCount = marker("human-resource.count.ore", in: app)
        XCTAssertTrue(resourceCount.waitForExistence(timeout: 3))
        let baseline = resourceCount.frame.midY
        let shelfCount = marker("dev-cards.hud-count.shelf", in: app)
        XCTAssertTrue(shelfCount.exists)
        XCTAssertEqual(shelfCount.frame.midY, baseline, accuracy: 1)
        let hud = app.scrollViews.containing(.button, identifier: "dev-cards.shelf").firstMatch
        XCTAssertTrue(hud.exists)
        for type in cardTypes {
            let card = app.buttons["dev-cards.tile.\(type)"]
            for _ in 0..<6 where !card.isHittable { hud.swipeLeft() }
            XCTAssertTrue(card.isHittable, "Every held card must be reachable: \(type)")
            XCTAssertFalse(card.label.uppercased().contains("READY"))
            let count = marker("dev-cards.hud-count.\(type)", in: app)
            XCTAssertTrue(count.exists)
            XCTAssertEqual(count.frame.midY, baseline, accuracy: 1, "Count baseline for \(type)")
        }
        capture("Naval hand — aligned card and resource counts", in: app)
    }

    func testLargestTextMonopolyAndPlentyKeepChoicesScrollableAndActionsPinned() {
        let app = launchHand(largeText: true)
        for type in ["monopoly", "yearOfPlenty"] {
            selectCard(type, in: app)
            assertPanelFits(in: app)
            assertActionsFit(type, in: app)
            let ore = app.buttons["dev-cards.resource.ore"]
            scrollToChoice(ore, in: app)
            ore.tap()
            if type == "yearOfPlenty" {
                ore.tap()
                XCTAssertTrue(app.buttons["dev-cards.play.yearOfPlenty"].isEnabled)
                let selected = app.buttons["dev-cards.selected.ore"]
                scrollToChoice(selected, in: app, direction: .down)
                selected.tap()
                XCTAssertFalse(app.buttons["dev-cards.play.yearOfPlenty"].isEnabled)
                scrollToChoice(ore, in: app)
                ore.tap()
            }
            XCTAssertTrue(app.buttons["dev-cards.play.\(type)"].isEnabled)
            assertActionsFit(type, in: app)
            capture("Naval card — \(type) largest text selected", in: app)
        }
        app.buttons["dev-cards.play.yearOfPlenty"].tap()
        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        assertVisible(app.buttons["dev-cards.result.continue"], in: app.frame)
        capture("Year of Plenty — largest text result and acknowledgement", in: app)
        app.buttons["dev-cards.result.continue"].tap()
        XCTAssertTrue(app.buttons["Roll Dice"].waitForExistence(timeout: 3))
    }

    func testPlentyKeepsChosenCardsInPickOrderAndPaysTheMixedPair() {
        let app = launchHand()
        selectCard("yearOfPlenty", in: app)
        app.buttons["dev-cards.resource.grain"].tap()
        app.buttons["dev-cards.resource.ore"].tap()
        let grain = app.buttons["dev-cards.selected.grain"]
        let ore = app.buttons["dev-cards.selected.ore"]
        XCTAssertLessThan(grain.frame.minX, ore.frame.minX,
                          "The first chosen card must not jump when the second resource sorts earlier")
        grain.tap()
        XCTAssertFalse(app.buttons["dev-cards.play.yearOfPlenty"].isEnabled)
        app.buttons["dev-cards.resource.grain"].tap()
        XCTAssertLessThan(ore.frame.minX, grain.frame.minX)
        capture("Year of Plenty — ordered mixed choices", in: app)
        app.buttons["dev-cards.play.yearOfPlenty"].tap()
        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The bank gave you 1 Ore and 1 Grain."].exists)
        capture("Year of Plenty — actual mixed resource receipt", in: app)
    }

    func testPlentyScarcityAndMonopolyBankIndependenceUseTheirActualRules() {
        let app = launchHand(extra: ["-qaDevCardBankScarce"])
        selectCard("yearOfPlenty", in: app)
        let ore = app.buttons["dev-cards.resource.ore"]
        XCTAssertTrue(ore.isEnabled)
        ore.tap()
        XCTAssertFalse(ore.isEnabled, "The last bank Ore cannot be selected a second time")
        XCTAssertFalse(app.buttons["dev-cards.resource.wool"].isEnabled)
        XCTAssertFalse(app.buttons["dev-cards.play.yearOfPlenty"].isEnabled)
        app.buttons["dev-cards.resource.grain"].tap()
        XCTAssertTrue(app.buttons["dev-cards.play.yearOfPlenty"].isEnabled)
        selectCard("monopoly", in: app)
        let wool = app.buttons["dev-cards.resource.wool"]
        XCTAssertTrue(wool.isEnabled, "Monopoly may choose a resource absent from the bank")
        wool.tap()
        XCTAssertTrue(app.buttons["dev-cards.play.monopoly"].isEnabled)
        XCTAssertFalse(app.staticTexts["Bank supply"].exists)
        capture("Naval Monopoly — bank stock does not limit selection", in: app)
        app.buttons["dev-cards.play.monopoly"].tap()
        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        capture("Naval Monopoly — collects rival stock with an empty bank", in: app)
        app.buttons["dev-cards.result.continue"].tap()
        let heldWool = Int(app.otherElements["human-resource.wool"].value as? String ?? "")
        XCTAssertNotNil(heldWool)
        XCTAssertGreaterThan(heldWool ?? 0, 0, "A zero bank must not prevent collecting rivals' Wool")
        XCTAssertTrue(app.buttons["Roll Dice"].waitForExistence(timeout: 3))
    }

    /// Starts an ordinary seeded game. The audit modifier only pauses the
    /// existing app driver; no card, resource, building or winning state is
    /// seeded. Native taps inspect genuinely owned cards and acknowledge real
    /// receipts between those production-session checkpoints.
    func testOrdinaryNavalMatchIncludesDeliberateCardInspectionAndReachesAnActualWinner() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalExpert", "-qaNavalSeed=7501", "-qaPlayToEnd", "-qaInspectCompleteMatch"]
        app.launch()
        let resume = app.buttons["qa.complete-match.continue"]
        let winner = app.buttons["game-over.new-game"]
        var stages: Set<String> = []
        let deadline = Date().addingTimeInterval(360)
        while !winner.exists && Date() < deadline {
            guard resume.waitForExistence(timeout: 5) else { continue }
            let summary = resume.value as? String ?? ""
            let stage = summary.split(separator: ";").first.map(String.init) ?? ""
            XCTAssertFalse(stage.isEmpty)
            XCTAssertTrue(stages.insert(stage).inserted, "Each audit stage must stop only once")
            capture("Ordinary Naval match — \(summary)", in: app)
            acknowledgeReceipt(in: app)
            inspectNaturalHand(in: app, stage: stage)
            XCTAssertTrue(resume.isHittable)
            resume.tap()
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !resume.exists || (resume.value as? String) != summary
            }, object: resume)
            XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        }
        XCTAssertTrue(winner.exists, "The inspected ordinary match must finish before its bounded deadline")
        XCTAssertTrue(stages.contains("purchase"), "This seed must inspect a naturally purchased card")
        XCTAssertTrue(stages.contains("mature-hand"), "The later-turn private hand was never inspected")
        capture("Ordinary Naval match — actual winner after card inspections", in: app)
        XCTAssertTrue(app.buttons["game-over.replay"].waitForExistence(timeout: 10))
        app.buttons["game-over.main-menu"].tap()
        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["main-menu.resume"].exists)
    }

    private func launchHand(largeText: Bool = false, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode", "-qaShowDevCardHand"] + extra
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 10))
        return app
    }

    private func selectCard(_ type: String, in app: XCUIApplication) {
        let card = app.buttons["dev-cards.tile.\(type)"]
        let hand = app.scrollViews["dev-cards.hand-scroll"]
        XCTAssertTrue(hand.exists)
        let middle = app.scrollViews["dev-cards.middle-scroll"]
        for _ in 0..<6 where hand.frame.minY < contentFrame(in: app).minY - 1 {
            XCTAssertTrue(middle.exists)
            middle.swipeDown()
        }
        for _ in 0..<6 where !card.isHittable {
            reveal(card, inside: hand, viewport: hand.frame, horizontally: true)
        }
        XCTAssertTrue(card.isHittable, "Card selector must be reachable: \(type)")
        XCTAssertLessThanOrEqual(card.frame.width, hand.frame.width + 1)
        for _ in 0..<6 where !hand.frame.insetBy(dx: -1, dy: -1).contains(card.frame) {
            reveal(card, inside: hand, viewport: hand.frame, horizontally: true)
        }
        if !hand.frame.insetBy(dx: -1, dy: -1).contains(card.frame) {
            print("CARD SELECTOR FRAMES \(type): hand=\(hand.frame), card=\(card.frame), content=\(contentFrame(in: app))")
            print(app.debugDescription)
            capture("Card selector frame counterexample — \(type)", in: app)
        }
        assertContained(card.frame, within: hand.frame, message: "Clipped selector: \(type)")
        card.tap()
        XCTAssertTrue(app.staticTexts["dev-cards.detail.\(type)"].waitForExistence(timeout: 2))
    }

    private func assertPanelFits(in app: XCUIApplication) {
        let panel = marker("dev-cards.panel-frame", in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        assertContained(panel.frame, within: app.frame, message: "Card panel extends off screen")
        XCTAssertGreaterThan(panel.frame.width, 100)
        XCTAssertGreaterThan(contentFrame(in: app).height, 40)
    }

    private func contentFrame(in app: XCUIApplication) -> CGRect {
        let content = marker("dev-cards.content-frame", in: app)
        XCTAssertTrue(content.exists)
        return content.frame
    }

    private func assertActionsFit(_ type: String, in app: XCUIApplication) {
        let panel = marker("dev-cards.panel-frame", in: app).frame
        assertVisible(app.buttons["dev-cards.close"], in: panel)
        if type == "victoryPoint" {
            XCTAssertFalse(app.buttons["dev-cards.play.victoryPoint"].exists)
        } else {
            assertVisible(app.buttons["dev-cards.play.\(type)"], in: panel)
        }
    }

    private func assertVisible(_ element: XCUIElement, in frame: CGRect) {
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable, "Expected the whole control to be usable: \(element.identifier)")
        assertContained(element.frame, within: frame, message: "Clipped control: \(element.identifier)")
    }

    private func assertContained(_ frame: CGRect, within container: CGRect, message: String) {
        XCTAssertGreaterThanOrEqual(frame.minX, container.minX - 1, message)
        XCTAssertGreaterThanOrEqual(frame.minY, container.minY - 1, message)
        XCTAssertLessThanOrEqual(frame.maxX, container.maxX + 1, message)
        XCTAssertLessThanOrEqual(frame.maxY, container.maxY + 1, message)
    }

    private enum ScrollDirection { case up, down }

    private func scrollToChoice(_ choice: XCUIElement, in app: XCUIApplication, direction: ScrollDirection = .up) {
        let scroll = app.scrollViews["dev-cards.middle-scroll"]
        for _ in 0..<10 {
            if !choice.exists {
                XCTAssertTrue(scroll.exists, "A deferred resource choice needs its visible middle scroller")
                if direction == .up { scroll.swipeUp() } else { scroll.swipeDown() }
                continue
            }
            if choice.isHittable && contentFrame(in: app).insetBy(dx: -1, dy: -1).contains(choice.frame) { return }
            XCTAssertTrue(scroll.exists, "Overflowing detail needs the dedicated middle scroller")
            reveal(choice, inside: scroll, viewport: contentFrame(in: app), horizontally: false)
        }
        assertVisible(choice, in: contentFrame(in: app))
    }

    /// Direction follows current geometry so an overshoot is corrected rather
    /// than amplified. Native drags stay inside the observed scroll viewport.
    private func reveal(_ target: XCUIElement, inside scroll: XCUIElement,
                        viewport: CGRect, horizontally: Bool) {
        let frame = target.frame
        if horizontally, frame.width > viewport.width * 0.8 {
            if frame.minX < viewport.minX - 1 { scroll.swipeRight() } else { scroll.swipeLeft() }
            return
        }
        let length = horizontally ? viewport.width : viewport.height
        let before = horizontally ? viewport.minX - frame.minX : viewport.minY - frame.minY
        let after = horizontally ? frame.maxX - viewport.maxX : frame.maxY - viewport.maxY
        XCTAssertLessThanOrEqual(horizontally ? frame.width : frame.height, length + 1,
                                 "A control larger than its viewport cannot become fully visible")
        let positive = before > 1
        let overflow = positive ? before : max(after, 0)
        let fraction = min(0.45, max(0.12, (overflow + 12) / length))
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(
            dx: horizontally ? 0.5 + (positive ? fraction : -fraction) : 0.5,
            dy: horizontally ? 0.5 : 0.5 + (positive ? fraction : -fraction)))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func acknowledgeReceipt(in app: XCUIApplication) {
        if app.buttons["dev-cards.continue"].exists { app.buttons["dev-cards.continue"].tap() }
        if app.buttons["dev-cards.result.continue"].exists { app.buttons["dev-cards.result.continue"].tap() }
    }

    private func inspectNaturalHand(in app: XCUIApplication, stage: String) {
        let shelf = app.buttons["dev-cards.shelf"]
        XCTAssertTrue(shelf.isHittable, "An audit checkpoint must allow private hand inspection")
        shelf.tap()
        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 3))
        assertPanelFits(in: app)
        var inspected = 0
        for type in cardTypes where app.buttons["dev-cards.tile.\(type)"].exists {
            selectCard(type, in: app)
            assertActionsFit(type, in: app)
            capture("Ordinary Naval match — \(stage) owned \(type)", in: app)
            inspected += 1
        }
        if stage != "resolution" { XCTAssertGreaterThan(inspected, 0, "Inspect naturally held cards, never a fake hand") }
        app.buttons["dev-cards.close"].tap()
    }

    private func marker(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
