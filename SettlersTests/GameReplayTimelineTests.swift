import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

/// The replay screen is only as honest as this type: every position it shows
/// is reconstructed here, not stored, so a wrong frame is a wrong claim about
/// a game the player actually played.
@Suite struct GameReplayTimelineTests {
    @Test func timelineHoldsOneFrameForTheOpeningPositionAndOnePerMove() throws {
        let recording = try makeRecording(moves: 12)

        let timeline = GameReplayTimeline(detail: recording)

        #expect(timeline.frames.count == 13)
        #expect(timeline.lastIndex == 12)
        #expect(timeline.frames[0].actor == nil)
        #expect(timeline.frames[0].headline == "Opening position")
        #expect(timeline.truncation == nil)
    }

    /// The whole point of scrubbing: frame *n* must be the board as it stood
    /// after move *n*, not the final board or the opening one.
    @Test func eachFrameIsTheStateThatMoveProduced() throws {
        let recording = try makeRecording(moves: 20)

        let timeline = GameReplayTimeline(detail: recording)

        var expected = recording.initialState
        for (offset, event) in recording.events.enumerated() {
            try RulesEngine.apply(event.move, by: event.player, to: &expected)
            #expect(timeline.frames[offset + 1].state == expected)
            #expect(timeline.frames[offset + 1].actor == event.player)
        }
    }

    @Test func scoresAreRecordedPerSeatAndGrowAsTheGameIsPlayed() throws {
        let recording = try makeRecording(moves: 30)

        let timeline = GameReplayTimeline(detail: recording)

        #expect(timeline.frames[0].scores == [0, 0, 0, 0])
        let last = try #require(timeline.frames.last)
        #expect(last.scores.count == 4)
        #expect(last.scores.reduce(0, +) > 0)
        for (seat, points) in last.scores.enumerated() {
            #expect(points == last.state.victoryPoints(for: PlayerID(index: seat)))
        }
    }

    /// A recording written by an engine this build cannot replay must keep the
    /// part it *can* reconstruct and say where it stopped, rather than either
    /// refusing the game or ending silently on a half-played board.
    @Test func anUnreplayableMoveTruncatesTheTimelineAndIsReported() throws {
        let recording = try makeRecording(moves: 8)
        // Ending a turn during the opening placements is rejected by today's
        // engine (`.wrongPhase`), which is exactly the shape of a move a
        // recording from another rules version could carry: decodes fine,
        // cannot be applied here.
        let poisoned = GameLogDetail(
            initialState: recording.initialState,
            summary: recording.summary,
            roster: recording.roster,
            events: Array(recording.events.prefix(4))
                + [GameLogEvent(timestamp: Date(), player: PlayerID(index: 0), move: .endTurn)]
                + recording.events.dropFirst(4))

        let timeline = GameReplayTimeline(detail: poisoned)

        #expect(timeline.frames.count == 5)
        let truncation = try #require(timeline.truncation)
        #expect(truncation.contains("move 4"))
    }

    /// Names and civilizations must come from the recording, never from the
    /// global assignment describing whatever match is loaded now.
    @Test func identitiesComeFromTheArchivedRoster() throws {
        CivilizationAssignment.current = Array(Civilization.allCases.suffix(4))
        CivilizationAssignment.humanSeat = PlayerID(index: 3)
        let recording = try makeRecording(moves: 4)

        let timeline = GameReplayTimeline(detail: recording)

        let seatZero = timeline.identity(for: PlayerID(index: 0))
        #expect(seatZero.displayName == "Archivist")
        #expect(seatZero.controller == .human)
        #expect(seatZero.civilization.displayName == recording.roster.civilizations[0])
        #expect(timeline.identity(for: PlayerID(index: 1)).controller == .computer)
    }

    @Test func narrationNamesTheSeatAndWhatTheRulesDid() throws {
        let roster = Self.roster
        let seat = PlayerID(index: 1)

        #expect(GameReplayNarrator.headline(for: [.rolled(seat, total: 8)], move: .rollDice,
                                            actor: seat, roster: roster) == "Sparta rolled 8")
        #expect(GameReplayNarrator.headline(
            for: [.playedMonopoly(seat, resource: .ore, gained: 3)],
            move: .playMonopoly(.ore), actor: seat, roster: roster)
            == "Sparta monopolised ore, taking 3")
        #expect(GameReplayNarrator.headline(
            for: [.movedRobber(seat, from: PlayerID(index: 0), stealing: .wool)],
            move: .moveRobber(HexCoordinate(q: 0, r: 0), stealFrom: PlayerID(index: 0)),
            actor: seat, roster: roster)
            == "Sparta moved the robber and took wool from Archivist")
    }

    /// `[Resource: Int]` iterates in a per-process order, so a narration built
    /// from one would read differently on two launches of the same recording.
    @Test func resourceListsNarrateInAStableOrder() {
        let seat = PlayerID(index: 1)
        let table: [Resource: Int] = [.wool: 1, .brick: 2, .ore: 1, .grain: 3, .lumber: 1]
        let line = GameReplayNarrator.headline(
            for: [.tradedWithBank(seat, gave: table, got: [.ore: 1])],
            move: .bankTrade(give: table, get: [.ore: 1]), actor: seat, roster: Self.roster)

        #expect(line == "Sparta traded 2 brick, 1 lumber, 1 ore, 3 grain, 1 wool to the bank for 1 ore")
    }

    /// A move the rules accept without announcing anything still has to read
    /// as something, or the caption under the board goes blank mid-replay.
    @Test func aMoveWithNoEventsStillNarrates() {
        let seat = PlayerID(index: 0)
        let line = GameReplayNarrator.headline(for: [], move: .respondToTrade(offerID: UUID(), accept: true),
                                               actor: seat, roster: Self.roster)

        #expect(line == "Archivist accepted a trade")
    }

    // MARK: - Fixtures

    private static let roster = GameLogStore.SeatRoster(
        humanSeats: [PlayerID(index: 0)],
        humanNames: [0: "Archivist"],
        botProfileNames: [1: "Sparta", 2: "Carthage", 3: "Thebes"],
        botPersonalities: [1: "balanced", 2: "balanced", 3: "balanced"],
        civilizations: Dictionary(uniqueKeysWithValues: (0..<4).map {
            ($0, Civilization.allCases[$0].displayName)
        }))

    /// A real recording written by the production writer and read back through
    /// the production reader, so these tests cannot pass against a shape the
    /// app never produces.
    private func makeRecording(moves: Int) throws -> GameLogDetail {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameReplayTimelineTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameLogStore(directoryURL: directory, maxKeptLogs: 8)

        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 41)
        let id = try store.startNewGame(initialState: state, roster: Self.roster)
        for _ in 0..<moves {
            guard let seat = state.phase.awaitingSeatIndex.map({ PlayerID(index: $0) }),
                  let move = RulesEngine.legalMoves(for: state, seat: seat).first else { break }
            try RulesEngine.apply(move, by: seat, to: &state)
            try store.appendMove(gameID: id, player: seat, move: move)
        }
        let file = try #require(try store.logFiles().first)
        return try store.detail(for: file)
    }
}
