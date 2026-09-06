import Foundation

/// Offline CTNN v1 inference adapted from Eli Olcott's MIT-licensed `net.rs`.
/// See Resources/UpstreamPolicy for the original notice and pinned provenance.
///
/// Keeps float32 arithmetic and Rust's accumulation order: input-major ReLU
/// layers and 16 independent head sums. Weights are immutable; each prediction
/// owns its scratch buffers, so a loaded network can be shared between tasks.
/// Observation encoding, legal-action masking and action selection belong to
/// the caller. This type only understands the frozen 1350 -> 512 -> 512 graph.
public struct UpstreamNetwork: Sendable {
    public enum LoadingError: Error, Equatable, Sendable {
        case missingResource
        case invalidByteCount(Int)
        case invalidMagic
        case unsupportedVersion(UInt32)
        case invalidDimensions
        case nonfiniteFloat(byteOffset: Int)
        case selfCheckFailed
    }

    private static let inputCount = 1350
    private static let actionCount = 299
    private static let hiddenCount = 512
    private static let byteCount = 4_438_528
    private static let headerBytes = 20
    private static let selfCheckTolerance: Float = 0.001

    private let firstLayer: ReluLayer
    private let secondLayer: ReluLayer
    private let policyWeights: [Float]
    private let policyBias: [Float]
    private let valueWeights: [Float]
    private let valueBias: Float

    /// Decodes fixed-size little-endian IEEE-754 tensors and validates every
    /// float before allocating layer buffers. Rejects trailing bytes as well as
    /// truncation. The embedded PyTorch probe is a numeric check, not a digest.
    /// Throws a LoadingError for unsupported, malformed or incompatible data.
    public init(data: Data) throws {
        try Self.validateHeader(data)
        var reader = try FloatReader(data: data, start: Self.headerBytes)
        let hidden = Self.hiddenCount
        firstLayer = ReluLayer(
            rows: reader.take(hidden * Self.inputCount), bias: reader.take(hidden), inputs: Self.inputCount
        )
        secondLayer = ReluLayer(rows: reader.take(hidden * hidden), bias: reader.take(hidden), inputs: hidden)
        policyWeights = reader.take(Self.actionCount * hidden)
        policyBias = reader.take(Self.actionCount)
        valueWeights = reader.take(hidden)
        valueBias = reader.take(1)[0]
        let probe = reader.take(Self.inputCount)
        let expectedValue = reader.take(1)[0]
        let expectedLogits = reader.take(8)
        try validateProbe(probe, value: expectedValue, logits: expectedLogits)
    }

    /// Loads the unchanged r2 export from the SwiftPM resource bundle, offline.
    /// Call once and share the returned immutable value; this does not cache or
    /// substitute a different checkpoint when loading fails.
    public static func bundled() throws -> UpstreamNetwork {
        guard let url = Bundle.module.url(forResource: "final", withExtension: "ctnn", subdirectory: "UpstreamPolicy") else {
            throw LoadingError.missingResource
        }
        return try UpstreamNetwork(data: Data(contentsOf: url))
    }

    /// Returns 299 raw policy logits and the Rust value head clamped to [-1, 1].
    /// Requires exactly 1350 finite float32 features. No softmax, tanh, masking,
    /// normalization or randomness is applied. Out-of-range finite inputs are
    /// permitted, but arithmetic overflow is a caller contract failure.
    public func predict(_ features: [Float]) -> (logits: [Float], value: Float) {
        precondition(features.count == Self.inputCount, "CTNN requires 1350 features")
        precondition(features.allSatisfy(\.isFinite), "CTNN features must be finite")
        let result = forward(features)
        precondition(result.value.isFinite && result.logits.allSatisfy(\.isFinite), "CTNN inference overflow")
        return (result.logits, min(1, max(-1, result.value)))
    }

