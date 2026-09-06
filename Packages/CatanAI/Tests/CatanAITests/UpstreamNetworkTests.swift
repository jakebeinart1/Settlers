import Foundation
import Testing
@testable import CatanAI

private let upstreamModelBytes = 4_438_528
private let upstreamProbeOffset = 4_433_092

private struct NetworkFixture: Decodable {
    let sourceCommit: String
    let modelSHA256: String
    let cases: [Sample]

    struct Sample: Decodable, Sendable {
        let name: String
        let inputBits: [UInt32]
        let logitsBits: [UInt32]
        let valueBits: UInt32

        var features: [Float] { inputBits.map { Float(bitPattern: $0) } }
    }

    static func load() throws -> Self {
        let url = try #require(Bundle.module.url(
            forResource: "rust-parity", withExtension: "json", subdirectory: "Fixtures/UpstreamNetwork"
        ))
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

/// Writes explicit little-endian words, including unaligned Data slices in tests.
private func setWord(_ word: UInt32, at offset: Int, in data: inout Data) {
    for byte in 0..<4 { data[data.startIndex + offset + byte] = UInt8(truncatingIfNeeded: word >> (byte * 8)) }
}

private func syntheticNetwork(value: Float = 0) -> Data {
    var data = Data(repeating: 0, count: upstreamModelBytes)
    data.replaceSubrange(0..<4, with: Array("CTNN".utf8))
    for (index, word) in [UInt32(1), 1350, 299, 512].enumerated() {
        setWord(word, at: 4 + index * 4, in: &data)
    }
    setWord(value.bitPattern, at: 4_433_088, in: &data)
    setWord(value.bitPattern, at: 4_438_492, in: &data)
    return data
}

@Suite(.serialized)
struct UpstreamNetworkTests {
    @Test func allFrozenRustOutputsMatch() throws {
        let fixture = try NetworkFixture.load()
        #expect(fixture.sourceCommit == "021279c56834b6203480e5292e1de7246e47bd68")
        #expect(fixture.modelSHA256 == "a3c957a8765ccbb3c9afd1a8ebee45b7cbaff134c40ce0456e5024560b3ef94e")
        #expect(fixture.cases.count == 31)
        let network = try UpstreamNetwork.bundled()
        for sample in fixture.cases {
            let prediction = network.predict(sample.features)
            #expect(prediction.logits.map(\.bitPattern) == sample.logitsBits, "logits: \(sample.name)")
            #expect(prediction.value.bitPattern == sample.valueBits, "value: \(sample.name)")
        }
    }

    @Test func immutableNetworkCanBeSharedAcrossConcurrentPredictions() async throws {
        let network = try UpstreamNetwork.bundled()
        let samples = try NetworkFixture.load().cases
        await withTaskGroup(of: Bool.self) { group in
            for sample in samples {
                group.addTask {
                    let result = network.predict(sample.features)
                    return result.logits.map(\.bitPattern) == sample.logitsBits && result.value.bitPattern == sample.valueBits
                }
            }
            for await matches in group { #expect(matches) }
        }
    }

    @Test(arguments: [0, 3, 19, 20, upstreamProbeOffset - 1, upstreamModelBytes - 1, upstreamModelBytes + 1])
    func rejectsTruncatedAndTrailingData(count: Int) {
        #expect(throws: UpstreamNetwork.LoadingError.invalidByteCount(count)) {
            _ = try UpstreamNetwork(data: Data(repeating: 0, count: count))
        }
    }

    @Test func rejectsMagicVersionAndDimensionsBeforeAllocation() {
        var data = syntheticNetwork()
        data[0] = 0
        #expect(throws: UpstreamNetwork.LoadingError.invalidMagic) { _ = try UpstreamNetwork(data: data) }
        data[0] = 67
        for offset in [4, 8, 12, 16] {
            for value: UInt32 in [0, 2, .max, 0x01000000] {
                var invalid = data
                setWord(value, at: offset, in: &invalid)
                #expect(throws: UpstreamNetwork.LoadingError.self) { _ = try UpstreamNetwork(data: invalid) }
            }
        }
    }

