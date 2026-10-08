import CatanEngine
import Foundation

/// Everything the How to Play screen says, kept apart from how it is drawn.
///
/// ## Why the numbers are read from the engine
/// Costs come from `Building`/`Conquest`, and targets, piece limits and bonus
/// sizes from `Ruleset.forMode`. A rules screen that restates them as literals
/// is a second copy of the ruleset, and the first rule change after it ships
/// makes the screen teach a game the app no longer plays.
///
/// ## Why the wording is our own
/// Game rules and mechanics are not protected by copyright (US Copyright
/// Office, circular FL-108), but a rulebook's *text* is. Every line here is
/// written for this app, in its own vocabulary (Army cards, Vast, Conquest,
/// civilizations), and nothing is paraphrased from a printed rulebook. See
/// `docs/AI_summaries/2026-09-28-app-store-ip-review.md`.
enum HowToPlayContent {
    /// A read-only match snapshot. Menu callers omit it; paused games may
    /// supply it without handing the rulebook a model that can make moves.
    struct Context {
        let mode: GameMode
        let variant: GameVariant
        let victoryPointTarget: Int
        let armyPrice: ArmyPrice
        let navalOptions: NavalOptions?
        let navalRulesVersion: Int?

        init(state: GameState) {
            mode = state.mode
            variant = state.variant
            victoryPointTarget = state.victoryPointTarget
            armyPrice = state.armyPrice
            navalOptions = state.naval?.options
            navalRulesVersion = state.naval?.rulesVersion
        }

        var ruleset: Ruleset { Ruleset.forMode(mode) }
        var title: String { "\(mode.displayName) · \(variant.displayName) · \(victoryPointTarget) points" }
    }

    struct ResourceLoss: Identifiable {
        let id: String
        let icon: String
        let title: String
        let amount: String
        let explanation: String
        let example: String
    }

    /// What a walkthrough card or a rules section shows above its words.
    enum Illustration: Equatable {
        case terrain
        case settlement
        case city
        case road
        case dice
        case robber
        case cards
        case trade
        case victory
    }

    /// One card of the click-through walkthrough: a picture, a headline and
    /// one short sentence - the whole game in about a minute.
    struct Step: Identifiable {
        let id: Int
        let illustration: Illustration
        let title: String
        let line: String
        var cost: [Resource: Int]?
    }

    /// One rule, as a single plain statement a player can read at a glance,
    /// with the fine print behind a Details disclosure.
    struct Section: Identifiable {
        let id: String
        let icon: String
        let title: String
        let summary: String
        let details: [String]
        var cost: [Resource: Int]?
        /// Draw `RollOddsChart` under the details.
        var showsRollOdds = false
        var resourceLosses: [ResourceLoss] = []
    }

    private static let classic = Ruleset.forMode(.classic)
    private static let vast = Ruleset.forMode(.vast)
    private static let naval = Ruleset.forMode(.naval)

    static let introduction = "These are the rules of Empires, a game of building, trading and competing empires. "
        + "Classic, Vast, Conquest and Naval are described here in our own terms; this is not the official CATAN rulebook."

    static var steps: [Step] { steps(for: nil) }
    static var rules: [Section] { rules(for: nil) }
    static var modes: [Section] { modes(for: nil) }

    static func steps(for context: Context?) -> [Step] {
        let ruleset = context?.ruleset ?? classic
        let target = context?.victoryPointTarget ?? ruleset.defaultVictoryPointTarget
        let isNaval = context?.mode == .naval
        return [
        Step(id: 0, illustration: .victory, title: "The goal",
             line: "Be the first empire to reach \(target) victory points."),
        Step(id: 1, illustration: .terrain, title: "The land",
             line: isNaval ? "Sail through sea and shared fog to discover resource islands. Sea and desert make nothing."
                : "Each hex makes one resource: Brick, Lumber, Wool, Grain or Ore. The desert makes nothing."),
        Step(id: 2, illustration: .settlement, title: "Settlements",
             line: "Build on the corners of hexes. A settlement is worth \(ruleset.victoryPoints(for: .settlement)) point and collects from the hexes it touches.",
             cost: Building.settlementCost),
        Step(id: 3, illustration: .dice, title: "Roll for resources",
             line: "Every turn starts with two dice. Each hex showing that number pays everyone built next to it."),
        Step(id: 4, illustration: .road, title: "Roads",
             line: isNaval ? "Roads grow from your own settlements. Sail a ship to establish a colony before building roads on a new island."
                : "Roads run along hex edges and are how you reach new corners to settle.",
             cost: Building.roadCost),
        Step(id: 5, illustration: .city, title: "Cities",
             line: "Upgrade a settlement to a city: \(ruleset.victoryPoints(for: .city)) points, and double the resources.",
             cost: Building.cityCost),
        Step(id: 6, illustration: .trade, title: "Trade",
             line: "Swap cards with other players, or trade with the bank at 4 for 1 - better at a port."),
        Step(id: 7, illustration: .robber, title: "The robber",
             line: "Roll a 7 and nobody collects. You move the robber to block a hex and steal a card."),
        Step(id: 8, illustration: .cards, title: "Development cards",
             line: "Buy a hidden card: a Knight, a free bonus, or a secret victory point.",
             cost: Building.devCardCost),
        Step(id: 9, illustration: .victory, title: "Win",
             line: "Points come from settlements, cities, bonuses and cards. Reach \(target) to win."),
        ]
    }

