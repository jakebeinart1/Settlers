import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostPersonModelTests {

    private let anchor = EvaluationWeights.forMode(.classic)
    private let styleCount = StyleFeatures.labels.count
    private let slotCount = EvaluationWeights.vectorLabels.count

    /// A known person: values production more than Expert, is sharp, loves proposing, hates ending turns.
    private var truth: PersonModel {
        var model = PersonModel.anchored(at: anchor)
        model.weights[1] += 0.3
        model.beta = 3
        model.theta[0] = 1.5
        model.theta[10] = -1.0
        return model
    }

    private func candidate(_ rng: inout RandomSource) -> CandidateRecord {
        var gradient = [Double](repeating: 0, count: slotCount)
        gradient[1] = Double.random(in: -1...1, using: &rng)
        var style = [Double](repeating: 0, count: styleCount)
        style[0] = Double.random(in: 0...1, using: &rng) < 0.3 ? 1 : 0
        style[10] = Double.random(in: 0...1, using: &rng) < 0.3 ? 1 : 0
        return CandidateRecord(move: .endTurn, score: Double.random(in: -1...1, using: &rng), gradient: gradient, style: style)
    }

    private func synthetic(count: Int, seed: UInt64) -> [DecisionRecord] {
        var rng = RandomSource(seed: seed)
        return (0..<count).map { index in
            let candidates = (0..<6).map { _ in candidate(&rng) }
            let draft = DecisionRecord(game: "s\(index % 20)", facet: .turn, anchor: anchor.vector, candidates: candidates, chosen: 0)
            let probabilities = truth.probabilities(draft)
            var roll = Double.random(in: 0..<1, using: &rng)
            var chosen = 0
            while chosen < probabilities.count - 1, roll >= probabilities[chosen] {
                roll -= probabilities[chosen]
                chosen += 1
            }
            return DecisionRecord(game: draft.game, facet: .turn, anchor: draft.anchor, candidates: candidates, chosen: chosen)
        }
    }

    @Test func probabilitiesSumToOne() {
        let decision = synthetic(count: 1, seed: 1)[0]
        #expect(abs(PersonModel.anchored(at: anchor).probabilities(decision).reduce(0, +) - 1) < 1e-9)
    }

    @Test func theFitRecoversAKnownPerson() {
        // Small enough for a debug-build test run; `ghost selftest` is the full-size check.
        let train = synthetic(count: 800, seed: 2)
        let heldOut = synthetic(count: 300, seed: 3)
        var options = FitOptions()
        options.iterations = 1000
        options.learningRate = 0.05
        let fitted = PersonFitter.fit(train, anchor: anchor, options: options)
        #expect(fitted.theta[0] > 0.9, "proposal habit not recovered: \(fitted.theta[0])")
        #expect(fitted.theta[10] < -0.5, "end-turn aversion not recovered: \(fitted.theta[10])")
        #expect(fitted.weights[1] - anchor.vector[1] > 0.1, "production shift not recovered: \(fitted.weights[1])")
        #expect((1.5...5).contains(fitted.beta), "beta \(fitted.beta)")
        #expect(fitted.meanLogLikelihood(heldOut) > PersonModel.anchored(at: anchor).meanLogLikelihood(heldOut))
    }

    @Test func frozenSlotsNeverMove() {
        var options = FitOptions()
        options.iterations = 200
        let fitted = PersonFitter.fit(synthetic(count: 300, seed: 4), anchor: anchor, options: options)
        for slot in DecisionExtractor.frozen.sorted() { #expect(fitted.weights[slot] == anchor.vector[slot]) }
    }

    /// Found fitting Jake: 3% of his turns had a candidate scored ~992 (a
    /// trade that would win if a bot accepted, which no bot does) that he
    /// rightly ignored. Without a lapse rate those few decisions drove beta to
    /// its floor, and the model stopped using Expert's scores at all.
    @Test func aFewAbsurdlyScoredOptionsDoNotCollapseBeta() {
        let clean = synthetic(count: 600, seed: 6)
        let poisoned = clean.enumerated().map { index, decision -> DecisionRecord in
            guard index % 33 == 0 else { return decision }
            var candidates = decision.candidates
            let spare = decision.chosen == 0 ? 1 : 0
            let old = candidates[spare]
            candidates[spare] = CandidateRecord(move: old.move, score: 990, gradient: old.gradient, style: old.style)
            return DecisionRecord(game: decision.game, facet: decision.facet, anchor: decision.anchor,
                                  candidates: candidates, chosen: decision.chosen)
        }
        var options = FitOptions()
        options.iterations = 800
        options.learningRate = 0.05
        let fitted = PersonFitter.fit(poisoned, anchor: anchor, options: options)
        #expect(fitted.beta > 1.5, "beta collapsed to \(fitted.beta)")
    }

    /// Found fitting Jake: `rival` went 0.80 -> -1.48, i.e. "wants opponents to
    /// do well", and the linearisation drift rose to 2.5. Expert's own sweep
    /// keeps each weight's sign for the same reason; a fit round also may only
    /// move a weight within a trust region, where its slopes still hold.
    @Test func weightsKeepTheirSignAndStayInTheTrustRegion() {
        // A person pushed hard against production: the unbounded fit drives it negative.
        var pushed = synthetic(count: 300, seed: 7).map { decision -> DecisionRecord in
            let candidates = decision.candidates.map {
                CandidateRecord(move: $0.move, score: $0.score, gradient: $0.gradient.map { $0 * -5 }, style: $0.style)
            }
            return DecisionRecord(game: decision.game, facet: decision.facet, anchor: decision.anchor,
                                  candidates: candidates, chosen: decision.chosen)
        }
        pushed = Array(pushed)
        var options = FitOptions()
        options.iterations = 400
        options.learningRate = 0.05
        let start = PersonModel.anchored(at: anchor)
        let fitted = PersonFitter.fit(pushed, anchor: anchor, start: start, options: options)
        for slot in anchor.vector.indices {
            #expect(fitted.weights[slot] * anchor.vector[slot] >= 0, "\(EvaluationWeights.vectorLabels[slot]) flipped sign")
            let reach = options.trustRadius * max(abs(anchor.vector[slot]), 0.05)
            #expect(abs(fitted.weights[slot] - start.weights[slot]) <= reach + 1e-9)
        }
    }

    /// Final review, Critical: re-linearised rounds store records whose
    /// `anchor` is the previous round's weights, but the fitter measured the
    /// shift from Expert's. Its gradient must be the derivative of the
    /// likelihood `PersonModel` reports, on records anchored anywhere.
    @Test func theGradientMatchesTheLikelihoodOnRelinearisedRecords() {
        var shiftedAnchor = anchor.vector
        shiftedAnchor[1] += 0.2
        let records = synthetic(count: 50, seed: 8).map {
            DecisionRecord(game: $0.game, facet: $0.facet, anchor: shiftedAnchor, candidates: $0.candidates, chosen: $0.chosen)
        }
        var model = PersonModel.anchored(at: anchor)
        model.weights[1] = shiftedAnchor[1] + 0.05
        model.beta = 2
        var options = FitOptions()
        options.weightPrior = 0
        options.stylePrior = 0
        let movable = PersonFitter.movableSlots(records)
        let analytic = PersonFitter.gradient(model, decisions: records, anchor: anchor.vector, movable: movable, options: options)
        let step = 1e-5
        var up = model
        up.weights[1] += step
        var down = model
        down.weights[1] -= step
        let numeric = -(up.meanLogLikelihood(records) - down.meanLogLikelihood(records)) / (2 * step)
        #expect(abs(analytic[1] - numeric) < 1e-4, "analytic \(analytic[1]) vs numeric \(numeric)")
    }

    /// Re-linearising needs the fit to resume from the last round's person,
    /// while the prior still pulls toward Expert.
    @Test func aFitResumesFromItsStartingPoint() {
        var start = PersonModel.anchored(at: anchor)
        start.weights[1] += 0.2
        start.theta[3] = -0.7
        var options = FitOptions()
        options.iterations = 0
        #expect(PersonFitter.fit(synthetic(count: 10, seed: 5), anchor: anchor, start: start, options: options) == start)
    }

    /// Review Focus 4: no data means the anchor, not NaN.
    @Test func fittingNothingReturnsTheAnchor() {
        #expect(PersonFitter.fit([], anchor: anchor) == PersonModel.anchored(at: anchor))
    }
}