    @Test(arguments: [UInt32(0x7FC00001), 0x7F800001, 0x7F800000, 0xFF800000])
    func rejectsNonfiniteWeightsBiasesAndProbe(word: UInt32) {
        // One word from each tensor/probe, including policy rows beyond the embedded check.
        for offset in [20, 2_764_820, 2_766_868, 3_815_444, 3_817_492, 4_429_844,
                       4_431_040, 4_433_088, upstreamProbeOffset, 4_438_492, 4_438_524] {
            var data = syntheticNetwork()
            setWord(word, at: offset, in: &data)
            #expect(throws: UpstreamNetwork.LoadingError.nonfiniteFloat(byteOffset: offset)) {
                _ = try UpstreamNetwork(data: data)
            }
        }
    }

    @Test func rejectsEmbeddedValueAndLogitMismatch() {
        for offset in [4_438_492, 4_438_496, 4_438_524] {
            var data = syntheticNetwork()
            setWord(Float(1).bitPattern, at: offset, in: &data)
            #expect(throws: UpstreamNetwork.LoadingError.selfCheckFailed) { _ = try UpstreamNetwork(data: data) }
        }
    }

    @Test func rejectsFiniteDataThatOverflowsDuringTheEmbeddedCheck() {
        var data = syntheticNetwork()
        setWord(Float.greatestFiniteMagnitude.bitPattern, at: 20, in: &data)
        setWord(Float.greatestFiniteMagnitude.bitPattern, at: upstreamProbeOffset, in: &data)
        #expect(throws: UpstreamNetwork.LoadingError.selfCheckFailed) { _ = try UpstreamNetwork(data: data) }
    }

    @Test func embeddedToleranceMatchesRustStrictInequality() throws {
        var data = syntheticNetwork()
        setWord(Float(0.000999).bitPattern, at: 4_438_492, in: &data)
        _ = try UpstreamNetwork(data: data)
        setWord(Float(0.001).bitPattern, at: 4_438_492, in: &data)
        #expect(throws: UpstreamNetwork.LoadingError.selfCheckFailed) { _ = try UpstreamNetwork(data: data) }
    }

    @Test func preservesRawValueCheckButClampsPrediction() throws {
        for value: Float in [-2, -1, 0, 1, 2] {
            let network = try UpstreamNetwork(data: syntheticNetwork(value: value))
            let result = network.predict([Float](repeating: 0, count: 1350))
            #expect(result.value == min(1, max(-1, value)))
            #expect(result.logits == [Float](repeating: 0, count: 299))
        }
    }

    @Test func supportsNonzeroDataStartIndexAndUnalignedStorage() throws {
        var padded = Data([0xFF])
        padded.append(syntheticNetwork(value: 0.5))
        let sliced = padded.dropFirst()
        #expect(sliced.startIndex == 1)
        let network = try UpstreamNetwork(data: sliced)
        #expect(network.predict([Float](repeating: 0, count: 1350)).value == 0.5)
    }

    @Test func rowMajorLayoutReluAndFinalLogitArePreserved() throws {
        var data = syntheticNetwork()
        // Path: input[1349] -> hidden1[511] -> hidden2[510] -> action[298].
        setWord(Float(2).bitPattern, at: 20 + (511 * 1350 + 1349) * 4, in: &data)
        setWord(Float(-1).bitPattern, at: 2_764_820 + 511 * 4, in: &data)
        setWord(Float(3).bitPattern, at: 2_766_868 + (510 * 512 + 511) * 4, in: &data)
        setWord(Float(-2).bitPattern, at: 3_815_444 + 510 * 4, in: &data)
        setWord(Float(4).bitPattern, at: 3_817_492 + (298 * 512 + 510) * 4, in: &data)
        setWord(Float(-5).bitPattern, at: 4_429_844 + 298 * 4, in: &data)
        let network = try UpstreamNetwork(data: data)
        var features = [Float](repeating: 0, count: 1350)
        #expect(network.predict(features).logits[298] == -5)
        features[1349] = 0.75 // first ReLU positive, second ReLU must zero -0.5.
        #expect(network.predict(features).logits[298] == -5)
        features[1349] = 2
        let result = network.predict(features)
        #expect(result.logits[298] == 23)
        #expect(result.logits.dropLast().allSatisfy { $0 == 0 })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["EMPIRES_NETWORK_BENCHMARK"] == "1"))
    func releaseLatency() throws {
        let fixture = try NetworkFixture.load()
        let network = try UpstreamNetwork.bundled()
        for name in ["embedded", "lcg-0", "lcg-1"] {
            let features = try #require(fixture.cases.first { $0.name == name }).features
            var checksum: Float = 0
            for _ in 0..<10 { checksum += network.predict(features).logits[298] }
            var times: [Double] = []
            for _ in 0..<100 {
                let start = ProcessInfo.processInfo.systemUptime
                let result = network.predict(features)
                times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                checksum += result.logits[298] + result.value
            }
            times.sort()
            #expect(checksum.isFinite)
            print("UpstreamNetwork \(name): 100 calls p50=\(times[50])ms p95=\(times[95])ms checksum=\(checksum)")
        }
    }
}