    static func rules(for context: Context?) -> [Section] {
        let ruleset = context?.ruleset ?? classic
        let target = context?.victoryPointTarget ?? ruleset.defaultVictoryPointTarget
        let boardName = context?.mode.displayName ?? GameMode.classic.displayName
        let isNaval = context?.mode == .naval
        var sections = [
        Section(
            id: "goal", icon: "star.fill", title: "Goal",
            summary: "Reach \(target) victory points to win.",
            details: [
                "A settlement is worth \(ruleset.victoryPoints(for: .settlement)) point and a city \(ruleset.victoryPoints(for: .city)).",
                "Longest Road is worth \(ruleset.longestRoadBonus) points and Largest Army \(ruleset.largestArmyBonus) while you hold them.",
                "Victory point cards count too, and stay hidden from the others.",
                "Empires checks everyone's score after a build or development-card play. A player at the target wins, even if it is another player's turn.",
                "This guide uses \(target) points for \(boardName).",
            ]
        ),
        Section(
            id: "resource-loss", icon: "hand.raised.fill", title: "Why did my cards go?",
            summary: "Knight takes one card. Monopoly takes one resource type. A seven can make you discard.",
            details: ["These are three different effects. A Knight never triggers a discard or takes more than one resource card."],
            resourceLosses: resourceLosses(for: context)
        ),
        Section(
            id: "setup", icon: "flag.fill", title: "Starting the game",
            summary: "Everyone places two settlements and two roads for free.",
            details: [
                "Seats place in order, then in reverse order, so the last seat places twice in a row.",
                "Each settlement comes with one road touching it.",
                "Your second settlement pays you one of each resource around it straight away.",
                "No two settlements may sit on neighbouring corners - there must be at least one empty corner between them.",
                isNaval ? "Setup settlements may use any legal empty corner on the home island, including inland corners."
                    : "Setup settlements may use any legal empty corner on the island.",
            ]
        ),
        Section(
            id: "turn", icon: "arrow.triangle.2.circlepath", title: "Your turn",
            summary: "Roll, then trade and build in any order, then end your turn.",
            details: [
                "The dice pay every player with a building next to a hex showing the rolled number - not just you.",
                "A settlement collects 1 card from each matching hex; a city collects 2.",
                "Numbers near 7 come up most often and 2 and 12 rarely - the chart below counts the ways each total can roll, out of 36.",
                "Humans and AI use the same two dice and the same rules. Expert changes how an opponent chooses moves; it does not give them better rolls or extra card plays.",
                "You can trade and build as many times as you can afford before ending your turn.",
                "If the bank cannot cover a resource owed to several players, nobody gets that resource. If only one player is owed it, they get what remains.",
            ],
            showsRollOdds: true
        ),
        Section(
            id: "build", icon: "hammer.fill", title: "Building",
            summary: "Spend resources on roads, settlements, cities and development cards.",
            details: [
                "Road: \(costDescription(Building.roadCost)). It must connect to your own road or building.",
                settlementDescription(isNaval: isNaval),
                "City: \(costDescription(Building.cityCost)). It replaces one of your settlements, which goes back to your supply.",
                "Development card: \(costDescription(Building.devCardCost)).",
                "In \(boardName) you have \(ruleset.pieceLimit(for: .settlement)) settlements, \(ruleset.pieceLimit(for: .city)) cities and \(ruleset.maxRoadsPerPlayer) roads.",
            ]
        ),
        Section(
            id: "trade", icon: "arrow.left.arrow.right", title: "Trading",
            summary: "Trade with players, or with the bank at 4 for 1.",
            details: [
                "On your turn you can offer any cards to the other players. They can accept or decline.",
                "When you accept a computer player's offer, other players who also accept and can pay have an equal chance "
                    + "to complete it. Two accepters each have a 50% chance. If another player wins, the game tells you who traded.",
                "The bank always takes 4 of one resource for 1 of any other.",
                "A 3:1 port takes 3 of any one resource. A resource port takes 2 of its own resource.",
                "You use a port by having a settlement or city on one of its two corners.",
            ]
        ),
        Section(
            id: "robber", icon: "exclamationmark.shield.fill", title: "Rolling a 7 and the robber",
            summary: "A 7 pays nobody. The roller moves the robber and steals a card.",
            details: [
                "Anyone holding more than \(ruleset.discardThreshold) resource cards discards half of them, rounded down. Those cards return to the bank, not to the roller.",
                isNaval ? "The robber moves to another discovered land hex. That hex produces nothing while the robber sits on it."
                    : "The robber moves to any other hex. That hex produces nothing while the robber sits on it.",
                "The roller steals one random card from a player with a building next to the robber's new hex.",
                "Choose one rival who holds resources next to the new hex. If nobody there holds resources, no card is stolen.",
                "A Knight card moves the robber the same way, without the discard.",
            ]
        ),
        Section(
            id: "cards", icon: "rectangle.portrait.on.rectangle.portrait.fill", title: "Development cards",
            summary: "Hidden cards bought from the deck. Play at most one per turn.",
            details: [
                "Knight: move the robber and steal one random resource card from one adjacent rival. Played Knights count toward Largest Army.",
                "Road Building: place 2 legal roads for free, together. Empires requires a legal pair; if only one road can be placed, the card waits.",
                "Year of Plenty: take exactly 2 resource cards the bank can supply. They can be the same resource; an unavailable pair cannot be confirmed.",
                "Monopoly: name one resource; every rival gives you all cards of that type. Other resource types stay with them.",
                "Victory Point: worth 1 point. It is never played - it just counts.",
                "An active card cannot be played on the turn you bought it. A Victory Point card counts immediately.",
                "A mature card may be played before or after rolling. Playing before the roll still uses this turn's one active-card allowance.",
                "Playing spends one copy of the card. To play Monopoly again on a later turn, you must hold another mature copy. A play that collects nothing still spends the card.",
                "Army cards in Conquest are a separate hand: they can be deployed the turn they are bought and do not use the development-card allowance.",
            ]
        ),
        Section(
            id: "bonuses", icon: "rosette", title: "Longest Road and Largest Army",
            summary: "Longest Road adds \(ruleset.longestRoadBonus) points; Largest Army adds \(ruleset.largestArmyBonus). Both can change hands.",
            details: [
                "Longest Road: the first player with an unbroken road of \(ruleset.longestRoadMinimum) or more. Someone who builds a longer one takes it.",
                "Another player's settlement built in the middle of your road breaks it.",
                "Largest Army: the first player to play \(ruleset.largestArmyMinimum) Knights. Someone who plays more takes it. Conquest's Army cards do not count as Knights.",
                "A tie does not take the bonus - the current holder keeps it.",
            ]
        ),
        ]
        if context?.variant == .conquest { sections.append(conquest(for: context)) }
        if isNaval { sections.append(voyages(for: context)) }
        return sections
    }

