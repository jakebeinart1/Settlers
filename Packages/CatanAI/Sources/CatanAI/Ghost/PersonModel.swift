import CatanEngine
import Foundation

/// How likely one person is to make each candidate move.
///
/// `P(m) ∝ exp(beta · S_w(m) + theta · style(m))`, where `S_w` is Expert's
/// score under this person's weights. `weights` says what they value, `beta`
/// how consistently they play their own best move, and `theta` the habits the
/// score cannot see.
///
/// ## The lapse rate
/// A share of choices, `lapse`, is treated as made for reasons the model
/// cannot see: `P'(m) = (1 - lapse) · P(m) + lapse / n`. Fitting Jake without
/// it, 3% of his turns offered a candidate scored ~992 (a trade that would win
/// if a bot accepted, which none does) that he rightly ignored, and those few
/// decisions drove `beta` to its floor. With it, no single decision can cost
/// more than `log(lapse / n)`.
public struct PersonModel: Codable, Sendable, Equatable {
    public static let defaultLapse = 0.05

    public var weights: [Double]
    public var beta: Double
    public var theta: [Double]
    public var lapse: Double

    public init(weights: [Double], beta: Double, theta: [Double], lapse: Double = PersonModel.defaultLapse) {
        self.weights = weights
        self.beta = beta
        self.theta = theta
        self.lapse = lapse
    }

    private enum CodingKeys: String, CodingKey { case weights, beta, theta, lapse }

    /// A model saved before the lapse rate existed decodes with the default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        weights = try values.decode([Double].self, forKey: .weights)
        beta = try values.decode(Double.self, forKey: .beta)
        theta = try values.decode([Double].self, forKey: .theta)
        lapse = try values.decodeIfPresent(Double.self, forKey: .lapse) ?? Self.defaultLapse
    }

    public static func anchored(at anchor: EvaluationWeights) -> PersonModel {
        PersonModel(weights: anchor.vector, beta: 1, theta: [Double](repeating: 0, count: StyleFeatures.labels.count))
    }

    /// Score under this person's weights, by the recorded slope.
    public func personalScore(_ candidate: CandidateRecord, anchor: [Double]) -> Double {
        var shift = 0.0
        for slot in candidate.gradient.indices { shift += candidate.gradient[slot] * (weights[slot] - anchor[slot]) }
        return candidate.score + shift
    }

    public func habit(_ style: [Double]) -> Double {
        zip(theta, style).reduce(0) { $0 + $1.0 * $1.1 }
    }

    public func logits(_ decision: DecisionRecord) -> [Double] {
        decision.candidates.map { beta * personalScore($0, anchor: decision.anchor) + habit($0.style) }
    }

    /// With the lapse blended in.
    public func probabilities(_ decision: DecisionRecord) -> [Double] {
        let choice = Self.softmax(logits(decision))
        let floor = lapse / Double(choice.count)
        return choice.map { (1 - lapse) * $0 + floor }
    }

    static func softmax(_ logits: [Double]) -> [Double] {
        let top = logits.max() ?? 0
        let exps = logits.map { exp($0 - top) }
        let total = exps.reduce(0, +)
        return exps.map { $0 / total }
    }

    /// Ties go to the earlier candidate, as in `EvaluationPolicy.best`.
    public func top1Accuracy(_ decisions: [DecisionRecord]) -> Double {
        guard !decisions.isEmpty else { return 0 }
        let hits = decisions.filter { decision in
            let logits = logits(decision)
            return logits.firstIndex(of: logits.max()!) == decision.chosen
        }.count
        return Double(hits) / Double(decisions.count)
    }

    public func meanLogLikelihood(_ decisions: [DecisionRecord]) -> Double {
        guard !decisions.isEmpty else { return 0 }
        let total = decisions.reduce(0) { $0 + log(max(probabilities($1)[$1.chosen], 1e-300)) }
        return total / Double(decisions.count)
    }
}
