import CatanAI
import CatanEngine

/// Anchors delegate once to their original policy; heuristics delegate once
/// to the same Bot with same-call assessment capture. No diagnostic rescore
/// and no extra RNG draw is allowed. GameSession may subsequently override
/// the return with its runaway backstop; the commit records that separately.
struct CorpusPolicy: Policy {
    let base: any Policy
    let bot: Bot?
    let writer: CorpusWriter

    var id: String { base.id }

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        writer.decide(policyID: id, observation: observation, rng: &rng) { random, assessments in
            if let bot {
                return bot.decide(for: observation.state, player: observation.seat,
                                  legalMoves: observation.legalMoves, rng: &random,
                                  assessments: &assessments)
            }
            return base.decide(observation, rng: &random)
        }
    }
}
