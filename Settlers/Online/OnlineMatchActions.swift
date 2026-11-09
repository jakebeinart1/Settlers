import SwiftUI
import CatanEngine
import EmpiresOnline

enum OnlineMoveEditor: Equatable, Identifiable {
    case discard, bank, trade, armyPurchase, cards, harvest, deploy(HexCoordinate)
    var id: String {
        switch self {
        case .discard: "discard"
        case .bank: "bank"
        case .trade: "trade"
        case .armyPurchase: "army-purchase"
        case .cards: "cards"
        case .harvest: "harvest"
        case .deploy(let tile): "deploy-\(tile.q)-\(tile.r)"
        }
    }

    var title: String {
        switch self {
        case .discard: "Discard Resources"
        case .bank: "Trade with Bank"
        case .trade: "Propose Trade"
        case .armyPurchase: "Buy Army Card"
        case .cards: "Development Cards"
        case .harvest: "Collect Resources"
        case .deploy: "Deploy Army"
        }
    }
}

struct OnlineMatchActions: View {
    let gameplay: OnlineGameplayView
    let moves: [GameMove]
    let isEnabled: Bool
    let name: (PlayerID) -> String
    let onBegin: (BoardDecisionIntent) -> Void
    let onEditor: (OnlineMoveEditor) -> Void
    let onSubmit: (GameMove) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let discard = gameplay.discardCount {
                row(.discard, icon: "square.stack.minus", detail: "Choose \(discard) cards to discard.")
            } else if gameplay.harvestRemaining != nil {
                row(.harvest, icon: "leaf", detail: "Choose what to collect from your islands.")
            } else if let offer = gameplay.tradeOffer {
                tradeResponse(offer)
            } else if moves.isEmpty {
                OnlineInformation(title: "Waiting for the table", detail: "Your next action will appear here.")
            } else {
                ordinaryActions
            }
        }
    }

    private var ordinaryActions: some View {
        Group {
            if moves.contains(.rollDice) {
                direct(.rollDice, title: "Roll Dice", icon: "dice.fill")
            }
            ForEach(OnlineBoardAction.allCases) { action in
                if moves.contains(where: action.matches) {
                    GoldRowButton(title: action.title, systemImage: action.icon,
                                  iconColor: SettingsChrome.ornamentGold, isEnabled: isEnabled) {
                        onBegin(action.intent)
                    }
                }
            }
            if moves.contains(.buyDevCard) {
                direct(.buyDevCard, title: "Buy Development Card", icon: "rectangle.on.rectangle")
            }
            if moves.contains(where: { if case .buyArmyCard = $0 { true } else { false } }) {
                row(.armyPurchase, icon: "shield", detail: gameplay.armyPrice.label.capitalized)
            }
            if moves.contains(where: { if case .bankTrade = $0 { true } else { false } }) {
                row(.bank, icon: "building.columns")
            }
            if gameplay.canProposeTrade { row(.trade, icon: "arrow.left.arrow.right") }
            if !gameplay.devCards.isEmpty { row(.cards, icon: "rectangle.stack") }
            if moves.contains(.endTurn) {
                direct(.endTurn, title: "End Turn", icon: "arrow.forward.circle.fill")
            }
        }
    }

    private func row(_ editor: OnlineMoveEditor, icon: String, detail: String? = nil) -> some View {
        GoldRowButton(title: editor.title, subtitle: detail, systemImage: icon,
                      iconColor: SettingsChrome.ornamentGold, isEnabled: isEnabled) { onEditor(editor) }
    }

    private func direct(_ move: GameMove, title: String, icon: String) -> some View {
        GoldRowButton(title: title, systemImage: icon, iconColor: SettingsChrome.ornamentGold,
                      isEnabled: isEnabled) { onSubmit(move) }
    }

    private func tradeResponse(_ offer: TradeOffer) -> some View {
        let sent = offer.from == gameplay.viewer
        return VStack(spacing: 8) {
            OnlineInformation(
                title: sent ? "Trade awaiting response" : "Trade from \(name(offer.from))",
                detail: sent ? "You give \(offer.give.onlineSummary). You receive \(offer.want.onlineSummary)."
                    : "You give \(offer.want.onlineSummary). You receive \(offer.give.onlineSummary)."
            )
            ForEach([true, false], id: \.self) { accepted in
                let move = GameMove.respondToTrade(offerID: offer.id, accept: accepted)
                if moves.contains(move) {
                    direct(move, title: accepted ? "Accept Trade" : "Decline Trade",
                           icon: accepted ? "checkmark.circle" : "xmark.circle")
                }
            }
        }
    }
}

