#if DEBUG
import Foundation
import CatanEngine

extension GameViewModel {
    /// Retains the rejected candidate so a persistence failure can be replayed
    /// without inferring the state from the last successfully saved turn.
    func qaRecordFailedCheckpoint(_ checkpoint: GameSession.Checkpoint, error: Error) throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("qa_failed_checkpoint.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(checkpoint).write(to: url, options: .atomic)
        print("QA rejected checkpoint: \(url.path); \(error)")
    }

    /// An ordinary new match for full UI play; rare deterministic positions are
    /// explicitly replaced replay baselines, never edits to its history.
    func qaStartNavalGame() {
        let civilizationArgument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-qaNavalCivilization=") }
        let civilization = civilizationArgument.map {
            Civilization(rawValue: String($0.dropFirst("-qaNavalCivilization=".count)))!
        } ?? .greece
        var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: civilization)
        setup.mode = .naval
        setup.victoryPointTarget = Ruleset.forMode(.naval).defaultVictoryPointTarget
        setup.randomizedBoard = true
        setup.randomizeSeatOrder = false
        setup.difficulty = QALaunchFlag.navalExpert.isSet ? .expert : .classic
        setup.navalOptions = NavalOptions(fogEnabled: !QALaunchFlag.navalNoFog.isSet,
            resourceChoiceEnabled: !QALaunchFlag.navalNoResourceChoice.isSet,
            mapFamily: QALaunchOption.navalMapFamily)
        setup.expertRevision = setup.newMatchExpertRevision
        startNewGame(setup: setup)
        let kind: NavalQAFixture.Position?
        if QALaunchFlag.navalGenericPortPosition.isSet {
            kind = .genericPort
        } else if QALaunchFlag.navalResourcePortPosition.isSet {
            kind = .resourcePort
        } else if QALaunchFlag.navalMixedShipsPosition.isSet {
            kind = .mixedShips
        } else if QALaunchFlag.navalStackedShipsPosition.isSet {
            kind = .stackedShips
        } else if QALaunchFlag.navalAdjacentShipsPosition.isSet {
            kind = .adjacentShips
        } else if QALaunchFlag.navalCityResourcePosition.isSet {
            kind = .cityHarvest
        } else if QALaunchFlag.navalResourcePosition.isSet {
            kind = .harvest
        } else if QALaunchFlag.navalCapturePosition.isSet {
            kind = .capture
        } else if QALaunchFlag.navalVoyagePosition.isSet || QALaunchFlag.navalBuildScarcity.isSet {
            kind = .voyage
        } else { kind = nil }
        let blockade: NavalBlockadeQAFixture.Position?
        if QALaunchFlag.navalBlockadeCapturePosition.isSet {
            blockade = .capture
        } else if QALaunchFlag.navalBlockadeLaunchPosition.isSet {
            blockade = .launch
        } else if QALaunchFlag.navalBlockadePosition.isSet {
            blockade = .passage
        } else { blockade = nil }
        guard kind != nil || blockade != nil else { return }
        let artworkAssignment = civilizationArgument.map { _ in
            state.players.map { playerIdentity(for: $0.id).civilization }
        }
        do {
            var position = try blockade.map { try NavalBlockadeQAFixture.make($0, options: setup.navalOptions) }
                ?? NavalQAFixture.make(kind!, options: setup.navalOptions)
            if QALaunchFlag.navalBuildScarcity.isSet {
                NavalQAFixture.replaceHand([.lumber: 1, .wool: 10], for: PlayerID(index: 0), in: &position)
            }
            replaceStateForTesting(position, humanSeat: PlayerID(index: 0), difficulty: setup.difficulty,
                                   civilizations: artworkAssignment)
        } catch { preconditionFailure("Naval QA fixture is invalid: \(error)") }
    }
}
#endif
