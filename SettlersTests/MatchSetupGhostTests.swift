import CatanEngine
import Foundation
import Testing
@testable import Settlers

@Suite struct MatchSetupGhostTests {

    private func table() -> MatchSetup {
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .greece)
        setup.randomizeSeatOrder = false
        return setup
    }

    @Test func aSeatDecodesWithAndWithoutAGhost() throws {
        var setup = table()
        setup.seats[2].ghostID = "jake"
        let data = try JSONEncoder().encode(setup)
        #expect(try JSONDecoder().decode(MatchSetup.self, from: data).seats[2].ghostID == "jake")
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var seats = try #require(object["seats"] as? [[String: Any]])
        seats[2].removeValue(forKey: "ghostID")
        object["seats"] = seats
        let old = try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.seats[2].ghostID == nil)
    }

    @Test func aGhostTableCanStart() {
        var setup = table()
        setup.seats[2].ghostID = "jake"
        #expect(setup.newGameProblem(knownGhosts: ["jake"]) == nil)
    }

    @Test func ghostsPlayClassicOnly() {
        var setup = table()
        setup.seats[2].ghostID = "jake"
        setup.mode = .vast
        setup.victoryPointTarget = 26
        #expect(setup.newGameProblem(knownGhosts: ["jake"]) == "Ghosts play Classic only.")
        setup.mode = .classic
        setup.victoryPointTarget = 10
        setup.variant = .conquest
        #expect(setup.newGameProblem(knownGhosts: ["jake"]) == "Ghosts play Classic only.")
    }

    /// Review Focus 5.
    @Test func oneGhostCannotSitTwice() {
        var setup = table()
        setup.seats[1].ghostID = "jake"
        setup.seats[2].ghostID = "jake"
        #expect(setup.newGameProblem(knownGhosts: ["jake"]) == "A ghost can only take one seat.")
    }

    /// Review Focus 2: a ghost that is no longer on this phone, named by seat.
    @Test func anUnknownGhostIsRefusedBySeat() {
        var setup = table()
        setup.seats[3].ghostID = "gone"
        #expect(setup.newGameProblem(knownGhosts: ["jake"]) == "Seat 4's ghost is no longer on this phone.")
    }

    @Test func aHumanCannotAlsoBeAGhost() {
        var setup = table()
        setup.seats[0].ghostID = "jake"
        #expect(setup.newGameProblem(knownGhosts: ["jake"]) == "Seat 1 cannot be both Human and Ghost.")
    }

    @Test func growingTheTableNeverAddsAHuman() {
        var setup = table()
        setup.resize(to: 3, preferredName: "Jake", preferredCivilization: .greece)
        setup.resize(to: 4, preferredName: "Jake", preferredCivilization: .greece)
        #expect(setup.seats.map(\.isHuman) == [true, false, false, false])
    }

    @Test(arguments: [false, true])
    func navalGhostIdentitiesAreRejectedAtTheSavedMatchBoundary(profileOnly: Bool) throws {
        var setup = table()
        setup.mode = .naval
        setup.victoryPointTarget = 14
        for index in setup.seats.indices {
            let civilization = Civilization.allCases[index]
            setup.seats[index].civilization = civilization
            if !setup.seats[index].isHuman {
                setup.seats[index].opponentProfile = .forCivilization(civilization)
            }
        }
        if profileOnly {
            setup.seats[2].opponentProfile = OpponentProfile(
                id: OpponentProfile.ghostProfilePrefix + "jake", name: "Jake's Ghost",
                civilization: setup.seats[2].civilization!, strategy: .balanced)
        } else {
            setup.seats[2].ghostID = "jake"
        }
        #expect(setup.matchProblem == "Ghosts play Classic only.")
        #expect(setup.realizedIdentityProblem == "Ghosts play Classic only.")
        let state = Naval.newGame(seed: 7, playerCount: 4, options: setup.navalOptions)
        let match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        #expect(throws: MatchCheckpointStore.StoreError.invalidSetup) { try match.validateHistory() }
        setup.mode = .classic
        setup.victoryPointTarget = 10
        #expect(setup.matchProblem == nil, "Existing Classic ghost matches must remain resumable")
        #expect(setup.realizedIdentityProblem == nil)
    }
}
