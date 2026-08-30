import Testing
import Foundation
@testable import Settlers
@testable import CatanEngine

/// Tests for the match contract behind the New Game screen (`MatchSetup`) and
/// for the store that prefills it.
///
/// ## Why the model and not the view
/// `NewGameSetupView` deliberately owns no validity logic - it renders
/// `MatchSetup.validationProblem` and disables Start on it. So the rules the
/// spec's acceptance criteria are written against (A1.3, A2.1, A2.4, A2.6,
/// A3.2, A6.1) are all decidable here, without a UI test target, without a
/// simulator, and without the flakiness of either. The two things that are
/// genuinely view-only - the 12-character input limit and the layout at 375pt -
/// are verified by screenshot instead, because nothing else can reach them:
/// the simulator has no touch injection and SwiftUI exposes no element tree.
private func seat(_ index: Int,
                  human: Bool,
                  name: String = "",
                  civilization: Civilization? = nil) -> MatchSetup.Seat {
    MatchSetup.Seat(index: index, isHuman: human, name: name, civilization: civilization)
}

private func setup(_ seats: [MatchSetup.Seat],
                   target: Int = WinCondition.standardTarget) -> MatchSetup {
    MatchSetup(seats: seats,
               victoryPointTarget: target,
               randomizedBoard: true,
               randomizeSeatOrder: true)
}

/// A four-seat table that is startable, as the baseline every test below
/// breaks exactly one thing about.
private var startableTable: MatchSetup {
    setup([
        seat(0, human: true, name: "Alex", civilization: .greece),
        seat(1, human: true, name: "Sam", civilization: .rome),
        seat(2, human: false, civilization: .japan),
        seat(3, human: false, civilization: nil),
    ])
}

@Suite struct MatchSetupValidationTests {

    @Test func aFullyConfiguredTableStarts() {
        #expect(startableTable.validationProblem == nil)
        #expect(startableTable.isStartable)
    }

    /// A3.5: an undecided seat is not an invalid one. Seat 4 above is `nil`
    /// and the table still starts.
    @Test func seatsLeftOnRandomDoNotBlockStart() {
        var table = startableTable
        table.seats[2].civilization = nil
        #expect(table.validationProblem == nil)
    }

    /// A2.1/A2.2: the problem names the seat, because "something is missing"
    /// on a screen with four seats is not an answer.
    @Test func anUnnamedHumanSeatIsRefusedByName() {
        var table = startableTable
        table.seats[1].name = ""
        #expect(table.validationProblem == "Seat 2 needs a name.")
    }

    /// A2.6. Whitespace is not a name, and this is the case a naive
    /// `isEmpty` check passes.
    @Test func aWhitespaceOnlyNameCountsAsUnnamed() {
        var table = startableTable
        table.seats[0].name = "   \n "
        #expect(table.validationProblem == "Seat 1 needs a name.")
    }

    /// A2.4, including the case that matters on a shared phone: "alex" and
    /// "Alex" are the same person as far as the HUD is concerned.
    @Test func twoHumansCannotShareAName() {
        var table = startableTable
        table.seats[1].name = "  ALEX "
        #expect(table.validationProblem == "Two players share a name.")
    }

    /// An AI seat carries no name at all, so four bots' empty names must not
    /// read as four duplicates.
    @Test func emptyAINamesAreNotDuplicates() {
        var table = startableTable
        table.seats[1].isHuman = false
        table.seats[1].name = ""
        #expect(table.validationProblem == nil)
    }

    /// A3.2. Duplicates are an invariant violation rather than a warning: the
    /// seat colour *is* the civilization's colour, so two Romes make the board
    /// unreadable.
    @Test func twoSeatsCannotShareACivilization() {
        var table = startableTable
        table.seats[3].civilization = .greece
        #expect(table.validationProblem == "Two seats share a civilization.")
    }

