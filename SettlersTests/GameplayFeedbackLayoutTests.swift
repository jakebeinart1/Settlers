import XCTest
import SwiftUI
import CatanEngine
@testable import Settlers

/// Both HUDs and the reserved information slot must retain their combined
/// height at 375/402pt. Combined with the real SE board-frame tap assertion,
/// this catches a feedback badge stealing space from the board at either width.
@MainActor
final class GameplayFeedbackLayoutTests: XCTestCase {
    func testFeedbackDoesNotResizeEitherHUDAt375And402Points() throws {
        for width in [375.0, 402.0] {
            let plain = try render(width: width, showsFeedback: false)
            let noticed = try render(width: width, showsFeedback: true)
            XCTAssertEqual(plain.width, noticed.width)
            XCTAssertEqual(plain.height, noticed.height, "HUD height changed at \(width)pt")
            let screenshot = XCTAttachment(image: UIImage(cgImage: noticed))
            screenshot.name = "Public feedback HUD at \(Int(width)) points"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    private func render(width: CGFloat, showsFeedback: Bool) throws -> CGImage {
        let human = PlayerID(index: 0)
        let rival = PlayerID(index: 1)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 32)
        state.longestRoadPlayer = human
        state.phase = .mainTurn(playerIndex: 0)
        let feedback = GameplayFeedback(kind: .longestRoad(previous: rival, holder: human),
                                        pointChanges: [human: 2, rival: -2], occurredAt: Date())
        let view = VStack(spacing: 0) {
            BotHUDRow(state: state, human: human, playerIdentity: identity,
                      pointChanges: showsFeedback ? feedback.pointChanges : [:])
                .padding(.horizontal, 12)
            Group {
                if showsFeedback {
                    GameplayFeedbackView(feedback: feedback, playerIdentity: identity)
                } else { Color.clear }
            }.frame(height: 20)
            HumanPlayerPanel(state: state, human: human, playerIdentity: identity,
                             onOpenDevCards: { _ in }, pointChange: showsFeedback ? 2 : 0)
                .padding(.horizontal, 12)
        }
        .frame(width: width)
        .background(CatanTheme.waterBackground)
        .dynamicTypeSize(.large)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private func identity(_ seat: PlayerID) -> PlayerIdentity {
        PlayerIdentity(seat: seat, displayName: seat.index == 0 ? "Alex" : "Alexander",
                       civilization: Civilization.allCases[seat.index],
                       controller: seat.index == 0 ? .human : .computer)
    }
}
