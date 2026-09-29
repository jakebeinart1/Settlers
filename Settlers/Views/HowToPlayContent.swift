import CatanEngine

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
    }

    private static let classic = Ruleset.forMode(.classic)
    private static let vast = Ruleset.forMode(.vast)

    static let steps: [Step] = [
        Step(id: 0, illustration: .victory, title: "The goal",
             line: "Be the first empire to reach \(classic.defaultVictoryPointTarget) victory points."),
        Step(id: 1, illustration: .terrain, title: "The land",
             line: "Each hex makes one resource: Brick, Lumber, Wool, Grain or Ore. The desert makes nothing."),
        Step(id: 2, illustration: .settlement, title: "Settlements",
             line: "Build on the corners of hexes. A settlement is worth 1 point and collects from the hexes it touches.",
             cost: Building.settlementCost),
        Step(id: 3, illustration: .dice, title: "Roll for resources",
             line: "Every turn starts with two dice. Each hex showing that number pays everyone built next to it."),
        Step(id: 4, illustration: .road, title: "Roads",
             line: "Roads run along hex edges and are how you reach new corners to settle.",
             cost: Building.roadCost),
        Step(id: 5, illustration: .city, title: "Cities",
             line: "Upgrade a settlement to a city: 2 points, and double the resources.",
             cost: Building.cityCost),
        Step(id: 6, illustration: .trade, title: "Trade",
             line: "Swap cards with other players, or trade with the bank at 4 for 1 - better at a port."),
        Step(id: 7, illustration: .robber, title: "The robber",
             line: "Roll a 7 and nobody collects. You move the robber to block a hex and steal a card."),
        Step(id: 8, illustration: .cards, title: "Development cards",
             line: "Buy a hidden card: a Knight, a free bonus, or a secret victory point.",
             cost: Building.devCardCost),
        Step(id: 9, illustration: .victory, title: "Win",
             line: "Points come from settlements, cities, bonuses and cards. The first to \(classic.defaultVictoryPointTarget) wins at once."),
    ]

    static let rules: [Section] = [
        Section(
            id: "goal", icon: "star.fill", title: "Goal",
            summary: "First to \(classic.defaultVictoryPointTarget) victory points wins.",
            details: [
                "A settlement is worth \(classic.victoryPoints(for: .settlement)) point and a city \(classic.victoryPoints(for: .city)).",
                "Longest Road and Largest Army are worth \(classic.longestRoadBonus) points each while you hold them.",
                "Victory point cards count too, and stay hidden from the others.",
                "The game ends the moment anyone reaches the target.",
                "New Classic games are played to \(classic.defaultVictoryPointTarget) points.",
            ]
        ),
        Section(
            id: "setup", icon: "flag.fill", title: "Starting the game",
            summary: "Everyone places two settlements and two roads for free.",
            details: [
                "Seats place in order, then in reverse order, so the last seat places twice in a row.",
                "Each settlement comes with one road touching it.",
                "Your second settlement pays you one of each resource around it straight away.",
                "No two settlements may sit on neighbouring corners - there must be at least one empty corner between them.",
            ]
        ),
        Section(
            id: "turn", icon: "arrow.triangle.2.circlepath", title: "Your turn",
            summary: "Roll, then trade and build in any order, then end your turn.",
            details: [
                "The dice pay every player with a building next to a hex showing the rolled number - not just you.",
                "A settlement collects 1 card from each matching hex; a city collects 2.",
                "Numbers near 7 come up most often and 2 and 12 rarely - the chart below counts the ways each total can roll, out of 36.",
                "You can trade and build as many times as you can afford before ending your turn.",
            ],
            showsRollOdds: true
        ),
        Section(
            id: "build", icon: "hammer.fill", title: "Building",
            summary: "Spend resources on roads, settlements, cities and development cards.",
            details: [
                "Road: 1 Brick, 1 Lumber. It must connect to your own road or building.",
                "Settlement: 1 Brick, 1 Lumber, 1 Wool, 1 Grain. It must touch one of your roads and keep one empty corner from every other settlement.",
                "City: 3 Ore, 2 Grain. It replaces one of your settlements, which goes back to your supply.",
                "Development card: 1 Ore, 1 Wool, 1 Grain.",
                "In Classic you have \(classic.pieceLimit(for: .settlement)) settlements, \(classic.pieceLimit(for: .city)) cities and \(classic.maxRoadsPerPlayer) roads.",
            ]
        ),
        Section(
            id: "trade", icon: "arrow.left.arrow.right", title: "Trading",
            summary: "Trade with players, or with the bank at 4 for 1.",
            details: [
                "On your turn you can offer any cards to the other players. They can accept or decline.",
                "The bank always takes 4 of one resource for 1 of any other.",
                "A 3:1 port takes 3 of any one resource. A resource port takes 2 of its own resource.",
                "You use a port by having a settlement or city on one of its two corners.",
            ]
        ),
        Section(
            id: "robber", icon: "exclamationmark.shield.fill", title: "Rolling a 7 and the robber",
            summary: "A 7 pays nobody. The roller moves the robber and steals a card.",
            details: [
                "Anyone holding more than \(classic.discardThreshold) resource cards discards half of them, rounded down.",
                "The robber moves to any other hex. That hex produces nothing while the robber sits on it.",
                "The roller steals one random card from a player with a building next to the robber's new hex.",
                "A Knight card moves the robber the same way, without the discard.",
            ]
        ),
        Section(
            id: "cards", icon: "rectangle.portrait.on.rectangle.portrait.fill", title: "Development cards",
            summary: "Hidden cards bought from the deck. Play at most one per turn.",
            details: [
                "Knight: move the robber and steal a card. Played Knights count toward Largest Army.",
                "Road Building: place 2 roads for free.",
                "Year of Plenty: take any 2 resource cards from the bank.",
                "Monopoly: name a resource; every other player gives you all of theirs.",
                "Victory Point: worth 1 point. It is never played - it just counts.",
                "A card cannot be played on the turn you bought it.",
            ]
        ),
        Section(
            id: "bonuses", icon: "rosette", title: "Longest Road and Largest Army",
            summary: "Two bonus cards worth \(classic.longestRoadBonus) points each, and they can be taken from you.",
            details: [
                "Longest Road: the first player with an unbroken road of \(classic.longestRoadMinimum) or more. Someone who builds a longer one takes it.",
                "Another player's settlement built in the middle of your road breaks it.",
                "Largest Army: the first player to play \(classic.largestArmyMinimum) Knights. Someone who plays more takes it.",
                "A tie does not take the bonus - the current holder keeps it.",
            ]
        ),
    ]

    static let modes: [Section] = [
        Section(
            id: "classic", icon: "hexagon.fill", title: "Classic",
            summary: "The main game: the \(classic.board.tileCount)-hex island, played to \(classic.defaultVictoryPointTarget) points.",
            details: [
                "Everything in Rules above describes Classic.",
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
                "The bank and the development deck are bigger to match.",
            ]
        ),
        Section(
            id: "conquest", icon: "shield.lefthalf.filled", title: "Conquest",
            summary: "An extra rule for Classic or Vast: capture hexes with Army cards.",
            details: [
                "Every hex that produces starts held by a tribe. Its strength is how many ways its number can roll: 5 for a 6 or 8, down to 1 for a 2 or 12.",
                "A tribe's hex pays everyone next to it as normal.",
                "Army cards cost any 3 resource cards and have a strength from 1 to 4. Everyone starts with one, and you can deploy a card the turn you buy it.",
                "Deploy armies on a hex one of your buildings touches. Beat its strength and the hex is yours; an exact tie leaves it empty.",
                "Once you hold a hex, it pays only you - your usual share, plus one.",
                "Deploying on a hex you already hold makes it harder to take.",
            ]
        ),
    ]
}
