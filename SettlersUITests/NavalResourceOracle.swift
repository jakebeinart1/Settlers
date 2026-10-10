import XCTest

/// A blocking harvest deliberately hides the underlying game HUD from VoiceOver.
/// Read its visible resource rows until collection dismisses that modal.
@MainActor
enum NavalResourceOracle {
    /// A visible part of a tall resource card does not imply that its quantity
    /// control is visible. Scroll toward the control's actual projected frame.
    static func revealHarvestControl(_ element: XCUIElement, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, "Missing harvest control: \(element.identifier)", file: file, line: line)
        let scroll = app.scrollViews["naval.resource.scroll"]
        for _ in 0..<10 {
            if element.isHittable && scroll.frame.contains(element.frame) { return }
            if element.frame.midY < scroll.frame.midY { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "The harvest control cannot be reached: \(element.identifier)", file: file, line: line)
        XCTAssertTrue(scroll.frame.contains(element.frame), "The whole harvest control must be visible", file: file, line: line)
    }

    static func ownedCount(_ resource: String, in app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) -> Int {
        let row = app.buttons["naval.resource.\(resource)"]
        if row.exists {
            let value = row.value as? String ?? ""
            let fields = value.components(separatedBy: "You have ")
            guard fields.count == 2, let owned = fields.last?.components(separatedBy: ". Bank ").first,
                  let count = Int(owned), count >= 0 else {
                XCTFail("Missing or malformed visible harvest holdings for \(resource): \(value)", file: file, line: line)
                return -1
            }
            return count
        }
        let hud = app.otherElements["human-resource.\(resource)"]
        guard hud.exists, let value = hud.value as? String, let count = Int(value), count >= 0 else {
            XCTFail("Neither a harvest row nor visible HUD holdings exists for \(resource)", file: file, line: line)
            return -1
        }
        return count
    }
}
