import XCTest

/// The summary fixture proves presentation and navigation, not played outcomes
/// or live CloudKit delivery. Complete-match and sync suites retain those jobs.
/// Overview checks deliberately run before any swipe: reachability after a
/// scroll cannot establish that the initial Leaderboard fits the device.
@MainActor
final class PlayerRatingsFlowTests: XCTestCase {
    private static let people = ["alex", "jake", "kyle"]
    private static let tolerance: CGFloat = 1
    private static let timeout: TimeInterval = 5
    private static let largestText = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]

    func testHomeHasOneLeaderboardEntryWithoutASeparateRatingSection() {
        let app = launch(seed: true)
        XCTAssertFalse(app.buttons["main-menu.ratings"].exists,
                       "The existing Leaderboard is the only home entry for ratings")
        let entry = app.buttons["main-menu.leaderboard"]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout) && entry.isHittable)
        assertContained(entry, in: app.frame)
        assertContained(app.buttons["main-menu.new-game"], in: app.frame)
        capture("01-restored-home", app)
        entry.tap()
        XCTAssertTrue(app.otherElements["screen.leaderboard"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["leaderboard.scope.players"].isSelected)
        assertContains(element("ratings.overall", in: app), ["13 wins", "9 losses"])
    }

    func testStandardPhoneOverviewFitsAt402By874WithoutSwiping() throws {
        let app = openOverview()
        try requireViewport(CGSize(width: 402, height: 874), app)
        assertInitialOverviewFits(app)
        capture("02-complete-player-leaderboard", app)
    }

    func testCompactPhoneOverviewFitsAt375By667() throws {
        let app = openOverview()
        try requireViewport(CGSize(width: 375, height: 667), app)
        assertInitialOverviewFits(app)
        capture("03-compact-player-leaderboard", app)
        chooseTier("classic", app)
        capture("03-compact-unrated-standings-before-fit", app)
        assertUnratedStandings(app)
        assertInitialOverviewFits(app)
    }

    func testReturningHomeFitsResumeHistoryAndTheSingleLeaderboardEntry() {
        let app = launch(seed: true, extra: ["-qaSeedGameHistory", "-qaPlayerRatingsBusyMenu"])
        app.buttons["main-menu.new-game"].tap()
        let start = app.buttons["new-game.start"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout) && start.isEnabled)
        start.tap()
        let settings = app.buttons["game.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Self.timeout) && settings.isHittable)
        settings.tap()
        let quit = app.buttons["in-game-settings.quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: Self.timeout) && quit.isHittable)
        quit.tap()
        let confirm = app.buttons["Main Menu"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.timeout))
        confirm.tap()
        XCTAssertTrue(element("screen.main-menu", in: app).waitForExistence(timeout: Self.timeout))
        let actions = ["main-menu.new-game", "main-menu.resume", "main-menu.game-history", "main-menu.leaderboard"]
            .map { app.buttons[$0] }
        for action in actions {
            assertContained(action, in: app.frame)
            XCTAssertTrue(action.isHittable)
        }
        assertNonoverlapping(actions)
        let statistics = ["Finished games on this device", "Average time", "Average VP", "20m", "9.0"]
            .map { app.staticTexts[$0] }
        for statistic in statistics { assertContained(statistic, in: app.frame) }
        assertNonoverlapping(actions + statistics)
        XCTAssertFalse(app.buttons["main-menu.ratings"].exists)
        capture("04-returning-home-with-real-resume-and-history", app)
        enterLeaderboard(app)
        assertInitialOverviewFits(app)
    }

    func testMaximumWidthPlayerNamesKeepTheOverviewAligned() {
        let app = openOverview(extra: ["-qaPlayerRatingsWideNames"])
        assertInitialOverviewFits(app)
        let ownRow = app.buttons["ratings.player.ratings-preview-alex"]
        XCTAssertTrue(ownRow.label.contains("WWWWWWWWWWWW"), "The full name remains available to VoiceOver")
        capture("04-wide-player-names", app)
        ownRow.tap()
        assertNormalProfileFits(app)
        capture("04-wide-name-profile", app)
    }

    func testFiltersKeepModeAndDifficultyRatingsIndependentAndPersist() {
        let app = openOverview()
        openPerson("alex", app)
        let expert = rating(app).label
        chooseTier("classic", app)
        XCTAssertEqual(rating(app, expectsRated: false).label, "Unrated")
        chooseTier("expert", app)
        XCTAssertEqual(rating(app).label, expert)
        chooseMode("naval.standard", app)
        XCTAssertNotEqual(rating(app).label, expert)
        assertRecord(wins: 4, losses: 2, games: 6, app)
        capture("04-voyages-personal-record", app)
        chooseTier("classic", app)
        XCTAssertEqual(rating(app, expectsRated: false).label, "Unrated")
        chooseMode("classic.conquest", app)
        assertRecord(wins: 1, losses: 3, games: 4, app)
        app.buttons["leaderboard.close"].tap()
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        enterLeaderboard(app)
        assertContains(app.buttons["ratings.mode"], ["Conquest"])
        assertContains(app.buttons["ratings.tier"], ["Classic"])
        openPerson("alex", app)
        assertRecord(wins: 1, losses: 3, games: 4, app)
    }

    func testNewPlayerSeesAnHonestUnratedRecordAndEmptyHistory() {
        let app = launch(seed: false)
        enterLeaderboard(app)
        let ownRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "ratings.player.", "you"
        )).firstMatch
        XCTAssertTrue(ownRow.waitForExistence(timeout: Self.timeout))
        ownRow.tap()
        XCTAssertTrue(element("ratings.profile", in: app).waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(rating(app, expectsRated: false).label, "Unrated")
        assertRecord(wins: 0, losses: 0, games: 0, app)
        assertNormalProfileFits(app, expectsChart: false)
        capture("05-unrated-personal-record", app)
        app.buttons["ratings.games"].tap()
        XCTAssertTrue(element("ratings.history", in: app).waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(resultRows(app).firstMatch.exists)
        assertProfileChromeFits(app)
        assertDetailContentDoesNotCoverNavigation(marker("ratings.history-frame", app), app, context: true)
        capture("06-empty-game-history", app)
    }

    func testSharedPlayersOpenTheirOwnRecordAndBoundedHistory() {
        let app = openOverview()
        openPerson("kyle", app)
        assertRecord(wins: 4, losses: 8, games: 12, app)
        assertNormalProfileFits(app)
        capture("07-kyle-personal-record", app)
        app.buttons["ratings.games"].tap()
        XCTAssertTrue(element("ratings.history", in: app).waitForExistence(timeout: Self.timeout))
        assertContains(element("ratings.record-context", in: app), ["Kyle", "Classic", "Expert"])
        let list = marker("ratings.history-frame", app)
        let first = resultRows(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: Self.timeout))
        assertContained(first, in: list.frame)
        XCTAssertTrue(first.label.contains("Elo"), first.label)
        assertProfileChromeFits(app)
        assertDetailContentDoesNotCoverNavigation(list, app, context: true)
        capture("08-bounded-game-history", app)
        app.buttons["ratings.back"].tap()
        assertRecord(wins: 4, losses: 8, games: 12, app)
        app.buttons["ratings.back"].tap()
        assertInitialOverviewFits(app)
    }

    func testRatingHelpAndAccountStatusAreReachableFromLeaderboard() {
        let app = openOverview()
        app.buttons["ratings.help"].tap()
        let closeHelp = app.buttons["ratings.help-close"]
        XCTAssertTrue(closeHelp.waitForExistence(timeout: Self.timeout) && closeHelp.isHittable)
        capture("09-rating-help", app)
        closeHelp.tap()
        app.buttons["leaderboard.account"].tap()
        let status = element("leaderboard.sync-status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(status.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let closeAccount = app.buttons["leaderboard.account-close"]
        XCTAssertTrue(closeAccount.waitForExistence(timeout: Self.timeout) && closeAccount.isHittable)
        capture("10-account-and-sync-status", app)
        closeAccount.tap()
        assertInitialOverviewFits(app)
    }

    func testGhostsAndTheirAIReferencesRemainWithinLeaderboard() {
        let app = openOverview(extra: ["-qaSeedLeaderboard"])
        app.buttons["leaderboard.scope.ghosts"].tap()
        XCTAssertTrue(app.buttons["leaderboard.scope.ghosts"].isSelected)
        let classic = app.buttons["leaderboard.row.classic"]
        assertContains(classic, ["1000", "fixed"])
        // This combined fixture includes rated Expert games, so its rating
        // evolves. Only Classic is a fixed reference on the ghost ladder.
        assertContains(app.buttons["leaderboard.row.expert"], ["Expert"])
        let ghost = app.buttons["leaderboard.row.ghost:jake"]
        XCTAssertTrue(ghost.waitForExistence(timeout: Self.timeout))
        capture("11-ghost-and-legacy-ai-ladder", app)
        ghost.tap()
        XCTAssertTrue(element("screen.rated-entity", in: app).waitForExistence(timeout: Self.timeout))
        let radar = element("leaderboard.radar", in: app)
        XCTAssertTrue(radar.exists && radar.label.contains("Production"))
        capture("12-preserved-ghost-radar", app)
        app.buttons["leaderboard.back"].tap()
        XCTAssertTrue(app.buttons["leaderboard.scope.ghosts"].isSelected)
        app.buttons["leaderboard.scope.players"].tap()
        XCTAssertTrue(app.buttons["leaderboard.scope.players"].isSelected)
    }

    func testGhostPersonModeRecordReturnsToTheSameGhostDetail() {
        let app = openOverview(extra: ["-qaSeedLeaderboard"])
        app.buttons["leaderboard.scope.ghosts"].tap()
        let jake = app.buttons["leaderboard.row.person:ratings-preview-jake"]
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: Self.timeout))
        revealOnlyInside(jake, viewport: list, app)
        jake.tap()
        let detail = element("screen.rated-entity", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout))
        let records = app.buttons["leaderboard.ai-ratings"]
        revealOnlyInside(records, viewport: detail, app)
        capture("20-ghost-ladder-person-and-ai-records-link", app)
        records.tap()
        XCTAssertTrue(element("ratings.profile", in: app).waitForExistence(timeout: Self.timeout))
        assertRecord(wins: 6, losses: 6, games: 12, app)
        app.buttons["ratings.back"].tap()
        XCTAssertTrue(app.buttons["leaderboard.scope.ghosts"].isSelected)
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(element("leaderboard.radar", in: app).exists)
        XCTAssertTrue(records.exists)
        capture("21-ghost-person-detail-restored-after-records", app)
    }

    func testGhostDetailBackStaysPinnedWhileReadingItsStyle() {
        let app = openOverview(extra: ["-qaSeedLeaderboard"])
        app.buttons["leaderboard.scope.ghosts"].tap()
        app.buttons["leaderboard.row.ghost:jake"].tap()
        let detail = element("screen.rated-entity", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout))
        let back = app.buttons["leaderboard.back"]
        XCTAssertTrue(back.isHittable)
        let original = back.frame
        for _ in 0..<3 {
            let start = detail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = detail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.1, thenDragTo: end)
            assertUnmoved(back.frame, original)
            XCTAssertTrue(back.isHittable)
        }
        capture("21-ghost-detail-pinned-back-after-style", app)
        back.tap()
        XCTAssertTrue(app.buttons["leaderboard.row.ghost:jake"].waitForExistence(timeout: Self.timeout))
    }

    func testWinReceiptOpensTheSameRatingPool() { assertResult(won: true) }
    func testLossReceiptOpensTheSameRatingPool() { assertResult(won: false) }

    func testLargeTextKeepsOverviewChromePinnedAroundItsBoundedTable() {
        let app = openOverview(extra: Self.largestText)
        assertAccessibleOverviewFits(app)
        capture("15-accessibility-bounded-standings-bottom", app)
    }

    func testLargestTextAndWideNamesKeepRowsInsideTheBoundedTable() {
        let app = openOverview(extra: Self.largestText + ["-qaPlayerRatingsWideNames"])
        assertAccessibleOverviewFits(app)
        capture("15-accessibility-wide-name-standings-bottom", app)
    }

    func testCompactLargestTextAndWideNamesKeepTheOverviewUsable() throws {
        let app = openOverview(extra: Self.largestText + ["-qaPlayerRatingsWideNames"])
        try requireViewport(CGSize(width: 375, height: 667), app)
        chooseMode("vast.conquest", app)
        capture("15-compact-accessibility-vast-conquest-top-before-fit", app)
        assertContains(app.buttons["ratings.mode"], ["Vast", "Conquest"])
        assertContains(app.buttons["ratings.tier"], ["Expert"])
        assertUnratedStandings(app)
        assertAccessibleOverviewFits(app)
        capture("15-compact-accessibility-vast-conquest-bottom", app)
        let ownRow = app.buttons["ratings.player.ratings-preview-alex"]
        revealOnlyInside(ownRow, viewport: marker("leaderboard.table-frame", app), app)
        XCTAssertTrue(ownRow.isHittable)
        ownRow.tap()
        XCTAssertTrue(element("ratings.profile", in: app).waitForExistence(timeout: Self.timeout))
        capture("16-compact-accessibility-vast-conquest-unrated-before-fit", app)
        XCTAssertEqual(rating(app, expectsRated: false).label, "Unrated")
        assertPinnedProfileControlsFit(app)
        app.buttons["ratings.games"].tap()
        assertEmptyGamesFit(
            app, context: ["WWWWWWWWWWWW", "Vast Conquest", "Expert"],
            screenshot: "18-compact-accessibility-vast-conquest-empty-games")
        app.buttons["ratings.back"].tap()
        XCTAssertEqual(rating(app, expectsRated: false).label, "Unrated")
        assertPinnedProfileControlsFit(app)
        app.buttons["ratings.back"].tap()
        XCTAssertTrue(app.buttons["leaderboard.scope.players"].isSelected)
        assertContains(app.buttons["ratings.mode"], ["Vast", "Conquest"])
        assertContains(app.buttons["ratings.tier"], ["Expert"])
    }

    func testCompactLargestTextUnratedProfileRemainsReadable() throws {
        let app = openOverview(extra: Self.largestText)
        try requireViewport(CGSize(width: 375, height: 667), app)
        openPerson("alex", app)
        chooseTier("classic", app)
        XCTAssertEqual(rating(app, expectsRated: false).label, "Unrated")
        capture("16-compact-accessibility-unrated-before-fit", app)
        assertPinnedProfileControlsFit(app)
        let body = marker("ratings.profile-frame", app)
        let controls = ["leaderboard.close", "ratings.back", "ratings.help", "ratings.mode", "ratings.tier", "ratings.games"]
            .map { app.buttons[$0] }
        let frames = controls.map(\.frame)
        let fields = ["ratings.rating", "ratings.rating-unit", "ratings.wins", "ratings.losses", "ratings.win-rate",
                      "ratings.game-count", "ratings.first-game"]
        for id in fields {
            let field = element(id, in: app)
            revealOnlyInside(field, viewport: body, app)
            assertContained(field, in: body.frame)
            for (control, before) in zip(controls, frames) { assertUnmoved(control.frame, before) }
        }
        let explanation = element("ratings.first-game", in: app)
        assertContains(explanation, ["first rated game", "Elo"])
        XCTAssertEqual(explanation.label.filter(\.isNumber), "1000")
        capture("16-compact-accessibility-unrated-explanation", app)
        revealOnlyInside(element("ratings.rating", in: app), viewport: body, app)
        assertContained(element("ratings.rating", in: app), in: body.frame)
        assertContained(element("ratings.rating-unit", in: app), in: body.frame)
        for (control, before) in zip(controls, frames) { assertUnmoved(control.frame, before) }
        assertPinnedProfileControlsFit(app)
        capture("16-compact-accessibility-unrated-profile", app)
    }

    private func assertAccessibleOverviewFits(_ app: XCUIApplication) {
        capture("15-accessibility-standings-top-before-fit", app)
        assertOverviewChromeFits(app)
        let table = marker("leaderboard.table-frame", app)
        let controls = pinnedControls(app)
        let frames = controls.map(\.frame)
        let rows = Self.people.map { app.buttons["ratings.player.ratings-preview-\($0)"] }
            + [element("ratings.ai-standing", in: app)]
        for row in rows {
            revealOnlyInside(row, viewport: table, app)
            assertContained(row, in: table.frame)
            for (control, before) in zip(controls, frames) {
                assertUnmoved(control.frame, before)
            }
        }
        XCTAssertTrue(app.buttons["leaderboard.close"].isHittable)
    }

    func testLargeTextKeepsProfileHistoryAndChoiceControlsWithinTheViewport() {
        let app = openOverview(extra: Self.largestText)
        openPerson("alex", app)
        assertPinnedProfileControlsFit(app)
        XCTAssertEqual(element("ratings.win-rate", in: app).frame.minY,
                       element("ratings.game-count", in: app).frame.minY, accuracy: Self.tolerance)
        capture("16-accessibility-personal-record", app)
        chooseMode("naval.standard", app)
        let body = marker("ratings.profile-frame", app)
        let trend = app.buttons["ratings.trend"]
        revealOnlyInside(trend, viewport: body, app)
        trend.tap()
        assertContains(element("leaderboard.title", in: app), ["Rating history"])
        assertContains(element("ratings.record-context", in: app), ["Alex", "Voyages", "Expert"])
        let chart = marker("ratings.trend-frame", app)
        assertContained(chart, in: marker("leaderboard.content-frame", app).frame)
        assertDetailContentDoesNotCoverNavigation(chart, app, context: true)
        assertContained(element("ratings.chart", in: app), in: chart.frame)
        assertProfileChromeFits(app)
        capture("17-accessibility-rating-history", app)
        app.buttons["ratings.back"].tap()
        assertPinnedProfileControlsFit(app)
        app.buttons["ratings.games"].tap()
        XCTAssertTrue(element("ratings.history", in: app).waitForExistence(timeout: Self.timeout))
        let list = marker("ratings.history-frame", app)
        assertContained(list, in: marker("leaderboard.content-frame", app).frame)
        assertDetailContentDoesNotCoverNavigation(list, app, context: true)
        revealOnlyInside(resultRows(app).firstMatch, viewport: list, app)
        assertProfileChromeFits(app)
        capture("18-accessibility-game-history", app)
        app.buttons["ratings.back"].tap()
        chooseTier("classic", app)
        XCTAssertEqual(rating(app, expectsRated: false).label, "Unrated")
    }

    func testRestartAndReplacementExplainTheRatingLoss() {
        let app = launch(seed: false, extra: ["-qaAutoStart", "-qaShowPauseMenu"])
        let restart = app.buttons["in-game-settings.restart"]
        XCTAssertTrue(restart.waitForExistence(timeout: Self.timeout) && restart.isHittable)
        restart.tap()
        assertLossWarning(app, screenshot: "18-restart-loss-disclosure")
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["main-menu.new-game"].tap()
        app.buttons["new-game.start"].tap()
        assertLossWarning(app, screenshot: "19-replacement-loss-disclosure")
    }

    private func launch(seed: Bool, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
            + (seed ? ["-qaSeedPlayerRatings"] : []) + extra
        app.launch()
        return app
    }

    private func openOverview(extra: [String] = []) -> XCUIApplication {
        let app = launch(seed: true, extra: extra)
        enterLeaderboard(app)
        XCTAssertTrue(app.buttons["ratings.player.ratings-preview-alex"].waitForExistence(timeout: Self.timeout))
        return app
    }

    private func enterLeaderboard(_ app: XCUIApplication) {
        let entry = app.buttons["main-menu.leaderboard"]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout) && entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.otherElements["screen.leaderboard"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["leaderboard.scope.players"].isSelected)
        _ = marker("leaderboard.content-frame", app)
    }

    private func openPerson(_ suffix: String, _ app: XCUIApplication) {
        let row = app.buttons["ratings.player.ratings-preview-\(suffix)"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout) && row.isHittable)
        row.tap()
        XCTAssertTrue(element("ratings.profile", in: app).waitForExistence(timeout: Self.timeout))
        _ = rating(app)
    }

    private func rating(_ app: XCUIApplication, expectsRated: Bool = true) -> XCUIElement {
        let value = app.staticTexts["ratings.rating"]
        let ready = NSPredicate { _, _ in
            value.exists && (expectsRated ? !value.label.filter(\.isNumber).isEmpty : value.label == "Unrated")
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)],
                                    timeout: Self.timeout), .completed)
        return value
    }

    private func assertRecord(wins: Int, losses: Int, games: Int, _ app: XCUIApplication) {
        for (id, count) in [("ratings.wins", wins), ("ratings.losses", losses), ("ratings.game-count", games)] {
            let value = element(id, in: app)
            let ready = NSPredicate { _, _ in
                value.exists && value.label.range(of: "(?<![0-9])\(count)(?![0-9])", options: .regularExpression) != nil
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)],
                                        timeout: Self.timeout), .completed,
                           "Expected \(count) in \(id), received \(value.label)")
        }
    }

    private func chooseMode(_ suffix: String, _ app: XCUIApplication) {
        app.buttons["ratings.mode"].tap()
        let cancel = app.buttons["ratings.mode-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: Self.timeout) && cancel.isHittable)
        let option = app.buttons["ratings.mode.\(suffix)"]
        let panel = marker("ratings.mode-frame", app)
        let options = marker("ratings.mode-options-frame", app)
        assertContained(options, in: panel.frame)
        assertContained(cancel, in: panel.frame)
        XCTAssertTrue(cancel.isHittable)
        assertNonoverlapping([options, cancel])
        let cancelFrame = cancel.frame
        revealOnlyInside(option, viewport: options, app)
        assertUnmoved(cancel.frame, cancelFrame)
        XCTAssertTrue(option.isHittable)
        capture("mode-chooser-\(suffix)", app)
        option.tap()
    }

    private func chooseTier(_ tier: String, _ app: XCUIApplication) {
        app.buttons["ratings.tier"].tap()
        let option = app.buttons["ratings.difficulty.\(tier)"]
        XCTAssertTrue(option.waitForExistence(timeout: Self.timeout) && option.isHittable)
        let choices = [app.buttons["ratings.difficulty.classic"], app.buttons["ratings.difficulty.expert"],
                       app.buttons["ratings.tier-cancel"]]
        for choice in choices {
            assertContained(choice, in: app.frame)
            XCTAssertTrue(choice.isHittable)
        }
        assertNonoverlapping(choices)
        capture("tier-chooser-\(tier)", app)
        option.tap()
    }

    private func assertInitialOverviewFits(_ app: XCUIApplication) {
        let rows = Self.people.map { app.buttons["ratings.player.ratings-preview-\($0)"] }
        for row in rows { XCTAssertTrue(row.waitForExistence(timeout: Self.timeout)) }
        capture("standings-initial-before-fit", app)
        assertOverviewChromeFits(app)
        let table = marker("leaderboard.table-frame", app).frame
        for row in rows {
            assertContained(row, in: table)
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
            XCTAssertTrue(row.isHittable, "Every fixture friend must fit without scrolling")
        }
        let opponent = element("ratings.ai-standing", in: app)
        assertContained(opponent, in: table)
        assertNonoverlapping(rows + [opponent])
        let reference = rows[0].frame
        for row in rows.dropFirst() {
            XCTAssertEqual(row.frame.height, reference.height, accuracy: Self.tolerance,
                           "A clipped last-row sliver must not pass as a complete peer row")
            XCTAssertEqual(row.frame.minX, reference.minX, accuracy: Self.tolerance)
            XCTAssertEqual(row.frame.maxX, reference.maxX, accuracy: Self.tolerance)
        }
    }

    private func assertOverviewChromeFits(_ app: XCUIApplication) {
        let viewport = marker("leaderboard.content-frame", app).frame
        for control in pinnedControls(app) { assertContained(control, in: viewport) }
        let table = marker("leaderboard.table-frame", app)
        assertContained(table, in: viewport)
        let overall = element("ratings.overall", in: app)
        assertContained(overall, in: viewport)
        assertContained(element("leaderboard.title", in: app), in: viewport)
        assertNonoverlapping(pinnedControls(app) + [table, overall])
        XCTAssertEqual(app.buttons["ratings.mode"].frame.minY, app.buttons["ratings.tier"].frame.minY,
                       accuracy: Self.tolerance, "The filters must share one row")
    }

    private func assertProfileChromeFits(_ app: XCUIApplication) {
        let bounds = marker("leaderboard.content-frame", app).frame
        let controls = [app.buttons["leaderboard.close"], app.buttons["ratings.back"], app.buttons["ratings.help"],
                        app.buttons["ratings.mode"], app.buttons["ratings.tier"]]
        for control in controls {
            assertContained(control, in: bounds)
            XCTAssertTrue(control.isHittable)
        }
        assertContained(element("leaderboard.title", in: app), in: bounds)
        assertNonoverlapping(controls)
    }

    private func assertPinnedProfileControlsFit(_ app: XCUIApplication) {
        assertProfileChromeFits(app)
        let bounds = marker("leaderboard.content-frame", app).frame
        let games = app.buttons["ratings.games"]
        assertContained(games, in: bounds)
        XCTAssertTrue(games.isHittable)
        let body = marker("ratings.profile-frame", app)
        assertContained(body, in: bounds)
        assertNonoverlapping([body, games])
        assertDetailContentDoesNotCoverNavigation(body, app)
    }

    private func assertUnratedStandings(_ app: XCUIApplication) {
        for person in Self.people {
            assertContains(app.buttons["ratings.player.ratings-preview-\(person)"], ["Unrated"])
        }
        assertContains(element("ratings.ai-standing", in: app), ["Unrated"])
    }

    private func assertEmptyGamesFit(_ app: XCUIApplication, context: [String], screenshot: String) {
        XCTAssertTrue(element("ratings.history", in: app).waitForExistence(timeout: Self.timeout))
        capture(screenshot, app)
        assertProfileChromeFits(app)
        assertContains(element("ratings.record-context", in: app), context)
        let list = marker("ratings.history-frame", app)
        assertContained(list, in: marker("leaderboard.content-frame", app).frame)
        assertDetailContentDoesNotCoverNavigation(list, app, context: true)
        assertContained(app.staticTexts["No games in this competition yet."], in: list.frame)
        XCTAssertFalse(resultRows(app).firstMatch.exists)
    }

    private func assertNormalProfileFits(_ app: XCUIApplication, expectsChart: Bool = true) {
        assertPinnedProfileControlsFit(app)
        let bounds = marker("ratings.profile-frame", app).frame
        for id in ["ratings.rating", "ratings.wins", "ratings.losses", "ratings.win-rate", "ratings.game-count"] {
            assertContained(element(id, in: app), in: bounds)
        }
        if expectsChart { assertContained(element("ratings.chart", in: app), in: bounds) }
    }

    private func assertNonoverlapping(_ elements: [XCUIElement]) {
        for (index, first) in elements.enumerated() {
            for second in elements.dropFirst(index + 1) {
                let overlap = first.frame.intersection(second.frame)
                XCTAssertFalse(overlap.width > Self.tolerance && overlap.height > Self.tolerance,
                               "\(first.identifier) overlaps \(second.identifier): \(overlap)")
            }
        }
    }

    private func assertDetailContentDoesNotCoverNavigation(
        _ body: XCUIElement, _ app: XCUIApplication, context: Bool = false
    ) {
        var items = [body, app.buttons["leaderboard.close"], app.buttons["ratings.back"],
                     app.buttons["ratings.help"], app.buttons["ratings.mode"], app.buttons["ratings.tier"]]
        if context {
            let caption = element("ratings.record-context", in: app)
            assertContained(caption, in: marker("leaderboard.content-frame", app).frame)
            items.append(caption)
        }
        assertNonoverlapping(items)
    }

    private func pinnedControls(_ app: XCUIApplication) -> [XCUIElement] {
        ["leaderboard.close", "leaderboard.account", "ratings.help", "leaderboard.scope.players",
         "leaderboard.scope.ghosts", "ratings.mode", "ratings.tier"].map { app.buttons[$0] }
    }

    private func marker(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let marker = element(id, in: app)
        XCTAssertTrue(marker.waitForExistence(timeout: Self.timeout), "Missing viewport marker \(id)")
        XCTAssertGreaterThan(marker.frame.width, 0)
        XCTAssertGreaterThan(marker.frame.height, 0)
        assertContained(marker, in: app.frame)
        return marker
    }

    private func assertContained(_ element: XCUIElement, in bounds: CGRect) {
        XCTAssertTrue(element.waitForExistence(timeout: Self.timeout), element.identifier)
        XCTAssertGreaterThan(element.frame.width, 0, element.identifier)
        XCTAssertGreaterThan(element.frame.height, 0, element.identifier)
        XCTAssertTrue(bounds.insetBy(dx: -Self.tolerance, dy: -Self.tolerance).contains(element.frame),
                      "\(element.identifier) is clipped: \(element.frame), viewport \(bounds)")
    }

    /// Scrolling is permitted only inside a deliberate bounded content area;
    /// it must never rescue a failed initial-overview assertion.
    private func revealOnlyInside(_ element: XCUIElement, viewport: XCUIElement, _ app: XCUIApplication) {
        let bounds = viewport.frame
        for _ in 0..<6 {
            if element.exists {
                XCTAssertLessThanOrEqual(element.frame.height, bounds.height + Self.tolerance)
                if bounds.insetBy(dx: -Self.tolerance, dy: -Self.tolerance).contains(element.frame) { return }
            }
            let upwards = !element.exists || element.frame.maxY > bounds.maxY
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.8 : 0.2))
            let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.2 : 0.8))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        assertContained(element, in: bounds)
    }

    private func assertUnmoved(_ actual: CGRect, _ expected: CGRect) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: Self.tolerance)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: Self.tolerance)
        XCTAssertEqual(actual.width, expected.width, accuracy: Self.tolerance)
        XCTAssertEqual(actual.height, expected.height, accuracy: Self.tolerance)
    }

    private func assertResult(won: Bool) {
        let app = launch(seed: true, extra: ["-qaAutoStart", won ? "-qaShowRatingWin" : "-qaShowRatingLoss"])
        let receipt = app.buttons["game-over.rating"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10))
        XCTAssertTrue(receipt.label.contains(won ? "+" : "−"), receipt.label)
        capture(won ? "13-win-rating-receipt" : "14-loss-rating-receipt", app)
        receipt.tap()
        XCTAssertTrue(element("ratings.profile", in: app).waitForExistence(timeout: Self.timeout))
        _ = rating(app)
        assertContains(app.buttons["ratings.tier"], ["Expert"])
        assertProfileChromeFits(app)
        if won { chooseMode("naval.standard", app) }
        app.buttons["leaderboard.close"].tap()
        XCTAssertTrue(app.buttons["game-over.main-menu"].waitForExistence(timeout: Self.timeout))
        app.buttons["game-over.main-menu"].tap()
        XCTAssertFalse(app.buttons["main-menu.ratings"].exists)
        enterLeaderboard(app)
        if won { assertContains(app.buttons["ratings.mode"], ["Voyages"]) }
    }

    private func assertLossWarning(_ app: XCUIApplication, screenshot: String) {
        let warning = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'count as a loss'")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: Self.timeout))
        capture(screenshot, app)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func resultRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'ratings.result.'"))
    }

    private func assertContains(_ element: XCUIElement, _ fragments: [String]) {
        let ready = NSPredicate { _, _ in
            element.exists && fragments.allSatisfy { element.label.contains($0) }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)],
                                    timeout: Self.timeout), .completed, element.label)
    }

    private func requireViewport(_ expected: CGSize, _ app: XCUIApplication) throws {
        guard abs(app.frame.width - expected.width) <= Self.tolerance,
              abs(app.frame.height - expected.height) <= Self.tolerance else {
            throw XCTSkip("Requires a real \(Int(expected.width))×\(Int(expected.height))-point destination; "
                          + "this destination is \(app.frame.size)")
        }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(name)-\(Int(app.frame.width))x\(Int(app.frame.height))"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
