import Foundation
import CatanEngine

/// Read-only presentation of a draft against the current hand and bank.
/// The engine owns structural/stock legality. This adapter adds actionable
/// wording and quantity steps without mutating the draft or the saved game.
struct TradeDraftFeedback {
    let give: [Resource: Int]
    let receive: [Resource: Int]
    let mode: Trading.DraftMode
    let player: PlayerID
    let state: GameState

    var isBank: Bool { if case .bank = mode { true } else { false } }
    var isPlayersTurn: Bool { state.phase.isMainTurn(of: player.index) }
    var giveTotal: Int { give.values.reduce(0, +) }
    var receiveTotal: Int { receive.values.reduce(0, +) }
    var bankCredit: Int { Resource.allCases.reduce(0) { $0 + give[$1, default: 0] / rate($1) } }
    var unspentCredit: Int { bankCredit - receiveTotal }

    var canSubmit: Bool {
        guard isPlayersTurn, !give.isEmpty, !receive.isEmpty,
              give.values.allSatisfy({ $0 > 0 }), receive.values.allSatisfy({ $0 > 0 }),
              structuralProblem == nil, missingHolding == nil else { return false }
        return !isBank || bankProblem == nil
    }

    var hasProblem: Bool {
        !isPlayersTurn || structuralProblem != nil || missingHolding != nil
            || (isBank && missingStock != nil) || (isBank && unspentCredit < 0)
    }

    func owned(_ resource: Resource) -> Int {
        state.players.first { $0.id == player }?.resources[resource] ?? 0
    }

    func remaining(_ resource: Resource) -> Int { max(0, owned(resource) - give[resource, default: 0]) }
    func stock(_ resource: Resource) -> Int { state.bank[resource, default: 0] }
    func rate(_ resource: Resource) -> Int { Trading.bestRate(for: resource, player: player, state: state) }

    /// A player draft may carry an incomplete stack into Bank. Complete just
    /// that remainder; adding another whole bundle would leave it invalid forever.
    func addStep(_ resource: Resource) -> Int {
        guard isBank else { return 1 }
        return rate(resource) - give[resource, default: 0] % rate(resource)
    }

    func removeStep(_ resource: Resource) -> Int {
        guard isBank else { return 1 }
        let remainder = give[resource, default: 0] % rate(resource)
        return remainder > 0 ? remainder : rate(resource)
    }

    func canAdd(_ resource: Resource, toGive: Bool) -> Bool {
        guard isPlayersTurn else { return false }
        var proposedGive = give
        var proposedReceive = receive
        if toGive {
            guard remaining(resource) >= addStep(resource) else { return false }
            proposedGive[resource, default: 0] += addStep(resource)
        } else {
            if isBank {
                guard unspentCredit > 0, receive[resource, default: 0] < stock(resource) else { return false }
            }
            proposedReceive[resource, default: 0] += 1
        }
        // Check overlap here. Other incomplete bank bundles remain editable.
        return Trading.draftProblem(give: proposedGive, get: proposedReceive,
                                    mode: .players, by: player, state: state) == nil
    }

    var message: String {
        if !isPlayersTurn { return "You can trade during your turn." }
        if let resource = missingHolding {
            return "You only hold \(owned(resource)) \(name(resource)). Remove some from You give."
        }
        switch structuralProblem {
        case .overlappingResources:
            return "Give and receive different resources. Remove one side to continue."
        case .invalidBankBundle(let resource, let rate):
            let needed = rate - give[resource, default: 0] % rate
            return "Add \(needed) more \(name(resource)) for a \(rate):1 bundle, or use minus to remove the partial bundle."
        case nil: break
        }
        return isBank ? bankMessage : playerMessage
    }

    private var playerMessage: String {
        if give.isEmpty { return "Tap a square to choose what you give. Your remaining cards appear below each resource." }
        if receive.isEmpty { return "Choose what you receive. Players can exchange any quantities." }
        return "Offer \(cards(giveTotal)) for \(cards(receiveTotal)). Each bot decides whether to accept."
    }

    private var bankMessage: String {
        if let resource = missingStock {
            return "The bank has \(stock(resource)) \(name(resource)), but you selected \(receive[resource, default: 0]). Choose another resource or use minus."
        }
        if give.isEmpty { return "Tap a square to give a bundle at your port rate, then choose what you receive." }
        if unspentCredit > 0 { return "Choose \(unspentCredit) more \(unspentCredit == 1 ? "card" : "cards") to receive, or remove a give bundle." }
        if unspentCredit < 0 { return "Remove \(-unspentCredit) from You receive, or add another give bundle." }
        if let bankProblem { return bankProblem.localizedDescription }
        return "Ready to trade \(cards(giveTotal)) for \(cards(receiveTotal))."
    }

    private var structuralProblem: Trading.DraftProblem? {
        Trading.draftProblem(give: give, get: receive, mode: mode, by: player, state: state)
    }

    private var bankProblem: MoveError? {
        Trading.bankTradeProblem(give: give, get: receive, by: player, state: state)
    }

    private var missingHolding: Resource? {
        Resource.allCases.first { give[$0, default: 0] > owned($0) }
    }

    private var missingStock: Resource? {
        Resource.allCases.first { receive[$0, default: 0] > stock($0) }
    }

    private func name(_ resource: Resource) -> String { resource.rawValue.capitalized }
    private func cards(_ count: Int) -> String { "\(count) \(count == 1 ? "card" : "cards")" }
}

/// Incoming engine piles are in the proposer's perspective. Convert once at
/// the presentation boundary so all summaries and review actions speak to You.
struct IncomingTradeSummary {
    let give: [Resource: Int]
    let receive: [Resource: Int]

    init(offer: TradeOffer) {
        give = offer.want
        receive = offer.give
    }

    var giveText: String { "You give \(Self.resources(give))" }
    var receiveText: String { "You receive \(Self.resources(receive))" }
    var requiresReview: Bool { max(give.count, receive.count) > 2 }

    static func resources(_ counts: [Resource: Int], separator: String = ", ") -> String {
        let terms = Resource.allCases.filter { counts[$0, default: 0] > 0 }.map {
            "\(counts[$0, default: 0]) \($0.rawValue.capitalized)"
        }
        return terms.isEmpty ? "no cards" : terms.joined(separator: separator)
    }
}
