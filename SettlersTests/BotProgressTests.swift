import Foundation
import Testing
import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct BotProgressTests {
    /// Reaching the barrier from the main actor proves responsiveness without
    /// a subsecond performance threshold. Every worker has a finite fallback.
    @Test func aSlowBotDoesNotBlockTheMainRunLoop() async throws {
        let fixture = try CheckpointModelFixture()
        let model = makeBotStart(fixture)
        let gate = try installPolicy(in: model, seat: 0)
        defer {
            model.isBlockingSurfaceOpen = true
            gate.release()
        }
        let before = model.session.checkpoint
        let runner = Task { await model.runBotTurnIfNeeded() }
        try await waitUntil { gate.hasEntered }
        model.isBlockingSurfaceOpen = true
        gate.release()
        await runner.value
        #expect(!gate.didExpire, "The UI must reach the blocked worker before its safety timeout")
        #expect(model.session.checkpoint == before)
        #expect(fixture.makeModel().session.checkpoint == before)
    }

    @Test(arguments: [false, true])
    func readerReopeningDoesNotLoseTheResumeKick(reopenBeforeDrain: Bool) async throws {
        let fixture = try CheckpointModelFixture()
        let model = makeBotStart(fixture)
        let gate = try installPolicy(in: model, seat: 0)
        defer {
            model.isBlockingSurfaceOpen = true
            gate.release()
        }
        let before = model.session.checkpoint
        let runner = Task { await model.runBotTurnIfNeeded() }
        try await waitUntil { gate.hasEntered }
        model.isBlockingSurfaceOpen = true
        #expect(model.session.checkpoint == before)
        if reopenBeforeDrain { model.isBlockingSurfaceOpen = false }
        gate.release()
        await runner.value
        if !reopenBeforeDrain {
            #expect(model.session.checkpoint == before)
            model.isBlockingSurfaceOpen = false
        }
        try await expectFirstHumanTurn(model, fixture: fixture)
        #expect(!gate.didExpire)
    }

    @Test(arguments: [false, true])
    func foregroundKickSurvivesAnOutstandingWorker(resumeBeforeDrain: Bool) async throws {
        let fixture = try CheckpointModelFixture()
        let model = makeBotStart(fixture)
        let gate = try installPolicy(in: model, seat: 0)
        defer {
            model.isBlockingSurfaceOpen = true
            gate.release()
        }
        let before = model.session.checkpoint
        let runner = Task { await model.runBotTurnIfNeeded() }
        try await waitUntil { gate.hasEntered }
        model.appWillResignActive()
        if resumeBeforeDrain {
            model.appDidBecomeActive()
            await model.runBotTurnIfNeeded() // ContentView's foreground kick.
        }
        gate.release()
        await runner.value
        if !resumeBeforeDrain {
            #expect(model.session.checkpoint == before)
            model.appDidBecomeActive()
            await model.runBotTurnIfNeeded()
        }
        try await expectFirstHumanTurn(model, fixture: fixture)
        #expect(!gate.didExpire)
    }

    /// Cancellation fences publication; it need not forcibly interrupt the
    /// synchronous policy. The replacement kick may wait for this finite drain.
    @Test func cancelledVisibleRunnerRestartsAfterItsWorkerDrains() async throws {
        let fixture = try CheckpointModelFixture()
        let model = makeBotStart(fixture)
        let gate = try installPolicy(in: model, seat: 0)
        defer {
            model.isBlockingSurfaceOpen = true
            gate.release()
        }
        let before = model.session.checkpoint
        let runner = Task { await model.runBotTurnIfNeeded() }
        try await waitUntil { gate.hasEntered }
        runner.cancel()
        await model.runBotTurnIfNeeded()
        #expect(model.session.checkpoint == before)
        gate.release()
        await runner.value
        try await expectFirstHumanTurn(model, fixture: fixture)
        #expect(!gate.didExpire)
    }

    @Test(arguments: [false, true])
    func replacementFencesObsoleteSuccessAndFailure(rejectOldApplication: Bool) async throws {
        let fixture = try CheckpointModelFixture()
        let model = makeBotStart(fixture)
        let oldGate = try installObsoletePolicy(in: model, rejectApplication: rejectOldApplication)
        let newGate = FinitePolicyBarrier()
        defer {
            model.isBlockingSurfaceOpen = true
            oldGate.release()
            newGate.release()
        }
        let oldMatchID = model.currentGameLogID
        let runner = Task { await model.runBotTurnIfNeeded() }
        try await waitUntil { oldGate.hasEntered }
        var replacement = botFirstSetup(fixture)
        replacement.victoryPointTarget = 12
        model.startNewGame(setup: replacement)
        _ = try installPolicy(in: model, seat: 0, gate: newGate)
        let replacementCursor = model.session.checkpoint
        await model.runBotTurnIfNeeded()
        #expect(!newGate.hasEntered, "Replacement work may wait for the one outstanding worker to drain")
        oldGate.release()
        await runner.value
        #expect(!isFailed(model), "An obsolete worker error must not poison the replacement match")
        try await waitUntil { newGate.hasEntered || isFailed(model) }
        try #require(newGate.hasEntered, "The replacement worker must start after obsolete work drains")
        #expect(model.currentGameLogID != oldMatchID)
        #expect(model.session.checkpoint == replacementCursor)
        #expect(fixture.makeModel().session.checkpoint == replacementCursor)
        #expect(model.checkpointDocument?.activeMatch?.moves.isEmpty == true)
        newGate.release()
        try await expectFirstHumanTurn(model, fixture: fixture)
        #expect(!oldGate.didExpire && !newGate.didExpire)
    }

    @Test func skipCancelsViewingWaitButStopsAtHumanSetup() async throws {
        let fixture = try CheckpointModelFixture()
        let model = makeBotStart(fixture)
        let gate = try installPolicy(in: model, seat: 0)
        defer {
            model.isBlockingSurfaceOpen = true
            gate.release()
        }
        model.lastBotActionAt = nil
        let runner = Task { await model.runBotTurnIfNeeded() }
        try await waitUntil { model.botPacingWait != nil }
        let viewingWait = try #require(model.botPacingWait)
        model.skipBotPauses()
        #expect(viewingWait.isCancelled, "Skip must cancel the real wait, not just change its label")
        try await waitUntil { gate.hasEntered }
        gate.release()
        await runner.value
        try await expectFirstHumanTurn(model, fixture: fixture)
        let humanCursor = model.session.checkpoint
        model.skipBotPauses()
        await model.runBotTurnIfNeeded()
        #expect(model.session.checkpoint == humanCursor)
        #expect(model.boardDecisionPresentation?.intent == .initialSettlement)
        #expect(!model.skipsBotPacing, "Skip belongs to this CPU run, not the next human turn")
        #expect(!gate.didExpire)
    }

    /// An empty-board baseline also proves that no eligible victim is not a
    /// robber deadlock: a destination alone must be confirmable after discards.
    @Test(arguments: [false, true])
    func sevenDrainsBotDiscardsWithoutSkippingHumanRequirements(humanMustDiscard: Bool) async throws {
        let fixture = try CheckpointModelFixture()
        let model = try makeSevenPosition(fixture, humanMustDiscard: humanMustDiscard)
        defer { model.isBlockingSurfaceOpen = true }
        if humanMustDiscard {
            model.isBlockingSurfaceOpen = true
            let before = model.session.checkpoint
            model.skipBotPauses()
            await model.runBotTurnIfNeeded()
            #expect(model.session.checkpoint == before)
            #expect(model.currentDiscardObligation?.requiredCount == 4)
            try model.apply(.discard([.brick: 4]))
            model.isBlockingSurfaceOpen = false
        }
        model.skipBotPauses()
        try await waitUntil { model.state.phase == .movingRobber(playerIndex: 0) && !model.isProcessingBotTurns }
        #expect(model.state.players[1].resources[.grain] == 5)
        #expect(model.state.players[2].resources[.ore] == 5)
        #expect(model.state.players[0].resources[.brick, default: 0] == (humanMustDiscard ? 4 : 0))
        #expect(model.checkpointDocument?.activeMatch?.moves.count == (humanMustDiscard ? 3 : 2))
        #expect(model.boardDecisionPresentation?.intent == .robberAfterSeven)
        let beforeRobber = model.session.checkpoint
        model.skipBotPauses()
        await model.runBotTurnIfNeeded()
        #expect(model.session.checkpoint == beforeRobber)
        let tile = try #require(model.boardDecisionPresentation?.legalTiles.first)
        #expect(model.selectBoardTarget(.tile(tile)))
        #expect(model.confirmBoardDecision())
        #expect(model.state.phase == .mainTurn(playerIndex: 0))
        #expect(fixture.makeModel().state == model.state)
    }

    @Test func humanDiscardDuringBotWorkCannotBeRolledBack() async throws {
        let fixture = try CheckpointModelFixture()
        let model = try makeSevenPosition(fixture, humanMustDiscard: true)
        let gate = try installPolicy(in: model, seat: 1)
        defer {
            model.isBlockingSurfaceOpen = true
            gate.release()
        }
        let runner = Task { await model.runBotTurnIfNeeded() }
        try await waitUntil { gate.hasEntered }
        let generation = model.gameGeneration
        let revision = model.checkpointDocument?.revision
        try model.apply(.discard([.brick: 4]))
        #expect(model.gameGeneration == generation)
        #expect(model.checkpointDocument?.revision != revision)
        model.skipBotPauses()
        gate.release()
        await runner.value
        try await waitUntil { model.state.phase == .movingRobber(playerIndex: 0) && !model.isProcessingBotTurns }
        #expect(model.state.players[0].resources[.brick] == 4)
        #expect(model.state.players[1].resources[.grain] == 5)
        #expect(model.state.players[2].resources[.ore] == 5)
        #expect(model.checkpointDocument?.activeMatch?.moves.count == 3)
        #expect(fixture.makeModel().state == model.state)
        #expect(!gate.didExpire)
    }

    private func botFirstSetup(_ fixture: CheckpointModelFixture) -> MatchSetup {
        var setup = fixture.setup
        setup.seats[0].isHuman = false
        setup.seats[0].name = ""
        setup.seats[1].isHuman = true
        setup.seats[1].name = "Alex"
        return setup
    }

    private func makeBotStart(_ fixture: CheckpointModelFixture) -> GameViewModel {
        let model = fixture.makeModel()
        model.startNewGame(setup: botFirstSetup(fixture))
        model.lastBotActionAt = .distantPast
        return model
    }

    @discardableResult
    private func installPolicy(in model: GameViewModel, seat: Int,
                               gate: FinitePolicyBarrier = FinitePolicyBarrier()) throws -> FinitePolicyBarrier {
        let actor = PlayerID(index: seat)
        let id = try #require(model.session.policies[actor]?.id)
        model.session.policies[actor] = BarrierBoundaryPolicy(id: id, gate: gate)
        return gate
    }

    /// Fault injection only: permuting the in-memory player array makes a
    /// mask-valid setup move throw notYourTurn during application, instead of
    /// trapping in policy validation. No corrupt position is written to disk.
    private func installObsoletePolicy(in model: GameViewModel, rejectApplication: Bool) throws -> FinitePolicyBarrier {
        if rejectApplication {
            var rejected = model.state
            rejected.players.swapAt(0, 2)
            let move = try #require(RulesEngine.legalMoves(for: rejected).first)
            var application = rejected
            #expect(throws: MoveError.notYourTurn) {
                try RulesEngine.apply(move, by: rejected.players[0].id, to: &application)
            }
            model.session.replace(state: rejected)
            return try installPolicy(in: model, seat: 2)
        }
        return try installPolicy(in: model, seat: 0)
    }

    private func makeSevenPosition(_ fixture: CheckpointModelFixture, humanMustDiscard: Bool) throws -> GameViewModel {
        let model = fixture.makeModel()
        var position = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7, playerCount: 3)
        position.phase = .rollDice(playerIndex: 0)
        position.players[0].resources = humanMustDiscard ? [.brick: 8] : [:]
        position.players[1].resources = [.grain: 9]
        position.players[2].resources = [.ore: 9]
        position.bank[.brick, default: 0] -= humanMustDiscard ? 8 : 0
        position.bank[.grain, default: 0] -= 9
        position.bank[.ore, default: 0] -= 9
        MainPhase.rollDice(state: &position, roll: 7)
        model.replaceStateForTesting(position, humanSeat: PlayerID(index: 0))
        for seat in [1, 2] {
            let gate = FinitePolicyBarrier()
            gate.release()
            try installPolicy(in: model, seat: seat, gate: gate)
        }
        model.lastBotActionAt = .distantPast
        return model
    }

    private func expectFirstHumanTurn(_ model: GameViewModel, fixture: CheckpointModelFixture) async throws {
        try await waitUntil { model.state.phase == .setupForward(playerIndex: 1) && !model.isProcessingBotTurns }
        #expect(model.state.players[0].settlements.count == 1)
        #expect(model.state.players[0].roads.count == 1)
        #expect(model.state.players[1].settlements.isEmpty)
        #expect(model.checkpointDocument?.activeMatch?.moves.count == 2)
        #expect(fixture.makeModel().session.checkpoint == model.session.checkpoint)
        #expect(!isFailed(model))
    }

    private func isFailed(_ model: GameViewModel) -> Bool {
        if case .failed = model.botTurnProgress { return true }
        return false
    }

    /// A safety deadline is not a performance assertion. Missing kicks fail
    /// rather than leaving an unbounded test awaiting a runner forever.
    private func waitUntil(_ reached: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(FinitePolicyBarrier.timeout + 2)
        while !reached(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(reached(), "Lifecycle boundary was not reached before the safety deadline")
    }
}

private struct BarrierBoundaryPolicy: Policy {
    let id: String
    let gate: FinitePolicyBarrier

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        gate.waitOnce()
        _ = rng.next()
        return observation.legalMoves[0]
    }
}

/// Policy is synchronous, so this bounded thread-safe barrier controls its
/// system boundary. All mutable fields are protected by the condition lock;
/// release-on-cleanup plus expiry prevents an orphaned, uncooperative worker.
private final class FinitePolicyBarrier: @unchecked Sendable {
    static let timeout: TimeInterval = 10
    private let condition = NSCondition()
    private var entered = false
    private var released = false
    private var expired = false

    var hasEntered: Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }

    var didExpire: Bool {
        condition.lock()
        defer { condition.unlock() }
        return expired
    }

    func waitOnce() {
        condition.lock()
        defer { condition.unlock() }
        guard !entered else { return }
        entered = true
        let deadline = Date().addingTimeInterval(Self.timeout)
        while !released {
            if !condition.wait(until: deadline) {
                expired = true
                return
            }
        }
    }

    func release() {
        condition.lock()
        defer { condition.unlock() }
        released = true
        condition.broadcast()
    }
}
