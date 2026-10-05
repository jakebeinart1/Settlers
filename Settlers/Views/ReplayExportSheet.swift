import AVKit
import SwiftUI
import UIKit

/// Native preview and sharing stay outside the rendered movie. The diagnostic
/// option shares the original reusable archive only after a privacy warning.
struct ReplayExportSheet: View {
    let summary: GameLogSummary
    @State private var model: ReplayExportModel
    @State private var includeNames = false
    @State private var player: AVPlayer?
    @State private var sharing: SharedFile?
    @State private var warningPresented = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(summary: GameLogSummary, store: GameLogStore) {
        self.summary = summary
        _model = State(initialValue: ReplayExportModel(summary: summary, store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    explanation
                    if let result = model.result { preview(result) } else { creation }
                    if let message = model.errorMessage {
                        Text(message).foregroundStyle(SettingsChrome.ornamentGold)
                            .accessibilityIdentifier(AccessibilityID.ReplayExport.error)
                    }
                    diagnostic
                }
                .padding(20)
            }
            .background(Color(white: 0.1))
            .foregroundStyle(.white)
            .navigationTitle("Share replay video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.close(); dismiss() }.disabled(sharing != nil)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier(AccessibilityID.ReplayExport.sheet)
        .interactiveDismissDisabled(model.isBusy || sharing != nil)
        .onDisappear {
            player?.pause()
            // A share extension must finish reading the file before cleanup.
            if sharing == nil { model.close() } else { model.cancel() }
        }
        .onChange(of: model.result?.url) { _, url in player = url.map { AVPlayer(url: $0) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, model.isBusy { model.cancel() }
        }
        .task { await cleanAbandonedExports() }
        .sheet(item: $sharing) { item in
            ReplayExportActivityView(url: item.url) { error in
                if let error { model.sharingFailed(error) }
                sharing = nil
            }
        }
        .alert("Share diagnostic recording?", isPresented: $warningPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Share recording") { sharing = SharedFile(url: summary.fileURL) }
        } message: {
            Text("This raw JSONL file includes recorded player and Ghost names, timestamps, "
                 + "and data that can reveal every hidden hand and deck order. "
                 + "Share it only with someone you trust. It is for diagnostics, not a video.")
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your game, as a video").font(.title3.bold()).fontDesign(.serif)
            Text("Created on this device. Hidden hands excluded. The video shows the public board, public scores, and move captions.")
            Text(ReplayExportAnalysis.reconstructionNotice)
                .font(.caption).foregroundStyle(.white.opacity(0.65))
            Text("An unfinished or unreconstructable recording is labelled Partial replay.")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var creation: some View {
        VStack(spacing: 14) {
            Toggle("Include recorded player names", isOn: $includeNames)
                .disabled(model.isBusy).accessibilityIdentifier(AccessibilityID.ReplayExport.names)
            if includeNames {
                Text("Recorded player and Ghost names will appear in the video.").font(.caption)
            }
            if let progress = model.progress {
                VStack(spacing: 8) {
                    if let fraction = progress.fraction { ProgressView(value: fraction) } else { ProgressView() }
                    Text(model.isCancelling ? "Cancelling…" : progress.label).font(.caption)
                        .accessibilityIdentifier(AccessibilityID.ReplayExport.progress)
                    Button("Cancel") { model.cancel() }.disabled(model.isCancelling)
                        .accessibilityIdentifier(AccessibilityID.ReplayExport.cancel)
                }
            } else {
                GoldRowButton(title: model.errorMessage == nil ? "Create replay video" : "Retry video export",
                              systemImage: "video.fill", iconColor: SettingsChrome.ornamentGold) {
                    model.start(includeNames: includeNames)
                }
                .accessibilityIdentifier(AccessibilityID.ReplayExport.create)
            }
        }
    }

    private func preview(_ result: ReplayVideoResult) -> some View {
        VStack(spacing: 12) {
            if result.isPartial {
                Text("Partial replay").font(.headline).foregroundStyle(SettingsChrome.ornamentGold)
            }
            Text(result.notice).font(.caption).multilineTextAlignment(.center)
            VideoPlayer(player: player).frame(height: 280)
                .accessibilityIdentifier(AccessibilityID.ReplayExport.preview)
            Text("MP4 · \(Int(result.duration.rounded())) seconds · No audio").font(.caption)
            GoldRowButton(title: "Share replay video", systemImage: "square.and.arrow.up",
                          iconColor: SettingsChrome.ornamentGold) {
                player?.pause()
                sharing = SharedFile(url: result.url)
            }
            .accessibilityIdentifier(AccessibilityID.ReplayExport.share)
            Button("Create another video") { player?.pause(); player = nil; model.reset() }
        }
    }

    private var diagnostic: some View {
        VStack(spacing: 6) {
            Divider()
            Button("Share diagnostic recording (.jsonl)") { warningPresented = true }
                .disabled(model.isBusy).accessibilityIdentifier(AccessibilityID.ReplayExport.diagnostic)
            Text("Raw game data for support and analysis.").font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func cleanAbandonedExports() async {
        let cleanup = Task.detached(priority: .utility) { try ReplayVideoExporter.discardExpired() }
        do { try await cleanup.value } catch {
            model.sharingFailed("Old temporary exports could not be removed. \(error.localizedDescription)")
        }
    }

    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }
}

private struct ReplayExportActivityView: UIViewControllerRepresentable {
    let url: URL
    let completion: @MainActor @Sendable (String?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        makeReplayShareController(url: url, completion: completion)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

@MainActor
func makeReplayShareController(url: URL,
                               completion: @escaping @MainActor @Sendable (String?) -> Void) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    // No Photos-saving feature or add-only purpose key ships in this release;
    // exclude that destination as containment, not a claim of an observed crash.
    controller.excludedActivityTypes = [.saveToCameraRoll]
    controller.completionWithItemsHandler = { _, _, _, error in
        let message = error?.localizedDescription
        Task { @MainActor in completion(message) }
    }
    return controller
}