    static func modes(for context: Context?) -> [Section] {
        var sections = [
        Section(
            id: "classic", icon: "hexagon.fill", title: "Classic",
            summary: "The main game: the \(classic.board.tileCount)-hex island, played to \(classic.defaultVictoryPointTarget) points.",
            details: [
                "The introductory guide describes Classic unless it was opened for another match.",
                "Supply: \(classic.bankPerResource) cards of each resource and \(classic.devCardDeckSize) development cards, including \(classic.devCardDeck[.monopoly, default: 0]) Monopoly cards.",
                "Board: Standard uses the same fixed layout every game; Randomized shuffles the terrain and numbers.",
                "AI Opponents: Classic plays solid, steady games. Expert plans around your position and is much harder to beat.",
                "Ghosts - bots trained on real players' games - only play Classic.",
            ]
        ),
        Section(
            id: "vast", icon: "map.fill", title: "Vast",
            summary: "A \(vast.board.tileCount)-hex map played to \(vast.defaultVictoryPointTarget) points.",
            details: [
                "The same rules as Classic, on a map about three times the size.",
                "You get \(vast.pieceLimit(for: .settlement)) settlements, \(vast.pieceLimit(for: .city)) cities and \(vast.maxRoadsPerPlayer) roads.",
                "Longest Road and Largest Army are worth \(vast.longestRoadBonus) points each.",
                "You only discard on a 7 when holding more than \(vast.discardThreshold) cards.",
                "Supply: \(vast.bankPerResource) cards of each resource and \(vast.devCardDeckSize) development cards, including \(vast.devCardDeck[.monopoly, default: 0]) Monopoly cards.",
                "The bonus thresholds stay at \(vast.longestRoadMinimum) roads and \(vast.largestArmyMinimum) played Knights. Knight and Monopoly effects stay the same.",
            ]
        ),
        conquest(for: context),
        voyages(for: context),
        ]
        if context?.mode == .expanded {
            let legacy = Ruleset.forMode(.expanded)
            sections.append(Section(
                id: "expanded", icon: "map", title: "Expanded",
                summary: "Your saved \(legacy.board.tileCount)-hex game continues to \(legacy.defaultVictoryPointTarget) points.",
                details: [
                    "Expanded is retained for saved games. New games use Classic or Vast.",
                    "You have \(legacy.pieceLimit(for: .settlement)) settlements, \(legacy.pieceLimit(for: .city)) cities and \(legacy.maxRoadsPerPlayer) roads.",
                    "Bonuses are worth \(legacy.longestRoadBonus) points each; the discard threshold is \(legacy.discardThreshold).",
                ]
            ))
        }
        return sections
    }

