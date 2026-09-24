import Testing
import CatanEngine
@testable import Settlers

private let name: @Sendable (PlayerID) -> String = { "P\($0.index + 1)" }
private let me = PlayerID(index: 0)

@Suite struct ArmyPreviewTests {
    @Test func namesEachOutcome() {
        #expect(ArmyPreview.sentence(total: 9, against: Garrison(owner: nil, strength: 5), me: me, name: name)
            == "Takes it, holding at 4")
        #expect(ArmyPreview.sentence(total: 2, against: Garrison(owner: PlayerID(index: 1), strength: 5), me: me, name: name)
            == "Leaves P2 at 3")
        #expect(ArmyPreview.sentence(total: 3, against: Garrison(owner: me, strength: 5), me: me, name: name)
            == "Reinforces to 8")
        #expect(ArmyPreview.sentence(total: 1, against: nil, me: me, name: name) == "Takes it, holding at 1")
    }

    @Test func saysEmptyAtExactlyZero() {
        #expect(ArmyPreview.sentence(total: 5, against: Garrison(owner: nil, strength: 5), me: me, name: name)
            == "Leaves it empty")
    }
}

@Suite struct ArmyChipsTests {
    @Test func duplicateStrengthsToggleOneCopyAtATime() {
        let hand = [3, 3, 5]
        var selected: [Int] = []
        selected = ArmyChips.toggle(1, hand: hand, selected: selected)     // either 3 selects "a 3"
        #expect(selected == [3])
        #expect(ArmyChips.isOn(0, hand: hand, selected: selected))
        #expect(!ArmyChips.isOn(1, hand: hand, selected: selected))
        selected = ArmyChips.toggle(1, hand: hand, selected: selected)
        #expect(selected == [3, 3])
        selected = ArmyChips.toggle(0, hand: hand, selected: selected)
        #expect(selected == [3])
    }
}
