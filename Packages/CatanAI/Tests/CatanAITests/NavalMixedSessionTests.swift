import Testing
import Foundation
import CatanEngine
@testable import CatanAI

/// Covers the app's distinct human-seat path, including external responses
/// while an automated reply is pending. Save validity is checked every action.
@Suite struct NavalMixedSessionTests {
    @Test(arguments: [3, 4])
    func aCompleteExternalSeatMatchStaysReloadable(players: Int) throws {
        let state = Naval.newGame(seed: 7501, playerCount: players)
        let human = state.players[players - 2].id
        let policies = Dictionary(uniqueKeysWithValues: state.players.filter { $0.id != human }.map {
            ($0.id, NavalPolicy(tier: .expert) as any Policy)
        })
        var session = GameSession(state: state, policies: policies, policySeed: 7501 &* 31 &+ 7)
        var proxyRNG = RandomSource(seed: 0)
        let proxy = HeuristicPolicy(personality: .balanced, id: "qa-human")
        var externalActions = 0
        for _ in 0..<3000 {
            if case .gameOver = session.state.phase { break }
            if let offer = session.state.pendingTradeOffers.first(where: { $0.from != human }) {
                var legal: [GameMove] = [.respondToTrade(offerID: offer.id, accept: false)]
                if Trading.bothSidesCanHonour(offer, responder: human, state: session.state) {
                    legal.append(.respondToTrade(offerID: offer.id, accept: true))
                }
                let observation = GameObservation(seat: human, state: session.state, legalMoves: legal)
                _ = try session.applyExternal(proxy.decide(observation, rng: &proxyRNG), by: human)
                externalActions += 1
            } else if case .awaitingExternalSeat(let seat) = session.nextActor() {
                #expect(seat == human)
                let observation = GameObservation(seat: seat, state: session.state,
                    legalMoves: RulesEngine.legalMoves(for: session.state, seat: seat))
                _ = try session.applyExternal(proxy.decide(observation, rng: &proxyRNG), by: seat)
                externalActions += 1
            } else {
                #expect(try session.step() != nil)
            }
            try session.checkpoint.validate()
            let data = try JSONEncoder().encode(session.checkpoint)
            let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: data)
            try checkpoint.validate()
            #expect(checkpoint == session.checkpoint)
        }
        #expect(externalActions > 0)
        guard case .gameOver(let winner) = session.state.phase else { Issue.record("Mixed naval match did not finish"); return }
        #expect(session.state.victoryPoints(for: winner) >= 14)
    }
}
