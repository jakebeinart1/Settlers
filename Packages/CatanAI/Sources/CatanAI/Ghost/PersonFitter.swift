import CatanEngine
import Foundation

public struct FitOptions: Sendable {
    public var iterations = 3000
    public var learningRate = 0.02
    /// Pull of each weight toward Expert's, in units of the weight's own size.
    public var weightPrior = 1.0
    /// Pull of each habit toward "no habit".
    public var stylePrior = 0.1
    public init() {}
}

/// Maximum-likelihood fit of a `PersonModel`, pulled toward Expert.
///
/// ## Why a prior
/// A few games say little about rare decisions. With no pull, a weight nobody's
/// choices touched drifts on noise. With the pull, it stays at Expert's value:
/// thin data yields Expert's play, not random play. This is Maia4All's lesson
/// (a strong shared base plus a small personal part) in 24 numbers instead of a
/// network.
public enum PersonFitter {

    static let slots = EvaluationWeights.vectorLabels.count
    static var betaIndex: Int { slots }

    /// - Parameters:
    ///   - anchor: Expert's weights, which the prior pulls toward.
    ///   - start: where to begin, usually the previous round's fit when the
    ///     decisions were re-linearised there. Defaults to Expert.
    public static func fit(_ decisions: [DecisionRecord], anchor: EvaluationWeights,
                           start: PersonModel? = nil, options: FitOptions = FitOptions()) -> PersonModel {
        let start = start ?? PersonModel.anchored(at: anchor)
        guard !decisions.isEmpty else { return start }
        let movable = movableSlots(decisions)
        var params = pack(start)
        var adam = Adam(count: params.count)
        for _ in 0..<options.iterations {
            let grad = gradient(unpack(params), decisions: decisions, anchor: anchor.vector,
                                movable: movable, options: options)
            adam.step(&params, grad, rate: options.learningRate)
            params[betaIndex] = max(params[betaIndex], 0.01) // beta stays positive
        }
        return unpack(params)
    }

    /// Weights some decision's score actually depends on, minus the frozen ones.
    static func movableSlots(_ decisions: [DecisionRecord]) -> [Bool] {
        (0..<slots).map { slot in
            !DecisionExtractor.frozen.contains(slot)
                && decisions.contains { $0.candidates.contains { $0.gradient[slot] != 0 } }
        }
    }

    static func pack(_ model: PersonModel) -> [Double] { model.weights + [model.beta] + model.theta }

    static func unpack(_ params: [Double]) -> PersonModel {
        PersonModel(weights: Array(params[0..<slots]), beta: params[betaIndex], theta: Array(params[(slots + 1)...]))
    }

    /// Gradient of (mean negative log-likelihood + priors), in `pack` order.
    ///
    /// Each candidate's personal score is computed once and reused for its
    /// logit and the beta term, over movable slots only. The fit runs thousands
    /// of passes, and recomputing it made a 1,500-decision fit take minutes.
    static func gradient(_ model: PersonModel, decisions: [DecisionRecord], anchor: [Double],
                         movable: [Bool], options: FitOptions) -> [Double] {
        var grad = [Double](repeating: 0, count: slots + 1 + model.theta.count)
        let count = Double(decisions.count)
        let active = (0..<slots).filter { movable[$0] }
        let delta = (0..<slots).map { model.weights[$0] - anchor[$0] }
        for decision in decisions {
            let scores = decision.candidates.map { candidate in
                active.reduce(candidate.score) { $0 + candidate.gradient[$1] * delta[$1] }
            }
            let logits = zip(scores, decision.candidates).map { model.beta * $0 + model.habit($1.style) }
            let top = logits.max() ?? 0
            let exps = logits.map { exp($0 - top) }
            let total = exps.reduce(0, +)
            for (index, candidate) in decision.candidates.enumerated() {
                let residual = (exps[index] / total - (index == decision.chosen ? 1 : 0)) / count
                for slot in active { grad[slot] += residual * model.beta * candidate.gradient[slot] }
                grad[betaIndex] += residual * scores[index]
                for feature in candidate.style.indices where candidate.style[feature] != 0 {
                    grad[slots + 1 + feature] += residual * candidate.style[feature]
                }
            }
        }
        for slot in active {
            let scale = max(abs(anchor[slot]), 0.05)
            grad[slot] += 2 * options.weightPrior * delta[slot] / (scale * scale) / count
        }
        for feature in model.theta.indices {
            grad[slots + 1 + feature] += 2 * options.stylePrior * model.theta[feature] / count
        }
        return grad
    }
}

/// Adam, because the weights, beta and habits live on very different scales.
struct Adam {
    private var first: [Double]
    private var second: [Double]
    private var steps = 0

    init(count: Int) {
        first = [Double](repeating: 0, count: count)
        second = first
    }

    mutating func step(_ params: inout [Double], _ grad: [Double], rate: Double) {
        steps += 1
        let firstCorrection = 1 - pow(0.9, Double(steps))
        let secondCorrection = 1 - pow(0.999, Double(steps))
        for index in params.indices {
            first[index] = 0.9 * first[index] + 0.1 * grad[index]
            second[index] = 0.999 * second[index] + 0.001 * grad[index] * grad[index]
            params[index] -= rate * (first[index] / firstCorrection) / (sqrt(second[index] / secondCorrection) + 1e-8)
        }
    }
}