private enum OnlineBoardAction: String, CaseIterable, Identifiable {
    case road, settlement, city, ship, sail, knight, roadBuilding, deploy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .road: "Build Road"
        case .settlement: "Build Settlement"
        case .city: "Upgrade to City"
        case .ship: "Launch Ship"
        case .sail: "Sail Ship"
        case .knight: "Play Knight"
        case .roadBuilding: "Play Road Building"
        case .deploy: "Deploy Army"
        }
    }

    var icon: String {
        switch self {
        case .road, .roadBuilding: "road.lanes"
        case .settlement: "house"
        case .city: "building.2"
        case .ship, .sail: "sailboat"
        case .knight, .deploy: "shield"
        }
    }

    var intent: BoardDecisionIntent {
        switch self {
        case .road: .buildRoad
        case .settlement: .buildSettlement
        case .city: .buildCity
        case .ship: .buildShip
        case .sail: .sailShip
        case .knight: .knight
        case .roadBuilding: .roadBuilding
        case .deploy: .deployArmy
        }
    }

    func matches(_ move: GameMove) -> Bool {
        switch (self, move) {
        case (.road, .buildRoad), (.settlement, .buildSettlement), (.city, .buildCity),
             (.ship, .buildShip), (.sail, .sailShip), (.knight, .playKnight),
             (.roadBuilding, .playRoadBuilding), (.deploy, .deployArmy): true
        default: false
        }
    }
}

struct OnlineMoveEditorView: View {
    let editor: OnlineMoveEditor
    let gameplay: OnlineGameplayView
    let position: OnlineMatchView
    let name: (PlayerID) -> String
    let onClose: () -> Void
    let onSubmit: (GameMove) -> Void
    @State private var give: [Resource: Int] = [:]
    @State private var receive: [Resource: Int] = [:]
    @State private var army: [Int: Int] = [:]
    @State private var recipient: PlayerID?

    var body: some View {
        OnlineFormPage(title: editor.title, onClose: onClose) {
            switch editor {
            case .cards: developmentCards
            case .harvest: harvest
            case .deploy(let tile): deployEditor(tile)
            default: resourceEditor
            }
        }
        .onAppear { recipient = otherSeats.first }
    }

