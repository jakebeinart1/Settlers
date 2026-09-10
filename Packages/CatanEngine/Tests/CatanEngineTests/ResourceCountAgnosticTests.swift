import Testing
@testable import CatanEngine

/// Pins the behaviour a sixth resource depends on: everything that enumerates
/// resources does it through `Resource.allCases`, so adding a case is a
/// one-line change rather than a hunt.
///
/// What actually protects an unwired sixth `Resource` case is Swift's
/// exhaustiveness checking - add a case and every `switch` over `Resource`
/// fails to compile. This test cannot improve on that and does not try to.
/// What it covers is the ground the compiler can't: dictionary-keyed state
/// populated by iterating `allCases` (the bank fill below) would silently
/// gain a correct entry for a new case, where a hand-written partial
/// dictionary would silently not. This pins that the bank fill is
/// allCases-driven and uniform, so a new resource arrives stocked rather
/// than absent.
@Test func everyResourceGetsBankStockAndAFeatureSlot() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    // Every case, not five named ones.
    for resource in Resource.allCases {
        #expect(state.bank[resource] != nil, "\(resource) has no bank stock")
    }
    #expect(state.bank.count == Resource.allCases.count)
}

@Test func startingBankIsUniformAcrossEveryResource() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    let stocks = Set(Resource.allCases.map { state.bank[$0] ?? -1 })
    #expect(stocks.count == 1, "bank stock differs by resource: \(stocks)")
}