    static func resourceLosses(for context: Context?) -> [ResourceLoss] {
        let threshold = (context?.ruleset ?? classic).discardThreshold
        return [
            ResourceLoss(id: "knight", icon: "shield.fill", title: "Knight", amount: "One card · one rival",
                         explanation: "Move the robber and take one random resource card from one rival beside the new hex. No discard.",
                         example: "A rival holding 9 cards keeps 8 after the theft."),
            ResourceLoss(id: "monopoly", icon: "crown.fill", title: "Monopoly", amount: "One type · every rival",
                         explanation: "Choose a resource. Every rival gives you all cards of that type; their other resources stay put.",
                         example: "Choose Ore: a rival with 4 Ore and 3 Grain gives 4 Ore and keeps 3 Grain."),
            ResourceLoss(id: "seven", icon: "dice.fill", title: "Rolling a seven", amount: "Discard · then steal one",
                         explanation: "Above \(threshold) resources, discard half, rounded down, to the bank. Then the roller moves the robber and steals one card.",
                         example: "With \(threshold + 2) cards, discard \((threshold + 2) / 2). A theft is a separate loss of one card."),
        ]
    }

    private static func conquest(for context: Context?) -> Section {
        let ruleset = context?.mode == .naval ? classic : context?.ruleset ?? classic
        let price = context?.armyPrice ?? .anyThree
        let strengths = ruleset.armyDeck.keys.sorted()
        let strengthRange = "\(strengths.first ?? 1) to \(strengths.last ?? 4)"
        return Section(
            id: "conquest", icon: "shield.lefthalf.filled", title: "Conquest",
            summary: "An extra rule for Classic or Vast: capture hexes with Army cards.",
            details: [
                "Every hex that produces starts held by a tribe. Its strength is how many ways its number can roll: 5 for a 6 or 8, down to 1 for a 2 or 12.",
                "A tribe's hex pays everyone next to it as normal.",
                "Army cards cost \(price.label) and have a strength from \(strengthRange). Everyone starts with one, and you can deploy a card the turn you buy it.",
                "Deploy armies on a hex one of your buildings touches. Beat its strength and the hex is yours; an exact tie leaves it empty.",
                "Once you hold a hex, it pays only you - your usual share, plus one.",
                "Deploying on a hex you already hold makes it harder to take.",
                "Army cards are spent when deployed. You may combine them in an attack. They are not Knight development cards and do not count toward Largest Army.",
                "The robber still blocks an occupied hex. Conquest changes who collects from a hex, not the dice or how many cards a Knight steals.",
            ]
        )
    }