    private var resourceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editor == .trade {
                OnlinePicker(title: "Trade with", selection: $recipient) {
                    ForEach(otherSeats, id: \.self) { Text(name($0)).tag(Optional($0)) }
                }
            }
            Text(giveTitle).font(.system(.headline, design: .serif))
            ForEach(Resource.allCases, id: \.self) { resource in
                quantity(resource, in: $give, maximum: gameplay.resources[resource, default: 0])
            }
            if editor == .bank || editor == .trade {
                Text("You receive").font(.system(.headline, design: .serif)).padding(.top, 6)
                ForEach(Resource.allCases, id: \.self) { resource in
                    let limit = editor == .bank ? gameplay.bank[resource, default: 0]
                        : gameplay.boardPresentationState.rules.bankPerResource
                    quantity(resource, in: $receive, maximum: limit)
                }
            }
            GoldRowButton(title: editor.title, systemImage: "checkmark.circle",
                          iconColor: SettingsChrome.ornamentGold, isEnabled: composedMove != nil) {
                if let move = composedMove { onSubmit(move) }
            }
        }
    }

    private var giveTitle: String {
        if editor == .discard {
            return "\(give.values.reduce(0, +)) of \(gameplay.discardCount ?? 0) selected"
        }
        if editor == .armyPurchase { return "Pay \(gameplay.armyPrice.label)" }
        return "You give"
    }

    private var otherSeats: [PlayerID] {
        gameplay.players.map(\.id).filter { $0 != gameplay.viewer }
    }

    private var composedMove: GameMove? {
        let give = give.filter { $0.value > 0 }
        let receive = receive.filter { $0.value > 0 }
        switch editor {
        case .discard:
            return give.values.reduce(0, +) == gameplay.discardCount ? .discard(give) : nil
        case .armyPurchase:
            let valid = Conquest.isValidPayment(give, price: gameplay.armyPrice, hand: gameplay.resources)
            return valid ? .buyArmyCard(paying: give) : nil
        case .bank:
            let valid = Trading.bankTradeProblem(give: give, get: receive, by: gameplay.viewer,
                                                 state: gameplay.boardPresentationState) == nil
            return valid ? .bankTrade(give: give, get: receive) : nil
        case .trade:
            guard let recipient, !give.isEmpty, !receive.isEmpty,
                  Set(give.keys).isDisjoint(with: receive.keys) else { return nil }
            return .proposeTrade(TradeOffer(from: gameplay.viewer, recipient: recipient, give: give, want: receive))
        default: return nil
        }
    }

    private func quantity(_ resource: Resource, in counts: Binding<[Resource: Int]>, maximum: Int) -> some View {
        let value = Binding(get: { counts.wrappedValue[resource, default: 0] },
                            set: { counts.wrappedValue[resource] = $0 })
        return Stepper(value: value, in: 0 ... max(maximum, value.wrappedValue)) {
            Text("\(resource.rawValue.capitalized) · \(value.wrappedValue)").monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 8))
    }

    private var developmentCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DevCardType.allCases, id: \.self) { card in
                let count = gameplay.devCards.filter { $0 == card }.count
                if count > 0 {
                    let fresh = gameplay.devCardsBoughtThisTurn.filter { $0 == card }.count
                    OnlineInformation(title: "\(card.onlineTitle) · \(count)",
                                      detail: fresh > 0 ? "\(fresh) bought this turn" : "In your hand")
                }
            }
            ForEach(gameplay.legalMoves, id: \.self) { move in
                if let title = move.onlineCardChoice {
                    GoldRowButton(title: title, systemImage: "rectangle.stack", action: { onSubmit(move) })
                }
            }
        }
    }

    private var harvest: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(gameplay.harvestRemaining ?? 0) resources left to collect").font(.headline)
            ForEach(gameplay.legalMoves, id: \.self) { move in
                if case .chooseResource(let resource) = move {
                    GoldRowButton(title: "Collect \(resource.rawValue.capitalized)", systemImage: "leaf") { onSubmit(move) }
                }
            }
        }
    }

    private func deployEditor(_ tile: HexCoordinate) -> some View {
        let totals = Dictionary(grouping: gameplay.armyCards, by: { $0 }).mapValues(\.count)
        let chosen = army.keys.sorted().flatMap { strength in
            Array(repeating: strength, count: army[strength, default: 0])
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Choose which cards to commit to the selected territory.").font(.headline)
            ForEach(totals.keys.sorted(), id: \.self) { strength in
                Stepper(value: Binding(get: { army[strength, default: 0] }, set: { army[strength] = $0 }),
                        in: 0 ... totals[strength, default: 0]) {
                    Text("Strength \(strength) · \(army[strength, default: 0])")
                }
                .frame(minHeight: 44)
            }
            GoldRowButton(title: "Deploy Army", systemImage: "shield", isEnabled: !chosen.isEmpty) {
                onSubmit(.deployArmy(to: tile, strengths: chosen))
            }
        }
    }
}

private extension [Resource: Int] {
    var onlineSummary: String {
        Resource.allCases.compactMap { resource in
            self[resource].map { "\($0) \(resource.rawValue)" }
        }.joined(separator: ", ")
    }
}

extension DevCardType {
    var onlineTitle: String {
        switch self {
        case .knight: "Knight"
        case .roadBuilding: "Road Building"
        case .yearOfPlenty: "Year of Plenty"
        case .monopoly: "Monopoly"
        case .victoryPoint: "Victory Point"
        }
    }
}

private extension GameMove {
    var onlineCardChoice: String? {
        switch self {
        case .playMonopoly(let resource):
            "Monopoly · \(resource.rawValue.capitalized)"
        case .playYearOfPlenty(let first, let second):
            "Year of Plenty · \(first.rawValue.capitalized) and \(second.rawValue.capitalized)"
        default: nil
        }
    }
}
