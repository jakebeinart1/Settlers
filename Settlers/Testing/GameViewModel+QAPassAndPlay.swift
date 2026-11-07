#if DEBUG
import CatanEngine
import Foundation

enum QAPassAndPlayFixture {
    case discard, botWait, win, trade, harvest, devCard, recovery

    static var requested: Self? {
        if QALaunchFlag.passAndPlayDiscard.isSet { return .discard }
        if QALaunchFlag.passAndPlayBotWait.isSet { return .botWait }
        if QALaunchFlag.passAndPlayWin.isSet { return .win }
        if QALaunchFlag.passAndPlayTrade.isSet { return .trade }
        if QALaunchFlag.passAndPlayHarvest.isSet { return .harvest }
        if QALaunchFlag.passAndPlayDevCard.isSet { return .devCard }
        if QALaunchFlag.passAndPlayRecovery.isSet { return .recovery }
        return nil
    }
}

extension GameViewModel {
    /// Save a reproducible position just before the action under review.
    /// Real bot turns, dice, discard submissions, building and result
    /// recording still travel through the ordinary session and UI.
    func qaSetUpPassAndPlay(_ fixture: QAPassAndPlayFixture) {
        var position = fixture == .harvest ? qaPassAndPlayHarvest() : qaPassAndPlayPosition()
        let humans: Set<PlayerID>
        switch fixture {
        case .discard:
            humans = [PlayerID(index: 0), PlayerID(index: 1)]
            qaFundPassAndPlayHand([.brick: 8], seat: 0, in: &position)
            qaFundPassAndPlayHand([.ore: 8], seat: 1, in: &position)
            position.rng = NavalQAFixture.rollSource(total: 7)
        case .botWait:
            humans = [PlayerID(index: 2), PlayerID(index: 3)]
            PacingPreferences.shared.select(.slow)
            PacingPreferences.shared.setSkipPauses(false)
            PacingPreferences.shared.setBlockTradeOffers(true)
        case .win:
            let winner = PlayerID(index: 1)
            humans = [PlayerID(index: 0), winner]
            qaPreparePassAndPlayWin(winner: winner, in: &position)
        case .trade, .recovery:
            humans = [PlayerID(index: 0), PlayerID(index: 1)]
            qaFundPassAndPlayHand([.lumber: 2], seat: 0, in: &position)
            qaFundPassAndPlayHand([.grain: 2], seat: 1, in: &position)
            position.phase = .mainTurn(playerIndex: 0)
        case .harvest:
            humans = [PlayerID(index: 0), PlayerID(index: 1)]
        case .devCard:
            humans = [PlayerID(index: 0), PlayerID(index: 1)]
            qaFundPassAndPlayHand(Building.devCardCost, seat: 1, in: &position)
            guard let card = position.devCardDeck.firstIndex(of: .monopoly) else {
                preconditionFailure("Pass & Play fixture requires a Monopoly card")
            }
            position.devCardDeck.remove(at: card)
            position.devCardDeck.insert(.monopoly, at: 0)
            position.phase = .mainTurn(playerIndex: 1)
        }
        replaceStateForTesting(position, humanSeats: humans)
        releaseLocalDevice()
        if fixture == .recovery {
            // Seed the presentation boundary only. The valid checkpoint above
            // is still read by the production reload action on the cover.
            _ = reportPersistenceFailure(CocoaError(.fileWriteUnknown))
        }
    }

    private func qaPassAndPlayPosition() -> GameState {
        var position = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_251, playerCount: 4)
        while position.phase.isSetup, let index = position.phase.awaitingSeatIndex {
            let seat = PlayerID(index: index)
            guard let move = RulesEngine.legalMoves(for: position, seat: seat).first else {
                preconditionFailure("Pass & Play fixture has no legal opening move")
            }
            do {
                try RulesEngine.apply(move, by: seat, to: &position)
            } catch { preconditionFailure("Pass & Play fixture could not complete setup: \(error)") }
        }
        for index in position.players.indices {
            for (resource, count) in position.players[index].resources {
                position.bank[resource, default: 0] += count
            }
            position.players[index].resources = [:]
        }
        return position
    }

    private func qaPassAndPlayHarvest() -> GameState {
        do {
            // Reuse the navigated, settled island from the existing fixture.
            // Let the second person roll that tile's number in the live app.
            var position = try NavalQAFixture.make(.harvest)
            guard let roll = position.lastDiceRoll else { preconditionFailure("The harvest fixture needs a roll") }
            position.naval?.pendingResourceChoices = []
            position.naval?.productionRollerIndex = nil
            position.phase = .rollDice(playerIndex: 1)
            position.rng = NavalQAFixture.rollSource(total: roll)
            return position
        } catch {
            preconditionFailure("Pass & Play harvest fixture is invalid: \(error)")
        }
    }

    private func qaPreparePassAndPlayWin(winner: PlayerID, in position: inout GameState) {
        let index = winner.index
        var holdings = position.players[index].settlements.sorted()
        var occupied = Set(position.players.flatMap { $0.settlements })
        // Three cities and three settlements leave one legal city upgrade
        // between the guest and the normal Classic target of ten points.
        for vertex in position.board.onBoardVertices.sorted() where holdings.count < 6 {
            guard !occupied.contains(vertex),
                  position.board.adjacentVertices(of: vertex).allSatisfy({ !occupied.contains($0) }) else { continue }
            holdings.append(vertex)
            occupied.insert(vertex)
        }
        position.players[index].cities = Set(holdings.prefix(3))
        position.players[index].settlements = Set(holdings.dropFirst(3))
        qaFundPassAndPlayHand(Building.cityCost, seat: index, in: &position)
        position.phase = .mainTurn(playerIndex: index)
        precondition(position.victoryPoints(for: winner) == position.victoryPointTarget - 1
                     && RulesEngine.legalMoves(for: position, seat: winner).contains { move in
                         if case .buildCity = move { return true }
                         return false
                     }, "Pass & Play fixture must offer a legal winning city")
    }

    private func qaFundPassAndPlayHand(_ cards: [Resource: Int], seat: Int, in position: inout GameState) {
        for (resource, count) in cards {
            precondition(position.bank[resource, default: 0] >= count, "QA cards must come from the bank")
            position.bank[resource, default: 0] -= count
            position.players[seat].resources[resource, default: 0] += count
        }
    }
}
#endif
