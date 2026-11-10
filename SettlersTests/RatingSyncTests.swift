import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

/// Fast real setup/replay and file-backed sync checks. Unfinished matches
/// are explicit forfeits, not synthetic claims that an ordinary game ended.
@MainActor @Suite(.serialized) struct RatingSyncTests {
    private let expert = RatingPool(mode: .classic, difficulty: .expert)
    private let naval = RatingPool(mode: .naval, difficulty: .classic)

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RatingSyncTests.\(UUID().uuidString)")
    }

    private func setup(_ pool: RatingPool) -> MatchSetup {
        var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: .greece)
        setup.mode = pool.mode
        setup.variant = pool.variant
        setup.difficulty = pool.difficulty
        setup.victoryPointTarget = MatchSetup.newGameVictoryPointTargets(for: 4, mode: pool.mode)[0]
        setup.randomizeSeatOrder = false
        return setup
    }

    private func model(_ device: LiveSyncTests.Device, defaults: UserDefaults) -> GameViewModel {
        device.makeModel(defaults: defaults)
    }

    private func pendingMatch(on device: LiveSyncTests.Device, pool: RatingPool) throws -> SharedMatch {
        let suite = "RatingSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = model(device, defaults: defaults)
        model.startNewGame(setup: setup(pool))
        return try #require(model.abandonedRatedMatch())
    }

    private func sync(_ device: LiveSyncTests.Device, cloud: LiveSyncTests.FakeCloud,
                      user: String, name: String) async throws {
        let status = await device.sync(cloud, as: user, name: name)
        guard case .online = status else { throw status }
    }

    @Test(arguments: RatingPool.available)
    func everyModeAndTierVerifiesItsActualSavedContract(pool: RatingPool) throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let shared = try pendingMatch(on: device, pool: pool)
        let record = try shared.verified(owner: device.me)
        #expect(record.ratingPool == pool)
        #expect(record.abandoned == true)
        #expect(record.seats.filter { $0.stats.won }.count == 1)
        #expect(PlayerRatings(records: [record]).standing(for: device.me, in: pool).losses == 1)
    }

    @Test func payloadCannotClaimAnotherModeOrDifficulty() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        var shared = try pendingMatch(on: device, pool: naval)
        shared.ratingPool = expert
        #expect(throws: SharedMatch.Rejection.invalidRatingPool) { try shared.verified(owner: device.me) }
        shared.ratingPool = RatingPool(mode: .naval, difficulty: .expert)
        #expect(throws: SharedMatch.Rejection.invalidRatingPool) { try shared.verified(owner: device.me) }
    }

    @Test func downloadedReplayRejectsAnActorOutsideTheTable() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        let invalidSeat = PlayerID(index: state.players.count)
        state.phase = .rollDice(playerIndex: invalidSeat.index)
        let replay = recordedPosition(state, player: invalidSeat, move: .rollDice)
        let downloaded = try JSONDecoder().decode(SharedMatch.self, from: JSONEncoder().encode(replay))
        #expect(throws: SharedMatch.Rejection.replayFailed) { try downloaded.verified(owner: "apple-alex") }
    }

    @Test func downloadedReplayRejectsTradeQuantitiesThatWouldOverflow() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        let player = state.players[0].id
        state.phase = .mainTurn(playerIndex: player.index)
        let replay = recordedPosition(state, player: player,
            move: .bankTrade(give: [.brick: Int.max, .lumber: Int.max], get: [.wool: 1]))
        #expect(throws: SharedMatch.Rejection.replayFailed) { try replay.verified(owner: "apple-alex") }
    }

    @Test func downloadedReplayRejectsOutOfRangeStartingInventory() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        let player = state.players[0].id
        state.players[0].resources = [.brick: Int.max, .lumber: Int.max]
        state.phase = .rollDice(playerIndex: player.index)
        let replay = recordedPosition(state, player: player, move: .rollDice)
        #expect(throws: SharedMatch.Rejection.replayFailed) { try replay.verified(owner: "apple-alex") }
    }

    @Test func downloadedReplayCannotDeclareAWinnerInItsOpeningPosition() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.phase = .gameOver(winner: state.players[0].id)
        let replay = SharedMatch(version: SharedMatch.currentVersion, match: UUID(), date: Date(),
            seats: ["person:apple-alex", "expert", "expert", "expert"], initialState: state,
            moves: [], ratingPool: expert)
        #expect(throws: SharedMatch.Rejection.replayFailed) { try replay.verified(owner: "apple-alex") }
    }

    @Test(arguments: [false, true])
    func downloadedConquestReplayRejectsUnsafeArmyStrength(inGarrison: Bool) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7, variant: .conquest)
        let player = state.players[0].id
        let tile = try #require(state.board.tiles.first { $0.numberToken != nil }).coordinate
        state.phase = .mainTurn(playerIndex: player.index)
        state.players[0].settlements.insert(try #require(state.board.corners(of: tile).first))
        let cards = inGarrison ? [1] : [1, Int.max]
        state.armyHands[player] = cards
        if inGarrison { state.garrisons[tile] = Garrison(owner: player, strength: Int.max) }
        let replay = SharedMatch(version: SharedMatch.currentVersion, match: UUID(), date: Date(),
            seats: ["person:apple-alex", "expert", "expert", "expert"], initialState: state,
            moves: [.init(player: player, move: .deployArmy(to: tile, strengths: cards))],
            abandoned: true, ratingPool: RatingPool(mode: .classic, variant: .conquest, difficulty: .expert))
        #expect(throws: SharedMatch.Rejection.replayFailed) { try replay.verified(owner: "apple-alex") }
    }

    private func recordedPosition(_ state: GameState, player: PlayerID, move: GameMove) -> SharedMatch {
        SharedMatch(version: SharedMatch.currentVersion, match: UUID(), date: Date(),
            seats: ["person:apple-alex", "expert", "expert", "expert"], initialState: state,
            moves: [.init(player: player, move: move)], abandoned: true, ratingPool: expert)
    }

    @Test func checkpointRepairsQueuedReplayThatLostItsRulesVersion() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let suite = "RatingSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = model(device, defaults: defaults)
        let checkpoint = try legacyRobberCheckpoint(owner: device.me)
        let shared = try #require(model.sharedRatedMatch(checkpoint, abandoned: true))
        #expect(shared.moves.first?.rulesVersion == RulesEngine.oldestSupportedRulesVersion)
        let unversioned = SharedMatch(version: shared.version, match: shared.match, date: shared.date,
            seats: shared.seats, initialState: shared.initialState,
            moves: shared.moves.map { .init(player: $0.player, move: $0.move) },
            abandoned: true, ratingPool: shared.ratingPool)
        let outbox = device.stores.seatStats
        try outbox.queueForUpload(unversioned)
        #expect(throws: SharedMatch.Rejection.replayFailed) { try unversioned.verified(owner: device.me) }
        let pending = try #require(outbox.pendingUploadFiles().first)
        let oldBytes = try Data(contentsOf: pending)
        try device.stores.players.adopt("apple-alex", seatStats: outbox, ghosts: device.stores.ghosts)
        try model.persistDisplacedRatingMatch(checkpoint)
        let repaired = try outbox.queuedMatch(at: pending)
        #expect(repaired.moves.first?.rulesVersion == RulesEngine.oldestSupportedRulesVersion)
        #expect(outbox.record(for: shared.match)?.abandoned == true)
        #expect(outbox.record(for: shared.match)?.seats.compactMap(\.personID) == ["apple-alex"])
        let preserved = try FileManager.default.contentsOfDirectory(
            at: outbox.directory.appendingPathComponent("RejectedUploads"), includingPropertiesForKeys: nil)
        #expect(try Data(contentsOf: #require(preserved.first)) == oldBytes)
    }

    @Test func verifiedCheckpointReplacesDamagedSameMatchQueueAndPreservesBytes() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let shared = try pendingMatch(on: device, pool: naval)
        let outbox = device.stores.seatStats
        try outbox.queueForUpload(shared)
        let file = try #require(outbox.pendingUploadFiles().first)
        let damaged = Data("damaged replay".utf8)
        try damaged.write(to: file)
        let record = try outbox.queueVerifiedMatch(shared, resolveOwner: device.stores.players.resolvedID) {
            try $0.verified(owner: device.me)
        }
        #expect(record.match == shared.match)
        #expect(try outbox.queuedMatch(at: file).match == shared.match)
        let originals = try FileManager.default.contentsOfDirectory(
            at: outbox.directory.appendingPathComponent("RejectedUploads"), includingPropertiesForKeys: nil)
        #expect(try Data(contentsOf: #require(originals.first)) == damaged)
    }

    @Test func badQueueEntryDoesNotBlockAccountAdoptionOrValidUpload() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cloud = LiveSyncTests.FakeCloud()
        let phone = LiveSyncTests.Device("phone", in: directory)
        let outbox = phone.stores.seatStats
        let good = try pendingMatch(on: phone, pool: naval)
        try outbox.queueForUpload(good)
        func unsupportedMatch(seats: [String]) -> SharedMatch {
            SharedMatch(version: good.version + 1, match: UUID(), date: good.date,
                        seats: seats, initialState: good.initialState, moves: good.moves,
                        abandoned: good.abandoned, ratingPool: good.ratingPool)
        }
        try outbox.queueForUpload(unsupportedMatch(seats: good.seats))
        let foreignSeats = good.seats.map { $0.hasPrefix(RatedEntity.personPrefix) ? RatedEntity.person("apple-jake").key : $0 }
        try outbox.queueForUpload(unsupportedMatch(seats: foreignSeats))
        let archivedSeats = good.seats.map { $0.hasPrefix(RatedEntity.personPrefix) ? $0 : RatedEntity.ghost("archived~1").key }
        let archived = unsupportedMatch(seats: archivedSeats)
        let archivedFile = outbox.pendingUploadsDirectory.appendingPathComponent("\(archived.match.uuidString).json")
        try JSONEncoder().encode(archived).write(to: archivedFile)
        let corrupt = outbox.pendingUploadsDirectory.appendingPathComponent("00000000-0000-0000-0000-000000000000.json")
        let bytes = Data("damaged replay".utf8)
        try bytes.write(to: corrupt)
        let status = await phone.sync(cloud, as: "apple-alex", name: "Alex")
        #expect(status == .partiallySynced(rejectedRecordings: 2))
        #expect(phone.me == "apple-alex")
        #expect(cloud.locked { $0.matches[good.match]?.owner } == "apple-alex")
        #expect(try Data(contentsOf: corrupt) == bytes)
        #expect(try outbox.pendingUploadFiles().count == 4)
    }

    private func legacyRobberCheckpoint(owner: String) throws -> MatchCheckpoint {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 912)
        let actor = state.players[0].id
        let target = try #require(state.board.tiles.map(\.coordinate).first { $0 != state.board.robberTile })
        let vertex = try #require(state.board.corners(of: target).first)
        state.players[1].settlements.insert(vertex)
        state.players[1].resources = [.lumber: 1]
        state.phase = .movingRobber(playerIndex: actor.index)
        state.robberMoverIndex = actor.index
        var checkpoint = MatchCheckpoint(id: UUID(), initialState: state, setup: setup(expert), playerID: owner)
        try checkpoint.apply(.moveRobber(target, stealFrom: nil), by: actor,
                             rulesVersion: RulesEngine.oldestSupportedRulesVersion)
        checkpoint.recordAbandonment(at: Date())
        return checkpoint
    }

    @Test func alexJakeKyleAndASecondAlexDeviceConvergeToOneLedger() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cloud = LiveSyncTests.FakeCloud()
        let devices = [LiveSyncTests.Device("alex-phone", in: directory), LiveSyncTests.Device("alex-ipad", in: directory),
                       LiveSyncTests.Device("jake", in: directory), LiveSyncTests.Device("kyle", in: directory)]
        let accounts = [("apple-alex", "Alex"), ("apple-alex", "Alex"), ("apple-jake", "Jake"), ("apple-kyle", "Kyle")]
        for (index, device) in devices.enumerated() {
            let shared = try pendingMatch(on: device, pool: index.isMultiple(of: 2) ? expert : naval)
            try await device.liveSync(LiveSyncTests.Phone(cloud: cloud, user: accounts[index].0),
                                      name: accounts[index].1).recordAbandoned(shared)
            try await sync(device, cloud: cloud, user: accounts[index].0, name: accounts[index].1)
        }
        for (index, device) in devices.enumerated() {
            try await sync(device, cloud: cloud, user: accounts[index].0, name: accounts[index].1)
        }
        let ledger = PlayerRatings(records: devices[0].stores.seatStats.all())
        #expect(ledger.playerIDs == ["apple-alex", "apple-jake", "apple-kyle"])
        #expect(ledger.overallRecord(for: "apple-alex").games == 2)
        #expect(ledger.aiStanding(in: expert).games == 2 && ledger.aiStanding(in: naval).games == 2)
        for device in devices { #expect(PlayerRatings(records: device.stores.seatStats.all()) == ledger) }
        #expect(cloud.locked { $0.matches.count } == 4, "each real match counts once, not once per phone")
    }

    /// Simulate a crash after writing the replay but before writing stats,
    /// then failure after adopting Alex. Kyle must never inherit that game.
    @Test func anOfflineLocalQueueBindsToItsFirstAccountBeforeAFailedUpload() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cloud = LiveSyncTests.FakeCloud()
        let phone = LiveSyncTests.Device("phone", in: directory)
        let local = phone.me
        let shared = try pendingMatch(on: phone, pool: naval)
        try phone.stores.seatStats.queueForUpload(shared)
        cloud.locked { $0.failNextMatchUpload = true }
        #expect(await phone.sync(cloud, as: "apple-alex", name: "Alex") == .offline)
        #expect(phone.me == "apple-alex")
        #expect(phone.stores.players.resolvedID(local) == "apple-alex")
        #expect(phone.stores.seatStats.record(for: shared.match)?.seats.compactMap(\.personID) == ["apple-alex"])
        try await sync(phone, cloud: cloud, user: "apple-kyle", name: "Kyle")
        #expect(cloud.locked { $0.matches.isEmpty })
        #expect(try phone.stores.seatStats.pendingUploadFiles().count == 1)
        try await sync(phone, cloud: cloud, user: "apple-alex", name: "Alex")
        #expect(cloud.locked { $0.matches[shared.match]?.owner } == "apple-alex")
        #expect(try phone.stores.seatStats.pendingUploadFiles().isEmpty)
        let ledger = PlayerRatings(records: phone.stores.seatStats.all())
        #expect(ledger.overallRecord(for: "apple-alex").games == 1)
        #expect(ledger.overallRecord(for: "apple-kyle").games == 0)
    }

    @Test func restartingOfflineRecordsOneLossAndAReplayBeforeExportAcknowledgement() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let suite = "RatingSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = model(device, defaults: defaults)
        model.startNewGame(setup: setup(naval))
        let previous = try #require(model.currentGameLogID)
        model.startNewGame(setup: setup(expert))
        let record = try #require(device.stores.seatStats.record(for: previous))
        #expect(record.abandoned == true && record.ratingPool == naval)
        #expect(PlayerRatings(records: device.stores.seatStats.all()).standing(for: device.me, in: naval).losses == 1)
        #expect(try device.stores.seatStats.pendingUploadFiles().count == 1)
        #expect(model.checkpointDocument?.pendingExports.isEmpty == true)
        let once = device.stores.seatStats.all()
        model.exportCommittedRecordings()
        #expect(device.stores.seatStats.all() == once)
    }

    @Test func fixtureReplacementDoesNotCreateARestartLoss() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let suite = "RatingSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = model(device, defaults: defaults)
        model.startNewGame(setup: setup(expert))
        let old = try #require(model.checkpointDocument?.activeMatch)
        let next = MatchCheckpoint(id: UUID(), initialState: old.initialState, setup: old.setup)
        let fixture = try MatchCheckpointDocument(activeMatch: old).replacingActiveMatch(with: next)
        let displaced = try #require(fixture.pendingExports[old.id])
        #expect(displaced.abandonedAt == nil)
        try model.persistDisplacedRatingMatch(displaced)
        #expect(device.stores.seatStats.all().isEmpty)
    }

    @Test func aRetryUsesTheAtomicReplacementDateAndOriginalOwner() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let cloud = LiveSyncTests.FakeCloud()
        let suite = "RatingSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = model(device, defaults: defaults)
        model.startNewGame(setup: setup(naval))
        let old = try #require(model.checkpointDocument?.activeMatch)
        let local = device.me
        let when = old.startedAt.addingTimeInterval(42)
        let next = MatchCheckpoint(id: UUID(), initialState: old.initialState, setup: old.setup, startedAt: when)
        let switched = try MatchCheckpointDocument(activeMatch: old).replacingActiveMatch(with: next, recordAbandonment: true)
        let displaced = try #require(switched.pendingExports[old.id])
        try await sync(device, cloud: cloud, user: "apple-alex", name: "Alex")
        try await sync(device, cloud: cloud, user: "apple-kyle", name: "Kyle")
        #expect(device.stores.players.resolvedID(local) == "apple-alex")
        let payload = try #require(model.sharedRatedMatch(displaced, abandoned: true))
        #expect(payload.date == when && payload.personIDs == ["apple-alex"])
        try model.persistDisplacedRatingMatch(displaced)
        #expect(device.stores.seatStats.record(for: old.id)?.date == when)
        #expect(device.stores.seatStats.record(for: old.id)?.seats.compactMap(\.personID) == ["apple-alex"])
        try await sync(device, cloud: cloud, user: "apple-kyle", name: "Kyle")
        #expect(cloud.locked { $0.matches.isEmpty })
    }

    @Test(arguments: [false, true])
    func scopeUpgradeEnrichesAnExistingMatchAndRetriesTheFullQueryAfterOffline(failFirstQuery: Bool) async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cloud = LiveSyncTests.FakeCloud()
        let author = LiveSyncTests.Device("author", in: directory)
        let shared = try pendingMatch(on: author, pool: naval)
        let phone = LiveSyncTests.Device("observer", in: directory)
        let verified = try shared.verified(owner: "apple-jake")
        try phone.stores.seatStats.record(SeatStatsRecord(match: verified.match, date: verified.date,
                                                         seats: verified.seats, abandoned: verified.abandoned))
        try await LiveSyncTests.Phone(cloud: cloud, user: "apple-jake").upload(shared)
        var state = SyncState()
        state.filedByPlayerID = true
        state.ratedAbandonedMatches = true
        state.ratingsRebuilt = true
        state.lastModified = Date(timeIntervalSince1970: 5_000_000)
        try state.save(to: phone.stores.stateFile)
        if failFirstQuery {
            cloud.locked { $0.failNextMatches = true }
            #expect(await phone.sync(cloud, as: "apple-alex", name: "Alex") == .offline)
        }
        try await sync(phone, cloud: cloud, user: "apple-alex", name: "Alex")
        #expect(phone.stores.seatStats.record(for: shared.match)?.ratingPool == naval)
        let first = PlayerRatings(records: phone.stores.seatStats.all())
        #expect(first.standing(for: "apple-jake", in: naval).losses == 1)
        try await sync(phone, cloud: cloud, user: "apple-alex", name: "Alex")
        #expect(PlayerRatings(records: phone.stores.seatStats.all()) == first)
        let queries = cloud.locked { $0.matchQueries }
        #expect(queries.dropLast().allSatisfy { $0 == nil })
        #expect(try #require(queries.last) != nil, "successful backfill resumes incremental queries")
    }

    @Test func newCheckpointMetadataDecodesWhenAbsentAndPreservesArchiveDifficulty() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let suite = "RatingSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = model(device, defaults: defaults)
        model.startNewGame(setup: setup(expert))
        let match = try #require(model.checkpointDocument?.activeMatch)
        let data = try JSONEncoder().encode(match)
        var wire = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        wire.removeValue(forKey: "playerID")
        wire.removeValue(forKey: "abandonedAt")
        let old = try JSONDecoder().decode(MatchCheckpoint.self, from: JSONSerialization.data(withJSONObject: wire))
        #expect(old.playerID == nil && old.abandonedAt == nil)
        #expect(old.state == match.state && old.setup == match.setup)
        let file = try device.stores.logs.export(checkpoint: match)
        #expect(try device.stores.logs.detail(for: file).roster.difficulty == .expert)
    }

    @Test func aDurableFirstAccountBindingSurvivesAnInterruptedAdoptionAndAnotherAccount() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let local = device.me
        var contents = device.stores.players.load()
        contents.localOwnerBindings = [local: "apple-alex"]
        try device.stores.players.save(contents)
        let shared = try pendingMatch(on: device, pool: naval)
        let firstAccountRecord = try shared.verified(owner: "apple-alex")
        try device.stores.seatStats.record(firstAccountRecord)
        try device.stores.players.adopt("apple-kyle", seatStats: device.stores.seatStats, ghosts: device.stores.ghosts)
        #expect(device.me == "apple-kyle")
        #expect(device.stores.players.resolvedID(local) == "apple-alex", "the first binding is write-ahead intent")
        #expect(device.stores.seatStats.record(for: shared.match)?.seats.compactMap(\.personID) == ["apple-alex"])
    }

    @Test func aDifferentValidPayloadCannotOccupyAnotherMatchsOutboxPath() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let shared = try pendingMatch(on: device, pool: naval)
        try device.stores.seatStats.queueForUpload(shared)
        let other = SharedMatch(version: shared.version, match: UUID(), date: shared.date, seats: shared.seats,
                                initialState: shared.initialState, moves: shared.moves,
                                abandoned: true, ratingPool: shared.ratingPool)
        let bytes = try JSONEncoder().encode(other)
        let file = try #require(device.stores.seatStats.pendingUploadFiles().first)
        try bytes.write(to: file, options: .atomic)
        #expect(throws: (any Error).self) { try device.stores.seatStats.queueForUpload(shared) }
        #expect(try Data(contentsOf: file) == bytes, "retain mismatched bytes for diagnosis")
    }

    @Test func aCompletionRacingWithAdoptionIsRefiledToTheBoundAccount() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cloud = LiveSyncTests.FakeCloud()
        let device = LiveSyncTests.Device("phone", in: directory)
        let local = device.me
        let shared = try pendingMatch(on: device, pool: naval)
        try await sync(device, cloud: cloud, user: "apple-alex", name: "Alex")
        // Completion took its owner snapshot before adoption, but persists
        // after the refile's initial record enumeration completed.
        try device.stores.seatStats.record(shared.verified(owner: local))
        try device.stores.seatStats.queueForUpload(shared)
        try await sync(device, cloud: cloud, user: "apple-alex", name: "Alex")
        #expect(cloud.locked { $0.matches[shared.match]?.owner } == "apple-alex")
        #expect(device.stores.seatStats.record(for: shared.match)?.seats.compactMap(\.personID) == ["apple-alex"])
        #expect(PlayerRatings(records: device.stores.seatStats.all()).overallRecord(for: local).games == 0)
    }

    @Test func checkpointIdentityChangesCannotUseIncrementalHistoryValidation() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = LiveSyncTests.Device("phone", in: directory)
        let suite = "RatingSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = model(device, defaults: defaults)
        model.startNewGame(setup: setup(expert))
        let original = try #require(model.checkpointDocument?.activeMatch)
        let renamed = MatchCheckpoint(id: original.id, initialState: original.initialState, setup: original.setup,
                                      startedAt: original.startedAt, playerID: "another-account")
        #expect(!renamed.isExtending(original))
        var abandoned = original
        abandoned.recordAbandonment(at: original.startedAt.addingTimeInterval(20))
        #expect(!abandoned.isExtending(original))
    }

    /// Old releases queued restarts beside state.json without creating stats
    /// first. The new shared outbox must still drain that actual old shape.
    @Test func aLegacyAbandonedReplayDrainsOnceIntoTheCurrentRatings() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cloud = LiveSyncTests.FakeCloud()
        let device = LiveSyncTests.Device("phone", in: directory)
        var legacy = try pendingMatch(on: device, pool: expert)
        legacy.ratingPool = nil
        try FileManager.default.createDirectory(at: device.stores.abandonedDirectory, withIntermediateDirectories: true)
        let file = device.stores.abandonedDirectory.appendingPathComponent("\(legacy.match.uuidString).json")
        try JSONEncoder().encode(legacy).write(to: file, options: .atomic)
        #expect(device.stores.seatStats.all().isEmpty)
        try await sync(device, cloud: cloud, user: "apple-alex", name: "Alex")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try device.stores.pendingGameFiles().isEmpty)
        #expect(cloud.locked { $0.matches[legacy.match]?.owner } == "apple-alex")
        let ledger = PlayerRatings(records: device.stores.seatStats.all())
        #expect(ledger.standing(for: "apple-alex", in: expert).forfeits == 1)
        try await sync(device, cloud: cloud, user: "apple-alex", name: "Alex")
        #expect(PlayerRatings(records: device.stores.seatStats.all()) == ledger)
        #expect(cloud.locked { $0.matches.count } == 1)
    }

    @Test func archivedGhostReplayEvidenceStaysPrivateEvenIfAnOlderQueueContainsIt() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cloud = LiveSyncTests.FakeCloud()
        let device = LiveSyncTests.Device("phone", in: directory)
        let shared = try pendingMatch(on: device, pool: expert)
        var seats = shared.seats
        seats[1] = "ghost:apple-alex~1"
        var archived = try shared.refilingSeats(seats)
        archived.ratingPool = nil
        try device.stores.seatStats.queueForUpload(archived)
        #expect(try device.stores.seatStats.pendingUploadFiles().isEmpty, "new private ghost games never enter the outbox")
        try FileManager.default.createDirectory(at: device.stores.seatStats.pendingUploadsDirectory,
                                               withIntermediateDirectories: true)
        let file = device.stores.seatStats.pendingUploadsDirectory.appendingPathComponent("\(archived.match.uuidString).json")
        let original = try JSONEncoder().encode(archived)
        try original.write(to: file, options: .atomic)
        try await sync(device, cloud: cloud, user: "apple-alex", name: "Alex")
        #expect(cloud.locked { $0.matches.isEmpty })
        #expect(try Data(contentsOf: file) == original, "previously queued private evidence is retained, never published")
        #expect(PlayerRatings(records: device.stores.seatStats.all()).changes.isEmpty)
    }
}
