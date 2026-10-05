import SwiftUI
import Testing
import UIKit
import CatanEngine
@testable import Settlers

@MainActor
struct DevelopmentCardDisplayTests {
    @Test func plentyUsesPaintedPineInsteadOfNeonGreen() {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(UIColor(DevCardStyle.color(for: .yearOfPlenty)).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(green < 0.45, "The old semantic green is much brighter than the painted palette")
        #expect(DevCardStyle.icon(for: .yearOfPlenty) != "sparkles")
    }

    @Test func mixedStackReportsReadyOnlyWhenEngineAllowsPlay() {
        let playable = item(status: .playable)
        #expect(DevCardDisplay.inventoryBadge(playable) == "1 READY · 1 NEW")
        #expect(DevCardDisplay.handBadgeStatus(playable) == "1R · 1N")
        let blocked = item(status: .alreadyPlayedThisTurn)
        #expect(DevCardDisplay.inventoryBadge(blocked) == "1 HELD · 1 NEW")
        #expect(DevCardDisplay.handBadgeStatus(blocked) == "1H · 1N")
        #expect(DevCardDisplay.accessibilityValue(blocked).contains("One card already played"))
        #expect(DevCardDisplay.accessibilityValue(blocked) == "1 held, 1 new. One card already played")
    }

    @Test func everyRestrictionRemainsInspectableAndHasAReason() {
        let restrictions: [DevCardPlayStatus] = [
            .notOwned, .boughtThisTurn, .alreadyPlayedThisTurn, .waitingForYourTurn,
            .resolveRequiredAction, .noLegalChoices, .gameOver,
        ]
        for status in restrictions {
            let card = item(status: status)
            #expect(!DevCardDisplay.inventoryBadge(card).contains("READY"))
            #expect(DevCardDisplay.accessibilityValue(card).contains(DevCardStyle.statusTitle(for: status)))
        }
    }

    @Test func passivePointsAndNewOnlyStacksKeepTheirMeaning() {
        let point = DevCardInventoryItem(type: .victoryPoint, held: 2, boughtThisTurn: 1, status: .passiveVictoryPoint)
        #expect(DevCardDisplay.inventoryBadge(point) == "PASSIVE")
        #expect(DevCardDisplay.accessibilityValue(point).contains("Counts automatically"))
        let new = DevCardInventoryItem(type: .monopoly, held: 1, boughtThisTurn: 1, status: .boughtThisTurn)
        #expect(DevCardDisplay.inventoryBadge(new) == "1 NEW")
    }

    private func item(status: DevCardPlayStatus) -> DevCardInventoryItem {
        DevCardInventoryItem(type: .roadBuilding, held: 2, boughtThisTurn: 1, status: status)
    }
}
