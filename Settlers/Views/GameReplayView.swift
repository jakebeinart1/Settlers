import SwiftUI
import CatanEngine

/// A finished game played back on the real board: scrub from the opening
/// position to the last move and watch the map and the score fill in.
///
/// This replaced a screen that printed `String(describing:)` of every archived
/// `GameMove` into a scrolling list. That list was honest and unreadable - the
/// question a player actually asks about a game they just lost is "where did
/// the board get away from me", and a board answers it in one glance where 400
/// lines of `buildSettlement(VertexID(...))` never do.
///
/// ## Layout
/// The same rule the game screen is built around applies here, for the same
/// reason (`GameView.belowBoard`): everything under the board occupies one
/// FIXED-height frame, so the board's container is a constant and its fit is a
/// pure function of the screen. Nothing below is conditional - the caption
/// reserves both its lines whether or not it needs them, and the transport row
/// never changes shape - so scrubbing cannot resize or re-centre the board
/// under the player's finger.
struct GameReplayView: View {
    let summary: GameLogSummary
    var store = GameLogStore.shared

    @Environment(\.dismiss) private var dismiss
    @State private var timeline: GameReplayTimeline?
    @State private var loadError: String?
    @State private var index = 0
    @State private var isPlaying = false

    /// Height of everything below the board. A constant, not a remainder: see
    /// the type's doc comment.
    private static let belowBoardReserve: CGFloat = 226
    private static let headerHeight: CGFloat = 44
    /// One frame every this many seconds while playing. Slow enough to read
    /// the caption, fast enough that a 400-move game is not a sitting.
    private static let playbackInterval: Duration = .milliseconds(650)

    var body: some View {
        ZStack {
            paintedBackground
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.replay)
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .task { await load() }
        .task(id: isPlaying) { await advanceWhilePlaying() }
    }

