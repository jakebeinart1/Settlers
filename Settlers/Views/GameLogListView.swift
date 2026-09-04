import SwiftUI
import CatanEngine

/// Human-readable archive index. Corrupt files are reported instead of being
/// silently omitted, because an invisible bad log cannot be diagnosed or shared.
struct GameLogListView: View {
    let onDismiss: () -> Void
    var store = GameLogStore.shared

    @State private var summaries: [GameLogSummary] = []
    @State private var failures: [GameLogScan.Failure] = []
    @State private var selected: GameLogSummary?
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
        .sheet(item: $selected) { summary in
            GameLogDetailView(summary: summary, store: store)
        }
    }

    private var header: some View {
        HStack {
            Text("Recorded Games").font(.title2.bold())
            Spacer()
            Button("Done", action: onDismiss).fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView("Couldn’t Read Game Logs", systemImage: "exclamationmark.triangle",
                                   description: Text(loadError))
        } else if summaries.isEmpty {
            ContentUnavailableView("No Recorded Games", systemImage: "doc.text.magnifyingglass")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(failures) { failure in
                        Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
                    }
                    ForEach(summaries) { summary in
                        Button { selected = summary } label: { row(summary) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ summary: GameLogSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: summary.isComplete ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                .foregroundStyle(summary.isComplete ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                Text(summaryLine(summary)).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
    }

    private func summaryLine(_ summary: GameLogSummary) -> String {
        let result = summary.winner.map {
            "Winner: \(summary.playerNames[$0.index] ?? "Player \($0.index + 1)")"
        } ?? "In progress"
        return "\(result) · \(summary.playerCount) seats · \(summary.victoryPointTarget) VP · \(summary.moveCount) moves"
    }

    private func load() {
        do {
            let scan = try store.scan()
            summaries = scan.summaries
            failures = scan.failures
        } catch {
            loadError = error.localizedDescription
        }
    }
}
