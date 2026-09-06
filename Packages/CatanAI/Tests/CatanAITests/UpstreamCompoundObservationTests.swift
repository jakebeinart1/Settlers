import Foundation
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct UpstreamCompoundObservationTests {
    @Test(arguments: [3, 4], CompoundObservationFixture.Scenario.allCases)
    func policyStagesMatchRust(players: Int, scenario: CompoundObservationFixture.Scenario) throws {
        let frames = try CompoundObservationFixture.load(players: players, scenario: scenario)
        try #require(frames.map(\.stage) == scenario.stages)
        let root = try #require(frames.first)
        let state = root.nativeRoot()
        let seat = PlayerID(index: root.position.seat)
        let observation = GameObservation(seat: seat, state: state,
                                          legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
        let recorder = CompoundEncoderRecorder(actions: frames.map(\.action))
        var rng = RandomSource(seed: 73)
        let originalRNG = rng
        let selection = recorder.policy().select(observation, rng: &rng)
        #expect(selection.source == "neural" && selection.fallbackReason == nil)
        #expect(selection.move == (try root.expectedMove(frames)))
        #expect(observation.legalMoves.contains(selection.move))
        #expect(observation.state == state && rng == originalRNG)
        try compare(recorder.vectors, with: frames)
        var committed = state
        try RulesEngine.apply(selection.move, by: seat, to: &committed)
    }

    private func compare(_ actual: [[Float]], with frames: [CompoundObservationFixture]) throws {
        try #require(actual.count == frames.count, "every non-singleton Rust stage must reach the real Swift encoder")
        for (vector, frame) in zip(actual, frames) {
            let expected = frame.position.features
            try #require(vector.count == UpstreamObservation.count && expected.count == vector.count)
            for slot in vector.indices {
                #expect(abs(vector[slot] - expected[slot]) < 0.000_001,
                        "\(frame.scenario.rawValue)/\(frame.stage), \(frame.position.players) seats, slot \(slot)")
            }
        }
    }
}

/// Only logits are prescribed. The policy supplies its own native private
/// staged state/context, which this seam forwards unmodified to the production
/// encoder. Rust's independently executed stages are the feature-value oracle.
private final class CompoundEncoderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let actions: [Int]
    private var captured: [[Float]] = []

    init(actions: [Int]) { self.actions = actions }

    var vectors: [[Float]] { lock.withLock { captured } }

    func policy() -> UpstreamPolicy {
        UpstreamPolicy(fallback: HeuristicPolicy(personality: .balanced, id: "compound-test-fallback"),
                       predict: { self.predict($0) }, encode: { try self.encode($0, $1, $2) })
    }

    private func encode(_ state: GameState, _ seat: PlayerID, _ context: UpstreamDecisionContext?) throws -> [Float] {
        let vector = try UpstreamObservation.encode(state: state, seat: seat, context: context)
        lock.withLock { captured.append(vector) }
        return vector
    }

    private func predict(_ vector: [Float]) -> (logits: [Float], value: Float) {
        lock.withLock {
            let index = captured.count - 1
            var logits = [Float](repeating: 0, count: UpstreamActions.count)
            if actions.indices.contains(index) { logits[actions[index]] = 1 }
            #expect(captured.last == vector, "the predictor must receive the actual encoded vector")
            return (logits, 0)
        }
    }
}

struct CompoundObservationFixture: Decodable {
    enum Scenario: String, Decodable, CaseIterable {
        case roadBuilding = "road-building"
        case knightPreRoll = "knight-pre-roll"
        case knightMain = "knight-main"
        case discardFirst = "discard-seat-0"
        case discardSecond = "discard-seat-1"

        var stages: [String] {
            switch self {
            case .roadBuilding: ["root", "first-road", "second-road"]
            case .knightPreRoll, .knightMain: ["root", "move-robber", "choose-victim"]
            case .discardFirst, .discardSecond: (1...4).map { "discard-\($0)" }
            }
        }
    }

    let scenario: Scenario
    let stage: String
    let action: Int
    let position: UpstreamObservationFixture

    enum CodingKeys: String, CodingKey {
        case scenario = "case"
        case stage, action, position
    }

    static func load(players: Int, scenario: Scenario) throws -> [Self] {
        let url = try #require(Bundle.module.url(forResource: "upstream-compound-observations",
                                                 withExtension: "jsonl", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode(Self.self, from: Data($0.utf8))
        }.filter { $0.position.players == players && $0.scenario == scenario }
    }

    func nativeRoot() -> GameState {
        var state = position.makeState()
        switch scenario {
        case .roadBuilding, .knightMain:
            state.phase = .mainTurn(playerIndex: position.turnOwner)
        case .knightPreRoll:
            state.phase = .rollDice(playerIndex: position.turnOwner)
        case .discardFirst, .discardSecond:
            let pending = state.players.filter { $0.resources.values.reduce(0, +) > 7 }.map(\.id)
            state.phase = .discarding(pending: Set(pending))
            state.robberMoverIndex = position.turnOwner
            #expect(position.seat != position.turnOwner)
        }
        return state
    }

    func expectedMove(_ frames: [Self]) throws -> GameMove {
        let layout = try UpstreamBoardLayout(board: nativeRoot().board)
        switch scenario {
        case .roadBuilding:
            return .playRoadBuilding(layout.edges[frames[1].action - UpstreamCodec.Action.roadOffset],
                                     layout.edges[frames[2].action - UpstreamCodec.Action.roadOffset])
        case .knightPreRoll, .knightMain:
            let relative = frames[2].action - UpstreamCodec.Action.victimRelativeOffset
            let victim = PlayerID(index: (position.seat + relative) % position.players)
            return .playKnight(moveRobberTo: layout.tiles[frames[1].action - UpstreamCodec.Action.robberTiles.lowerBound],
                               stealFrom: victim)
        case .discardFirst, .discardSecond:
            var bundle: [Resource: Int] = [:]
            for frame in frames { bundle[UpstreamCodec.resources[frame.action - UpstreamCodec.Action.discardOffset], default: 0] += 1 }
            return .discard(bundle)
        }
    }
}
