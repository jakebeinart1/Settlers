import CatanAI
import CatanEngine
import Foundation

struct SeatDiagnostics: Codable {
    var shipsBought = 0
    var sailingSteps = 0
    var navigationProgressSteps = 0
    var hexesRevealed = 0
    var captures = 0
    var colonies = 0
    var colonyPoints = 0
    var resourceChoices = 0
    var bankTrades = 0
    var proposals = 0
    var acceptedTrades = 0
    var cities = 0
    var developmentCards = 0
    var cardsPlayed = 0
    var turns = 0
    var shipOpportunities = 0
    var sailingOpportunities = 0
    var colonyOpportunities = 0
}

struct Diagnostics {
    var seats: [SeatDiagnostics]
    var sailingCycles: Int { navigation.rawRevisits }
    var idleSailingCycles: Int { navigation.idleRevisits }
    var forcedEnds = 0
    var tradeCycles = 0
    var duplicateProposals = 0
    var decisionMilliseconds: [Double] = []
    private var mainActor: PlayerID?
    private var mainActions = 0
    private var navigation = NavalNavigationDiagnostics()
    private var sailingTurn: Int?
    private var economicMarker: [Int] = []
    private var seenHands: [PlayerID: Set<[Int]>] = [:]

    init(players: Int) { seats = Array(repeating: SeatDiagnostics(), count: players) }

    mutating func decision(_ decision: GameSession.Decision, milliseconds: Double) {
        decisionMilliseconds.append(milliseconds)
        let index = decision.seat.index
        let legal = decision.observation.legalMoves
        if legal.contains(where: { if case .buildShip = $0 { true } else { false } }) { seats[index].shipOpportunities += 1 }
        if legal.contains(where: { if case .sailShip = $0 { true } else { false } }) { seats[index].sailingOpportunities += 1 }
        if legal.contains(where: { move in
            if case .buildSettlement(let site) = move {
                return NavalNavigationDiagnostics.isOverseasSite(site, in: decision.observation.state)
            }
            return false
        }) { seats[index].colonyOpportunities += 1 }
    }

    mutating func applied(_ step: GameSession.Step, before: GameState, after: GameState) {
        let index = step.actor.index
        if case .mainTurn(let roller) = before.phase {
            if sailingTurn != roller {
                sailingTurn = roller
                economicMarker = []
            }
        } else { sailingTurn = nil }
        if step.move == .endTurn, mainActor == step.actor,
           mainActions >= GameSession.actionLimit(in: before) { forcedEnds += 1 }
        recordAction(step)
        recordTrading(step, before: before, after: after)
        let progressBefore = navigation.progressSteps
        navigation.observe(step.move, by: step.actor, before: before, after: after)
        seats[index].navigationProgressSteps += navigation.progressSteps - progressBefore
        if case .sailShip(let id, _) = step.move,
           let original = before.naval?.ships.first(where: { $0.id == id }),
           let sailed = after.naval?.ships.first(where: { $0.id == id }) {
            seats[index].sailingSteps += original.stepsRemaining - sailed.stepsRemaining
        }
        if case .buildSettlement(let vertex) = step.move,
           NavalNavigationDiagnostics.isOverseasSite(vertex, in: before) {
            seats[index].colonies += 1
        }
        classify(step.move, at: index)
        for event in step.events { observe(event) }
    }

    private mutating func recordAction(_ step: GameSession.Step) {
        if case .respondToTrade = step.move { return }
        if step.move == .endTurn, mainActor == step.actor {
            mainActor = nil
            mainActions = 0
        } else if mainActor == step.actor {
            mainActions += 1
        } else {
            mainActor = step.actor
            mainActions = 1
        }
    }

    private mutating func recordTrading(_ step: GameSession.Step, before: GameState, after: GameState) {
        let marker = before.players.flatMap {
            [$0.settlements.count, $0.cities.count, $0.roads.count, $0.devCards.count, $0.playedKnights]
        } + [before.naval?.revealed.count ?? 0, before.naval?.ships.count ?? 0]
        if marker != economicMarker {
            economicMarker = marker
            seenHands = Dictionary(uniqueKeysWithValues: before.players.map { ($0.id, Set([hand($0)])) })
        }
        if case .proposeTrade(let offer) = step.move,
           before.pendingTradeOffers.contains(where: { $0.id == offer.id }) { duplicateProposals += 1 }
        guard isExchange(step.move) else { return }
        for player in after.players where hand(player) != hand(before.players[player.id.index]) {
            if !seenHands[player.id, default: []].insert(hand(player)).inserted { tradeCycles += 1 }
        }
    }

    private func hand(_ player: Player) -> [Int] { Resource.allCases.map { player.resources[$0, default: 0] } }

    private func isExchange(_ move: GameMove) -> Bool {
        switch move {
        case .bankTrade, .respondToTrade(_, true): true
        default: false
        }
    }

    private mutating func classify(_ move: GameMove, at index: Int) {
        switch move {
        case .bankTrade: seats[index].bankTrades += 1
        case .proposeTrade: seats[index].proposals += 1
        case .respondToTrade(_, true): seats[index].acceptedTrades += 1
        case .buildCity: seats[index].cities += 1
        case .buyDevCard: seats[index].developmentCards += 1
        case .playKnight, .playRoadBuilding, .playMonopoly, .playYearOfPlenty: seats[index].cardsPlayed += 1
        case .endTurn: seats[index].turns += 1
        default: break
        }
    }

    private mutating func observe(_ event: GameEvent) {
        switch event {
        case .builtShip(let seat, _, _):
            seats[seat.index].shipsBought += 1
        case .discovered(let seat, let hexes): seats[seat.index].hexesRevealed += hexes.count
        case .capturedShip(let seat, _, _): seats[seat.index].captures += 1
        case .earnedColonyPoint(let seat, let total): seats[seat.index].colonyPoints = total
        case .choseResource(let seat, _): seats[seat.index].resourceChoices += 1
        default: break
        }
    }
}
