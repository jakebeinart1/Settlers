import CatanEngine
import Foundation

public struct FitOptions: Sendable {
    public var iterations = 3000
    public var learningRate = 0.02
    /// Pull of each weight toward Expert's, in units of the weight's own size.
    public var weightPrior = 1.0
    /// Pull of each habit toward "no habit".
    public var stylePrior = 0.1
    /// How far one fit may move a weight from where it started, in units of
    /// the weight's own size. The slopes it fits on hold only near that point;
    /// further moves wait for the next re-linearised round.
    public var trustRadius = 0.5
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
        let bounds = weightBounds(start: start, anchor: anchor.vector, radius: options.trustRadius)
        var params = pack(start)
        var adam = Adam(count: params.count)
        for _ in 0..<options.iterations {
            let grad = gradient(unpack(params, like: start), decisions: decisions, anchor: anchor.vector,
                                movable: movable, options: options)
            adam.step(&params, grad, rate: options.learningRate)
            params[betaIndex] = max(params[betaIndex], 0.01) // beta stays positive
            for slot in 0..<slots { params[slot] = min(max(params[slot], bounds[slot].lower), bounds[slot].upper) }
        }
        return unpack(params, like: start)
    }

    /// The trust region around `start`, never crossing zero from Expert's side.
    ///
    /// Found fitting Jake: unbounded, `rival` went 0.80 -> -1.48 ("wants
    /// opponents to do well") and the linearisation drift rose to 2.5. A
    /// negative `approach` or a positive `sevenLoss` means nothing in the game,
    /// which is why Expert's own sweep keeps each sign too.
    static func weightBounds(start: PersonModel, anchor: [Double], radius: Double) -> [(lower: Double, upper: Double)] {
        (0..<slots).map { slot in
            let reach = radius * max(abs(anchor[slot]), 0.05)
            var lower = start.weights[slot] - reach
            var upper = start.weights[slot] + reach
            if anchor[slot] > 0 { lower = max(lower, 0) }
            if anchor[slot] < 0 { upper = min(upper, 0) }
            return (lower, upper)
        }
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

    static func unpack(_ params: [Double], like model: PersonModel) -> PersonModel {
        var unpacked = unpack(params)
        unpacked.lapse = model.lapse
        return unpacked
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
            let choice = PersonModel.softmax(logits)
            // d log P'(chosen) / d logit = share · (onehot - choice), where share
            // is how much of P'(chosen) the model (not the lapse) accounts for.
            let chosen = choice[decision.chosen]
            let share = (1 - model.lapse) * chosen / ((1 - model.lapse) * chosen + model.lapse / Double(choice.count))
            for (index, candidate) in decision.candidates.enumerated() {
                let residual = share * (choice[index] - (index == decision.chosen ? 1 : 0)) / count
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
