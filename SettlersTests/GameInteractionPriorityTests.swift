import Testing
@testable import Settlers

@Suite("Game interaction priority")
struct GameInteractionPriorityTests {
    private static let rankedSurfaces: [GameInteractionSurface] = [
        .handoff,
        .recoveryFailure,
        .mandatoryDiscard,
        .mandatoryBoardDecision,
        .privateReceipt,
        .optionalBoardDecision,
        .incomingTrade
    ]

    @Test func everyCombinationSelectsItsHighestPriorityClaim() {
        for mask in 0..<(1 << Self.rankedSurfaces.count) {
            let active = Self.activeSurfaces(for: mask)
            let expected = Self.rankedSurfaces.first(where: active.contains) ?? .ordinaryActions
            let result = GameInteractionPriority.resolve(Self.input(for: active))

            #expect(result.winner == expected, "mask \(mask) resolved to \(result.winner), expected \(expected)")
            #expect(!result.isSettingsCoverPresented)
            #expect(result.blocksBotProgress == (expected != .ordinaryActions))
        }
    }

    @Test func everyAdjacentCollisionChoosesTheHigherLevel() {
        for index in 0..<(Self.rankedSurfaces.count - 1) {
            let higher = Self.rankedSurfaces[index]
            let lower = Self.rankedSurfaces[index + 1]
            let result = GameInteractionPriority.resolve(Self.input(for: [higher, lower]))

            #expect(result.winner == higher, "\(higher) must outrank adjacent \(lower)")
        }

        let ordinaryCollision = GameInteractionPriority.resolve(
            Self.input(for: [.incomingTrade, .ordinaryActions])
        )
        #expect(ordinaryCollision.winner == .incomingTrade)
    }

    @Test func settingsCoversWithoutReorderingOrErasingEveryUnderlyingState() {
        for mask in 0..<(1 << Self.rankedSurfaces.count) {
            let active = Self.activeSurfaces(for: mask)
            let uncovered = GameInteractionPriority.resolve(Self.input(for: active))
            let covered = GameInteractionPriority.resolve(Self.input(for: active, settings: true))

            #expect(covered.winner == uncovered.winner,
                    "Settings changed the underlying winner for mask \(mask)")
            #expect(!uncovered.isSettingsCoverPresented)
            #expect(covered.isSettingsCoverPresented)
            #expect(covered.blocksBotProgress)
        }
    }

    @Test func everySurfaceWinsWhenItIsTheOnlyClaim() {
        for surface in GameInteractionSurface.allCases {
            let result = GameInteractionPriority.resolve(Self.input(for: [surface]))
            #expect(result.winner == surface, "\(surface) was omitted from the resolver")
        }
    }

    private static func activeSurfaces(for mask: Int) -> Set<GameInteractionSurface> {
        Set(rankedSurfaces.enumerated().compactMap { index, surface in
            mask & (1 << index) == 0 ? nil : surface
        })
    }

    private static func input(
        for active: Set<GameInteractionSurface>,
        settings: Bool = false
    ) -> GameInteractionPriorityInput {
        GameInteractionPriorityInput(
            needsHandoff: active.contains(.handoff),
            hasRecoveryFailure: active.contains(.recoveryFailure),
            hasMandatoryDiscard: active.contains(.mandatoryDiscard),
            hasMandatoryBoardDecision: active.contains(.mandatoryBoardDecision),
            hasPrivateReceipt: active.contains(.privateReceipt),
            hasOptionalBoardDecision: active.contains(.optionalBoardDecision),
            hasIncomingTrade: active.contains(.incomingTrade),
            isSettingsPresented: settings
        )
    }
}