    /// A1.3, checked from the model's side. The view refuses the *edit* that
    /// would get here; this is the backstop if some other path ever builds one.
    @Test func aTableWithNoHumanCannotStart() {
        var table = startableTable
        table.seats[0].isHuman = false
        table.seats[1].isHuman = false
        #expect(table.validationProblem == "At least one seat must be a human player.")
    }

    /// A1.4: zero AI seats is a legal, startable configuration.
    @Test func anAllHumanTableStarts() {
        var table = startableTable
        table.seats[2].isHuman = true
        table.seats[2].name = "Jake"
        table.seats[3].isHuman = true
        table.seats[3].name = "Ada"
        #expect(table.validationProblem == nil)
    }

    @Test func aTargetOutsideTheSupportedRangeIsRefused() {
        var table = startableTable
        table.victoryPointTarget = WinCondition.supportedTargets.upperBound + 1
        #expect(table.validationProblem == "That match length is not available.")
    }

    @Test(arguments: [8, 10, 12])
    func eachOfferedMatchLengthIsSupported(target: Int) {
        var table = startableTable
        table.victoryPointTarget = target
        #expect(table.validationProblem == nil)
    }

    /// The seat-count check runs first, so a two-seat table is refused for
    /// being a two-seat table rather than for whatever else is wrong with it.
    @Test func aTableOutsideTheSupportedSizesIsRefusedFirst() {
        let table = setup([seat(0, human: true, name: "Alex", civilization: .greece),
                           seat(1, human: false, civilization: .rome)])
        #expect(table.validationProblem == "A game needs 3 or 4 players.")
    }
}

@Suite struct MatchSetupCivilizationsTakenTests {

    /// A3.3: the picker greys out what other seats hold, and never the seat's
    /// own pick - otherwise re-opening a picker shows the current choice as
    /// unavailable.
    @Test func takenExcludesTheSeatsOwnChoice() {
        let table = startableTable
        #expect(table.civilizationsTaken(excluding: 0) == [.rome, .japan])
        #expect(table.civilizationsTaken(excluding: 1) == [.greece, .japan])
    }

    /// A seat left on Random takes nothing, so it never blocks another seat.
    @Test func seatsOnRandomTakeNothing() {
        var table = startableTable
        table.seats[1].civilization = nil
        table.seats[2].civilization = nil
        #expect(table.civilizationsTaken(excluding: 3) == [.greece])
    }
}

@Suite struct MatchSetupResizeTests {

    private let preferredName = "Alex"
    private let preferredCivilization = Civilization.medieval

    /// Shrinking drops the highest seat - which is exactly why the screen
    /// marks seat 4 "Optional" - and leaves every remaining seat's role, name
    /// and civilization alone.
    @Test func shrinkingKeepsTheRemainingSeatsChoices() {
        var table = startableTable
        table.resize(to: 3, preferredName: preferredName, preferredCivilization: preferredCivilization)

        #expect(table.seats.count == 3)
        #expect(table.seats[0].name == "Alex")
        #expect(table.seats[0].civilization == .greece)
        #expect(table.seats[1].isHuman)
        #expect(table.seats[1].name == "Sam")
        #expect(table.seats[1].civilization == .rome)
        #expect(table.seats[2].civilization == .japan)
    }

    /// The only way `resize` can produce an invalid table: drop the one seat
    /// the human was sitting in. Seat 1 takes over, and is given the preferred
    /// name so the result is startable rather than merely non-empty.
    @Test func shrinkingNeverLeavesATableWithNoHuman() {
        var table = setup([
            seat(0, human: false, civilization: .greece),
            seat(1, human: false, civilization: .rome),
            seat(2, human: false, civilization: .japan),
            seat(3, human: true, name: "Alex", civilization: .norse),
        ])
        table.resize(to: 3, preferredName: preferredName, preferredCivilization: preferredCivilization)

        #expect(table.humanSeats.count == 1)
        #expect(table.seats[0].isHuman)
        #expect(table.seats[0].name == preferredName)
        #expect(table.validationProblem == nil)
    }

