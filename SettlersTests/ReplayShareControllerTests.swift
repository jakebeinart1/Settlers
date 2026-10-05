import Foundation
import Testing
import UIKit
@testable import Settlers

/// This dummy URL exercises controller configuration and callback forwarding,
/// not file delivery. Actual MP4 sharing still needs separate native evidence.
@MainActor
@Suite struct ReplayShareControllerTests {
    enum Outcome: CaseIterable, Sendable { case success, cancellation, error }

    private let dummyURL = URL(fileURLWithPath: "/tmp/replay-share-controller-test.mp4")

    @Test func excludesOnlyCameraRollAndInstallsCompletion() {
        let controller = makeReplayShareController(url: dummyURL) { _ in }

        #expect(controller.excludedActivityTypes == [.saveToCameraRoll])
        #expect(controller.completionWithItemsHandler != nil)
    }

    @Test(arguments: Outcome.allCases)
    func installedUIKitCompletionForwardsItsError(outcome: Outcome) async throws {
        let receipt = ShareCompletionReceipt()
        let controller = makeReplayShareController(url: dummyURL) { message in
            receipt.messages.append(message)
        }
        let handler = try #require(controller.completionWithItemsHandler)
        let error: Error? = outcome == .error
            ? NSError(domain: "ReplayShareControllerTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Replay share test error."])
            : nil

        handler(nil, outcome == .success, nil, error)
        try await waitForCompletion(receipt)
        switch outcome {
        case .success, .cancellation: #expect(receipt.messages == [nil])
        case .error: #expect(receipt.messages == ["Replay share test error."])
        }
    }

    private func waitForCompletion(_ receipt: ShareCompletionReceipt) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while receipt.messages.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!receipt.messages.isEmpty, "The installed UIKit completion did not forward its result")
    }
}

@MainActor
private final class ShareCompletionReceipt {
    var messages: [String?] = []
}
