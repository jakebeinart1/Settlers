import CatanAI
import CatanEngine
import Foundation

// What each trade model actually does, in real games, in about a minute.
//
// ## Why this exists next to `sim`
// `sim` answers "does this win more games", which needs 1,248 rotated games
// per arm and twenty minutes. Most questions about trading are not that
// question: what does it offer, who takes it, what does it give away, does it
// finish a build. Those need far fewer games, and waiting twenty minutes to
// see them made every trading experiment slow enough to guess instead of
// measure.
//
// ## It is the real game, not a model of one
// Every number here comes from `GameSession` driving the real engine: real
// legal moves, the real ledger, real shipping-bot opponents deciding for
// themselves whether to accept. Nothing about trading is simulated
// separately - an earlier version scored acceptance with Expert's *model* of
// an opponent, and that exact mistake cost the first cascade twenty points.
// The one thing this does not do is play enough games to measure a win rate,
// so it never reports one. Strength claims still come from `sim`.
//
// Usage: trade-bench [--games N] [--seed S] [--mode classic|expanded]

struct Options {
    var games = 24
    var seed: UInt64 = 900_000
    var mode = GameMode.classic
}

func parse() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while let flag = arguments.first {
        arguments.removeFirst()
        guard let raw = arguments.first else { break }
        arguments.removeFirst()
        switch flag {
        case "--games": options.games = Int(raw) ?? options.games
        case "--seed": options.seed = UInt64(raw) ?? options.seed
        case "--mode": options.mode = GameMode(rawValue: raw) ?? .classic
        default:
            FileHandle.standardError.write(Data("trade-bench: unknown flag \(flag)\n".utf8))
            exit(2)
        }
    }
    return options
}

struct Tally {
    var games = 0, turns = 0, offers = 0, accepted = 0, refused = 0
    var bundles = 0, bundlesAccepted = 0
    var given = 0, received = 0
    var acceptedAfterRefusal = 0, unlockedBuild = 0
    var cities = 0, settlements = 0, victoryPoints = 0
    var wins = 0
}

/// Does this offer make a settlement or city affordable that was not?
func unlocksABuild(_ give: [Resource: Int], _ want: [Resource: Int], hand: [Resource: Int]) -> Bool {
    func affords(_ cost: [Resource: Int], _ holding: [Resource: Int]) -> Bool {
        Resource.allCases.allSatisfy { (holding[$0] ?? 0) >= (cost[$0] ?? 0) }
    }
    var after = hand
    for resource in Resource.allCases {
        after[resource] = (hand[resource] ?? 0) - (give[resource] ?? 0) + (want[resource] ?? 0)
    }
    return [Building.cityCost, Building.settlementCost].contains {
        affords($0, after) && !affords($0, hand)
    }
}

func play(_ model: EvaluationPolicy.TradeModel, _ options: Options) -> Tally {
    var tally = Tally()
    let shape = Ruleset.forMode(options.mode).board
    for offset in 0..<options.games {
        let seed = options.seed &+ UInt64(offset)
        let state = GameSetup.newGame(
            board: BoardGenerator.randomized(seed: seed, shape: shape), seed: seed, mode: options.mode
        )
        let seat = state.players[0].id
        var policies: [PlayerID: any Policy] = [:]
        for player in state.players {
            policies[player.id] = player.id == seat
                ? EvaluationPolicy(tradeModel: model)
                : HeuristicPolicy(personality: .balanced, id: "balanced")
        }
        var session = GameSession(state: state, policies: policies, policySeed: seed &* 31 &+ 7)
        var refusalsThisTurn = 0

        for _ in 0..<6_000 {
            guard let decision = session.decideNextDetailed() else { break }
            let handBefore = session.state.players[0].resources
            guard let step = try? session.commit(seat: decision.seat, move: decision.move) else { break }
            for event in step.events {
                switch event {
                case .proposedTrade(let who, let give, let want) where who == seat:
                    tally.offers += 1
                    tally.given += Resource.allCases.reduce(0) { $0 + (give[$1] ?? 0) }
                    tally.received += Resource.allCases.reduce(0) { $0 + (want[$1] ?? 0) }
                    if give.count + want.count > 2 { tally.bundles += 1 }
                    if unlocksABuild(give, want, hand: handBefore) { tally.unlockedBuild += 1 }
                case .acceptedTrade(_, let from, let gave, let got) where from == seat:
                    tally.accepted += 1
                    if gave.count + got.count > 2 { tally.bundlesAccepted += 1 }
                    if refusalsThisTurn > 0 { tally.acceptedAfterRefusal += 1 }
                case .rejectedTrade(_, let from) where from == seat:
                    tally.refused += 1
                    refusalsThisTurn += 1
                case .builtCity(let who) where who == seat: tally.cities += 1
                case .builtSettlement(let who) where who == seat: tally.settlements += 1
                case .endedTurn(let who) where who == seat:
                    tally.turns += 1
                    refusalsThisTurn = 0
                case .gameWon(let who): if who == seat { tally.wins += 1 }
                default: break
                }
            }
            if case .gameOver = session.state.phase { break }
        }
        tally.games += 1
        tally.victoryPoints += session.state.victoryPoints(for: seat)
    }
    return tally
}

let options = parse()
let started = Date()
print("\(options.games) real games per model, \(options.mode.displayName), "
    + "Expert in seat 0 against three shipping bots\n")
let columns = ["model", "offers/turn", "taken", "take-rate", "given", "got",
               "bundles", "unlocks", "after refusal", "cities", "VP"]
print(columns.joined(separator: "  "))
for model in [EvaluationPolicy.TradeModel.roundThree, .current, .worthIt] {
    let label = ["roundThree": "round3", "current": "cascade", "worthIt": "worthIt"]["\(model)"] ?? "\(model)"
    let t = play(model, options)
    let per = { (value: Int, base: Int) in Double(value) / Double(max(1, base)) }
    print(String(
        format: "%-7@ %11.2f %6d %8.0f%% %6.2f %5.2f %8d %8d %14d %7.1f %5.1f",
        label as NSString, per(t.offers, t.turns), t.accepted,
        100 * per(t.accepted, t.offers), per(t.given, t.offers), per(t.received, t.offers),
        t.bundles, t.unlockedBuild, t.acceptedAfterRefusal,
        per(t.cities, t.games), per(t.victoryPoints, t.games)
    ))
}
print("\n\(String(format: "%.0f", -started.timeIntervalSinceNow))s. Win rates are NOT measured here - use sim.")