    /// Growing adds an AI seat with no civilization, so it can never collide
    /// with a pick already on the table - and a player who wants that chair
    /// flips it to Human themselves.
    @Test func growingAppendsAnUndecidedAISeat() {
        var table = startableTable
        table.resize(to: 3, preferredName: preferredName, preferredCivilization: preferredCivilization)
        table.resize(to: 4, preferredName: preferredName, preferredCivilization: preferredCivilization)

        #expect(table.seats.count == 4)
        #expect(table.seats[1].name == "Sam", "growing back must not disturb the seats that stayed")
        #expect(table.seats[2].civilization == .japan)
        #expect(!table.seats[3].isHuman)
        #expect(table.seats[3].civilization == nil)
        #expect(table.validationProblem == nil)
    }

    @Test func resizingToTheCurrentSizeChangesNothing() {
        var table = startableTable
        let before = table
        table.resize(to: 4, preferredName: preferredName, preferredCivilization: preferredCivilization)
        #expect(table == before)
    }
}

@Suite struct MatchSetupDefaultTests {

    /// X4.1: a fresh install needs a name typed in and nothing else - so the
    /// default is invalid for exactly one reason, and that reason is the name.
    @Test func afreshInstallOnlyNeedsAName() {
        let table = MatchSetup.default(preferredName: "", preferredCivilization: .medieval)
        #expect(table.seats.count == GameSetup.standardPlayerCount)
        #expect(table.validationProblem == "Seat 1 needs a name.")

        var named = table
        named.seats[0].name = "Alex"
        #expect(named.validationProblem == nil)
    }

    /// A2.3/A3.7: the App Settings preferences prefill seat 1.
    @Test func theStoredPreferencesPrefillTheHumanSeat() {
        let table = MatchSetup.default(preferredName: "Jake", preferredCivilization: .norse)
        #expect(table.seats[0].isHuman)
        #expect(table.seats[0].name == "Jake")
        #expect(table.seats[0].civilization == .norse)
        #expect(table.aiSeats.count == GameSetup.standardPlayerCount - 1)
        #expect(table.victoryPointTarget == WinCondition.standardTarget)
    }
}

@Suite struct MatchSetupStoreTests {

    /// Every test here builds its own `MatchSetupStore` over its own throwaway
    /// suite, and never touches `MatchSetupStore.shared` or
    /// `UserDefaults.standard`.
    ///
    /// That is not fastidiousness: `gate.sh` runs this bundle on the
    /// developer's own simulator on every push, and an app test here has
    /// already once wiped real simulator data by writing through a singleton
    /// into the standard domain. `defaults` is `var` on the store precisely so
    /// this is possible.
    private func withStore(_ body: (MatchSetupStore) -> Void) {
        let suiteName = "MatchSetupStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("could not open a throwaway defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MatchSetupStore()
        store.defaults = defaults
        body(store)
    }

    @Test func nothingSavedReadsAsNoStoredSetup() {
        withStore { store in
            #expect(store.load() == nil)
        }
    }

    /// A6.4/X4.2: the screen opens on the last configuration, so every field
    /// it shows has to survive the round trip - not just the two toggles that
    /// used to live on the main menu.
    @Test func aSavedSetupRoundTrips() {
        withStore { store in
            var table = startableTable
            table.victoryPointTarget = 8
            table.randomizedBoard = false
            table.randomizeSeatOrder = false
            store.save(table)

            #expect(store.load() == table)
        }
    }

    /// "Given a previous game was configured with three humans, when the setup
    /// screen is next opened, then it shows three humans" (A6.4).
    @Test func aThreeHumanTableComesBackAsThreeHumans() {
        withStore { store in
            var table = startableTable
            table.seats[2].isHuman = true
            table.seats[2].name = "Jake"
            store.save(table)

            let loaded = store.load()
            #expect(loaded?.humanSeats.count == 3)
            #expect(loaded?.seats[2].name == "Jake")
        }
    }

    @Test func clearingRemovesTheStoredSetup() {
        withStore { store in
            store.save(startableTable)
            store.clear()
            #expect(store.load() == nil)
        }
    }
}