    private var paintedBackground: some View {
        ZStack {
            GeometryReader { geo in
                Image("board-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.62), Color.black.opacity(0.35), Color.black.opacity(0.72)],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            failure(loadError)
        } else if let timeline, let frame = timeline.frames[safe: index] {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    header
                        .frame(height: Self.headerHeight)
                    BoardView(
                        state: frame.state,
                        playerIdentity: timeline.identity(for:),
                        decision: nil,
                        onSelectTarget: { _ in },
                        allowsGameCommands: false
                    )
                    .frame(height: max(0, geometry.size.height
                                       - Self.headerHeight - Self.belowBoardReserve))
                    controls(timeline: timeline, frame: frame)
                        .frame(height: Self.belowBoardReserve, alignment: .top)
                }
            }
        } else {
            ProgressView().tint(.white)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            header
            Spacer()
            ContentUnavailableView("Couldn't replay this game",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(message))
            Spacer()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityIdentifier(AccessibilityID.Replay.close)
            .accessibilityLabel("Close replay")
            Spacer()
            Text(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            ShareLink(item: summary.fileURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityLabel("Share this recording")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Below the board

    private func controls(timeline: GameReplayTimeline, frame: GameReplayTimeline.Frame) -> some View {
        VStack(spacing: 10) {
            scoreStrip(timeline: timeline, frame: frame)
            caption(timeline: timeline, frame: frame)
            scrubber(timeline: timeline)
            transport(timeline: timeline)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// Live score, in seat order, so the whole point of the screen - watching
    /// the game tilt - is readable without leaving the board.
    private func scoreStrip(timeline: GameReplayTimeline, frame: GameReplayTimeline.Frame) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<timeline.seatCount, id: \.self) { seat in
                let identity = timeline.identity(for: PlayerID(index: seat))
                let isWinner = summary.winner?.index == seat
                VStack(spacing: 3) {
                    CivilizationCrest(civilization: identity.civilization, size: 24)
                    Text(identity.displayName)
                        .font(.system(size: 11, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white.opacity(0.75))
                    Text("\(frame.scores[safe: seat] ?? 0) VP")
                        .font(.system(size: 14, weight: isWinner ? .bold : .semibold, design: .serif))
                        .foregroundStyle(isWinner ? SettingsChrome.ornamentGold : .white)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.Replay.score(PlayerID(index: seat)))
            }
        }
        .padding(.vertical, 8)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill),
                                            cornerRadius: 10, notchScale: 0.6))
    }

    /// Two lines, always. A caption that grows and shrinks with its sentence
    /// moves every control under it on every single frame of a scrub.
    private func caption(timeline: GameReplayTimeline, frame: GameReplayTimeline.Frame) -> some View {
        // The truncation notice replaces the caption only on the frame the
        // recording actually stops at, where "why does it end here" is the
        // question being asked. Everywhere else it would just be noise over
        // moves that replayed perfectly.
        Text(index == timeline.lastIndex ? (timeline.truncation ?? frame.headline) : frame.headline)
            .font(.system(size: 14, design: .serif))
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(AccessibilityID.Replay.caption)
    }

    private func scrubber(timeline: GameReplayTimeline) -> some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { newValue in
                        isPlaying = false
                        index = Int(newValue.rounded())
                    }),
                in: 0...Double(max(1, timeline.lastIndex)),
                step: 1
            )
            .tint(SettingsChrome.ornamentGold)
            .disabled(timeline.lastIndex == 0)
            .accessibilityIdentifier(AccessibilityID.Replay.scrubber)
            .accessibilityLabel("Move position")
            Text("Move \(index) of \(timeline.lastIndex)")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func transport(timeline: GameReplayTimeline) -> some View {
        HStack(spacing: 10) {
            transportButton("backward.end.fill", label: "Jump to start",
                            identifier: AccessibilityID.Replay.start,
                            isEnabled: index > 0) { index = 0 }
            transportButton("backward.fill", label: "Previous move",
                            identifier: AccessibilityID.Replay.previous,
                            isEnabled: index > 0) { index -= 1 }
            transportButton(isPlaying ? "pause.fill" : "play.fill",
                            label: isPlaying ? "Pause" : "Play",
                            identifier: AccessibilityID.Replay.playPause,
                            isEnabled: timeline.lastIndex > 0, isPrimary: true) {
                if index == timeline.lastIndex { index = 0 }
                isPlaying.toggle()
            }
            transportButton("forward.fill", label: "Next move",
                            identifier: AccessibilityID.Replay.next,
                            isEnabled: index < timeline.lastIndex) { index += 1 }
            transportButton("forward.end.fill", label: "Jump to end",
                            identifier: AccessibilityID.Replay.end,
                            isEnabled: index < timeline.lastIndex) { index = timeline.lastIndex }
        }
        .frame(height: 46)
    }

    private func transportButton(_ symbol: String, label: String, identifier: String,
                                 isEnabled: Bool, isPrimary: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        Button {
            if !isPrimary { isPlaying = false }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: isPrimary ? 20 : 16, weight: .semibold))
                .foregroundStyle(isEnabled ? (isPrimary ? SettingsChrome.ornamentGold : .white)
                                 : .white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PaintedChromeBackground(
                    fill: .color(isPrimary ? SettingsChrome.plaqueFill : Color(white: 0.16)),
                    cornerRadius: 10, notchScale: 0.6))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    // MARK: - Loading and playback

    /// Replaying hundreds of moves is real work, so it happens off the main
    /// actor and the screen shows a spinner until it lands.
    private func load() async {
        guard timeline == nil, loadError == nil else { return }
        let summary = summary
        let store = store
        let built = await Task.detached(priority: .userInitiated) { () -> Result<GameReplayTimeline, Error> in
            do { return .success(GameReplayTimeline(detail: try store.detail(for: summary))) } catch {
                return .failure(error)
            }
        }.value
        switch built {
        case .success(let value):
            timeline = value
            index = 0
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    private func advanceWhilePlaying() async {
        guard isPlaying else { return }
        while !Task.isCancelled, isPlaying, let timeline, index < timeline.lastIndex {
            try? await Task.sleep(for: Self.playbackInterval)
            guard !Task.isCancelled, isPlaying else { return }
            index += 1
        }
        isPlaying = false
    }
}

/// Bounds-checked subscript. The scrubber's index and the frame array are two
/// pieces of state that a reload could briefly disagree about, and a crash is
/// not the right answer to a one-frame disagreement on a history screen.
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
