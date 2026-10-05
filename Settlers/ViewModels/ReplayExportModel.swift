import Foundation
import Observation

/// Export task lifetime follows the sheet, not the replay's playback task.
/// Cancellation awaits writer cleanup before allowing a retry, so a second
/// export cannot race an unfinished first writer or delete its active file.
@MainActor @Observable
final class ReplayExportModel {
    private(set) var progress: ReplayExportProgress?
    private(set) var result: ReplayVideoResult?
    private(set) var errorMessage: String?
    private(set) var isCancelling = false
    private var task: Task<Void, Never>?
    private let summary: GameLogSummary
    private let store: GameLogStore
    private let directory: URL
    var isBusy: Bool { task != nil }

    init(summary: GameLogSummary, store: GameLogStore,
         directory: URL = FileManager.default.temporaryDirectory) {
        self.summary = summary
        self.store = store
        self.directory = directory
    }

    func start(includeNames: Bool) {
        guard task == nil else { return }
        errorMessage = nil
        progress = .preparing
        task = Task {
            do {
                let detail = try await readArchive()
                let video = try await ReplayVideoExporter.export(detail: detail, includeNames: includeNames,
                                                                directory: directory) { [weak self] update in
                    self?.progress = update
                }
                if Task.isCancelled {
                    try ReplayVideoExporter.discard(video)
                    throw CancellationError()
                }
                result = video
            } catch is CancellationError {
                errorMessage = "Video creation cancelled. You can try again."
            } catch {
                errorMessage = error.localizedDescription
            }
            progress = nil
            isCancelling = false
            task = nil
        }
    }

    func cancel() {
        guard task != nil else { return }
        isCancelling = true
        task?.cancel()
    }

    func reset() {
        guard !isBusy else { return }
        do {
            if let result { try ReplayVideoExporter.discard(result) }
            result = nil
            errorMessage = nil
        } catch {
            errorMessage = "The temporary video could not be removed. \(error.localizedDescription)"
        }
    }

    func close() {
        cancel()
        reset()
    }

    func sharingFailed(_ message: String) { errorMessage = message }

    private func readArchive() async throws -> GameLogDetail {
        let summary = summary
        let store = store
        let reader = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let detail = try store.detail(for: summary)
            try Task.checkCancellation()
            return detail
        }
        return try await withTaskCancellationHandler {
            try await reader.value
        } onCancel: {
            reader.cancel()
        }
    }
}