    private func forward(_ features: [Float]) -> (logits: [Float], value: Float) {
        let hidden = secondLayer.apply(firstLayer.apply(features))
        var logits = policyBias
        policyWeights.withUnsafeBufferPointer { weights in
            hidden.withUnsafeBufferPointer { inputs in
                for action in 0..<Self.actionCount {
                    logits[action] += Self.dot(weights, offset: action * Self.hiddenCount, inputs)
                }
            }
        }
        let value = valueWeights.withUnsafeBufferPointer { weights in
            hidden.withUnsafeBufferPointer { Self.dot(weights, offset: 0, $0) }
        }
        return (logits, value + valueBias)
    }

    private func validateProbe(_ features: [Float], value: Float, logits: [Float]) throws {
        let result = forward(features)
        guard result.value.isFinite, result.logits.allSatisfy(\.isFinite),
              abs(result.value - value) < Self.selfCheckTolerance,
              zip(result.logits, logits).allSatisfy({ abs($0 - $1) < Self.selfCheckTolerance }) else {
            throw LoadingError.selfCheckFailed
        }
    }

    private static func validateHeader(_ data: Data) throws {
        guard data.count == byteCount else { throw LoadingError.invalidByteCount(data.count) }
        try data.withUnsafeBytes { bytes in
            guard Array(bytes.prefix(4)) == Array("CTNN".utf8) else { throw LoadingError.invalidMagic }
            let version = bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian
            guard version == 1 else { throw LoadingError.unsupportedVersion(version) }
            for (offset, expected) in [(8, inputCount), (12, actionCount), (16, hiddenCount)] {
                guard bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian == UInt32(expected) else {
                    throw LoadingError.invalidDimensions
                }
            }
        }
    }

    /// Match net.rs: accumulate products into lanes 0...15, then sum those
    /// lanes left to right. Bias is added after reduction, not before. Hidden
    /// width is pinned to 512, so every head has exactly 32 chunks and no tail.
    private static func dot(_ weights: UnsafeBufferPointer<Float>, offset: Int, _ inputs: UnsafeBufferPointer<Float>) -> Float {
        var lanes = SIMD16<Float>(repeating: 0)
        for chunk in stride(from: 0, to: hiddenCount, by: 16) {
            for lane in 0..<16 {
                lanes[lane] += weights[offset + chunk + lane] * inputs[chunk + lane]
            }
        }
        var sum: Float = 0
        for lane in 0..<16 { sum += lanes[lane] }
        return sum
    }
}

private extension UpstreamNetwork {
    struct FloatReader {
        let floats: [Float]
        var cursor = 0

        init(data: Data, start: Int) throws {
            floats = try data.withUnsafeBytes { bytes in
                var values: [Float] = []
                values.reserveCapacity((bytes.count - start) / 4)
                for offset in stride(from: start, to: bytes.count, by: 4) {
                    let word = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
                    let value = Float(bitPattern: word)
                    guard value.isFinite else { throw LoadingError.nonfiniteFloat(byteOffset: offset) }
                    values.append(value)
                }
                return values
            }
        }

        mutating func take(_ count: Int) -> [Float] {
            defer { cursor += count }
            return Array(floats[cursor..<(cursor + count)])
        }
    }

    struct ReluLayer: Sendable {
        let weights: [Float]
        let bias: [Float]

        init(rows: [Float], bias: [Float], inputs: Int) {
            self.bias = bias
            let outputs = bias.count
            var transposed = [Float](repeating: 0, count: rows.count)
            for row in 0..<outputs {
                for column in 0..<inputs { transposed[column * outputs + row] = rows[row * inputs + column] }
            }
            weights = transposed
        }

        /// Bias starts each sum. Input order, skipped +/-zero and separate
        /// multiply/add match the Rust sparse AXPY trunk, without fast math.
        func apply(_ inputs: [Float]) -> [Float] {
            var output = bias
            output.withUnsafeMutableBufferPointer { result in
                weights.withUnsafeBufferPointer { weights in
                    for (index, value) in inputs.enumerated() where value != 0 {
                        let offset = index * result.count
                        for neuron in result.indices { result[neuron] += value * weights[offset + neuron] }
                    }
                }
                for index in result.indices { result[index] = max(result[index], 0) }
            }
            return output
        }
    }
}
