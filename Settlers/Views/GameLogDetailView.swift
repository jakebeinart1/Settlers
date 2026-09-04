import SwiftUI
import CatanEngine

/// One archived game's roster and ordered decisions, plus its original JSONL
/// for export when a tester needs to send an exact reproduction.
struct GameLogDetailView: View {
    let summary: GameLogSummary
    var store = GameLogStore.shared

    @Environment(\.dismiss) private var dismiss
    @State private var detail: GameLogDetail?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            VStack(spacing: 16) {
                header
                content
            }
            .padding(20)
        }
        .foregroundStyle(.white)
        .task { load() }
    }

    private var header: some View {
        HStack {
            Button("Close") { dismiss() }
            Spacer()
            ShareLink(item: summary.fileURL) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        .fontWeight(.semibold)
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView("Couldn’t Read This Game", systemImage: "exclamationmark.triangle",
                                   description: Text(loadError))
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    overview(detail)
                    roster(detail)
                    moves(detail)
                }
            }
        } else {
            ProgressView()
        }
    }

    private func overview(_ detail: GameLogDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.summary.startedAt.formatted(date: .long, time: .shortened)).font(.title3.bold())
            Text(detail.summary.isComplete ? "Completed game" : "Incomplete recording")
            Text("\(detail.summary.playerCount) seats · First to \(detail.summary.victoryPointTarget) VP")
            Text("\(duration(detail.summary.duration)) · \(detail.summary.moveCount) recorded moves")
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private func roster(_ detail: GameLogDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Players").font(.headline)
            ForEach(0..<detail.summary.playerCount, id: \.self) { seat in
                let player = PlayerID(index: seat)
                HStack(spacing: 9) {
                    if let civilization = detail.roster.civilization(for: player) {
                        CivilizationCrest(civilization: civilization, size: 28)
                    }
                    Text("Seat \(seat + 1) · \(detail.roster.displayName(for: player)) · "
                         + (detail.roster.civilizations[seat] ?? "Unknown civilization"))
                        .font(.subheadline)
                }
            }
        }
    }

    private func moves(_ detail: GameLogDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Moves").font(.headline)
            ForEach(Array(detail.events.enumerated()), id: \.offset) { index, event in
                Text("\(index + 1). \(detail.roster.displayName(for: event.player)): "
                     + String(describing: event.move))
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.14)))
            }
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60)m \(total % 60)s"
    }

    private func load() {
        do {
            detail = try store.detail(for: summary)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