    private static func settlementDescription(isNaval: Bool) -> String {
        let cost = "Settlement: \(costDescription(Building.settlementCost)). "
        return cost + (isNaval
            ? "It must touch your road or a ship beside a legal coastal corner. Keep one empty corner from every other settlement."
            : "It must touch one of your roads and keep one empty corner from every other settlement.")
    }

    private static func voyages(for context: Context?) -> Section {
        let options = context?.mode == .naval ? context?.navalOptions : nil
        let fog = navalDiscoveryDescription(for: context)
        let choices = options?.resourceChoiceEnabled == false
            ? "Resource-choice islands are off for this match. Each producing hex supplies its printed resource."
            : "When a harvest field's number rolls, a settlement chooses 1 resource and a city chooses 2 resources. "
                + "Collect each card separately; choosing the same resource twice is allowed. "
                + "Fixed production happens first; choices use the available bank."
        let target = (context?.mode == .naval ? context?.victoryPointTarget : nil) ?? naval.defaultVictoryPointTarget
        return Section(
            id: "voyages", icon: "sailboat.fill", title: "Naval · Voyages",
            summary: "Buy ships, discover islands and build colonies. First to \(target) points wins.",
            details: [
                "Both starting settlements may be inland or coastal on the home island. Ships launch beside your coastal settlements or cities.",
                "A ship costs \(costDescription(Naval.shipCost)). You may purchase six hulls; capture never refunds a purchased hull.",
                navalSailingDescription(for: context),
                fog,
                "Home-coast harbors are charted from setup. Other harbors appear when their coastline is discovered; "
                    + "a settlement or city on a harbor corner activates its 2:1 or 3:1 trade rate.",
                "World opens the overview. Return restores your previous zoom and position; Home focuses the starting island.",
                "A ship touching a legal coastal corner lets you settle there without a road. The ship stays. "
                    + "Establish your own settlement before building roads on a new island, then expand inland along your roads.",
                "Your first settlement on each of your first two overseas islands earns an extra permanent point. There is no Biggest Navy bonus.",
                "On an 11, collect resources, then capture any opponent's ship anywhere or skip. Its control is yours until another capture; ships are not destroyed.",
                choices,
                "Fog and resource-choice islands are optional before the match. Your shared hand funds building everywhere; ships do not carry cargo.",
                "Choose Archipelago, Peninsula, Twin Islands or Surprise. Every match varies the island shape, coast, resources and numbers.",
                "Longest Road and Largest Army are worth \(naval.longestRoadBonus) and \(naval.largestArmyBonus) points. Ships never count as roads. "
                    + "Discard on a 7 only above \(naval.discardThreshold) cards.",
                "Supply: \(naval.bankPerResource) cards of each resource and \(naval.devCardDeckSize) development cards. Naval is local and unrated; Ghosts and Conquest retain their existing modes.",
            ], cost: Naval.shipCost)
    }

    private static func navalSailingDescription(for context: Context?) -> String {
        let version = context?.navalRulesVersion ?? Naval.currentRulesVersion
        let travel = version < Naval.destinationSailingRulesVersion
            ? "This saved match gives each ship three hexes per turn, sailed one adjacent sea hex at a time."
            : "Each ship can sail up to two sea hexes per turn. Choose any highlighted destination, "
                + "preview its route, then confirm the voyage. Its travel cost is the number of hexes crossed."
        let sharing = version >= Naval.blockadeRulesVersion
            ? "Ships sail independently. Your own ships may share water. Opposing ships block entry, passage and launches."
            : "Ships sail independently and may share water."
        return "\(sharing) \(travel) New or captured ships can sail immediately."
    }

    private static func navalDiscoveryDescription(for context: Context?) -> String {
        if context?.navalOptions?.fogEnabled == false {
            return "Fog is off for this match: sea, islands, numbers and ports are visible from the beginning."
        }
        let buildings = context?.navalRulesVersion == 1
            ? "Settlements survey within two hexes of the land they touch."
            : "Settlements survey within two hexes of their actual corner."
        return "The home island starts charted for setup. \(buildings) Ships reveal within two hexes of their position. "
            + "Mist withdraws and discoveries stay visible for every player."
    }

    private static func costDescription(_ cost: [Resource: Int]) -> String {
        Resource.allCases.filter { cost[$0, default: 0] > 0 }
            .map { "\(cost[$0, default: 0]) \($0.rawValue.capitalized)" }.joined(separator: ", ")
    }
}
