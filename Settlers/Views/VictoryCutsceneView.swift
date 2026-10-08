import SwiftUI
import CatanEngine

/// Plays between the move that ends a game and `EndGameView`: the camera
/// tours the winner's pieces while their score counts up, the bonuses land,
/// then a banner. A human win ends in gold and confetti; a loss tours the
/// same winning board, dimmer and greyer, and ends in rain. Tap anywhere
/// (or Skip) to go straight to the results.
struct VictoryCutsceneView: View {
    let state: GameState
    let tally: VictoryTally
    let isHumanWin: Bool
    let playerIdentity: (PlayerID) -> PlayerIdentity
    let onFinish: () -> Void

    private static let pieceBeat = 0.55
    private static let bonusBeat = 1.0
    private static let bannerHold = 2.6

    @State private var revealed = 0
    @State private var spotlight = BoardSpotlight()
    @State private var caption: String?
    @State private var showsBanner = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var winnerIdentity: PlayerIdentity { playerIdentity(tally.winner) }
    private var score: Int { tally.beats.prefix(revealed).reduce(0) { $0 + $1.points } }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 10) {
                scoreHeader
                BoardView(state: state, playerIdentity: playerIdentity, decision: nil,
                          onSelectTarget: { _ in }, allowsGameCommands: false, animatesStateChanges: false)
                    .staticWorldOverview()
                    .spotlighting(spotlight)
                    // A tint, not `.saturation`: a colour filter re-renders the
                    // whole board offscreen on every camera step of the tour.
                    .overlay(Color(red: 0.05, green: 0.07, blue: 0.12)
                        .opacity(isHumanWin ? 0 : 0.4).allowsHitTesting(false))
                captionRow
            }
            .padding(.vertical, 24)
            if showsBanner { ending }
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .overlay(alignment: .bottomTrailing) { skipButton }
        .task { await play() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.GameOver.cutscene)
    }

    // MARK: - Sequence

    private func play() async {
        for beat in tally.beats {
            withAnimation(.easeInOut(duration: 0.45)) { show(beat) }
            guard await pause(isOnBoard(beat) ? Self.pieceBeat : Self.bonusBeat) else { return }
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            spotlight.focus = nil
            spotlight.label = nil
            caption = nil
        }
        guard await pause(0.6) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { showsBanner = true }
        guard await pause(Self.bannerHold) else { return }
        onFinish()
    }

    private func show(_ beat: VictoryTally.Beat) {
        revealed += 1
        let plus = "+\(beat.points)"
        switch beat.source {
        case .settlement(let vertex), .city(let vertex):
            spotlight.vertices.insert(vertex)
            spotlight.focus = vertex
            spotlight.label = plus
            caption = nil
        case .longestRoad(let roads):
            spotlight.edges = roads
            spotlight.focus = nil
            spotlight.label = nil
            caption = "Longest Road  \(plus)"
        case .largestArmy:
            caption = "Largest Army  \(plus)"
        case .victoryCards(let count):
            caption = (count == 1 ? "Victory Point card  " : "\(count) Victory Point cards  ") + plus
        case .colonies:
            caption = "Colonies  \(plus)"
        }
    }

    private func isOnBoard(_ beat: VictoryTally.Beat) -> Bool {
        switch beat.source {
        case .settlement, .city: return true
        default: return false
        }
    }

    /// False once the view is gone (skipped), which ends the sequence.
    private func pause(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil
    }

    // MARK: - Pieces

    private var backdrop: some View {
        GeometryReader { geo in
            Image("win-background")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .saturation(isHumanWin ? 1 : 0.3)
        }
        .ignoresSafeArea()
        .overlay(Color.black.opacity(isHumanWin ? 0.35 : 0.6).ignoresSafeArea())
    }

    private var scoreHeader: some View {
        HStack(spacing: 12) {
            CivilizationCrest(civilization: winnerIdentity.civilization, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(winnerIdentity.displayName).font(.headline)
                Text("Victory points").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text("\(score)")
                .font(.system(size: 52, weight: .black, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(score)))
                .foregroundStyle(isHumanWin ? CatanTheme.cityPennantGold : Color(white: 0.85))
                .accessibilityIdentifier(AccessibilityID.GameOver.cutsceneScore)
        }
        .padding(.horizontal, 20)
    }

    /// Fixed height whether or not a caption is up, so the board above it
    /// never resizes mid-tour.
    private var captionRow: some View {
        ZStack {
            if let caption {
                Text(caption)
                    .font(.title3.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(PaintedChromeBackground(fill: .color(Color(white: 0.08)), cornerRadius: 10))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .id(caption)
            }
        }
        .frame(height: 48)
    }

    @ViewBuilder
    private var ending: some View {
        if !reduceMotion {
            CelebrationParticles(mood: isHumanWin
                ? .confetti([winnerIdentity.civilization.accentColor, CatanTheme.cityPennantGold, DevCardChrome.ivory])
                : .rain)
                .ignoresSafeArea()
        }
        VStack(spacing: 6) {
            Text(isHumanWin ? "VICTORY!" : "YOU LOSE!")
                .font(.system(size: 46, weight: .black, design: .serif))
                .tracking(3)
                .foregroundStyle(isHumanWin ? CatanTheme.cityPennantGold : Color(white: 0.82))
            Text(isHumanWin ? "\(tally.total) points. The island is yours."
                            : "\(winnerIdentity.displayName) took the island. Get better at the game!")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .background(PaintedChromeBackground(
            fill: .color(isHumanWin ? Color(white: 0.08) : Color(red: 0.08, green: 0.1, blue: 0.14)), cornerRadius: 14))
        .padding(.horizontal, 28)
        .rotationEffect(.degrees(isHumanWin ? 0 : -3))
        .transition(.scale(scale: isHumanWin ? 1.6 : 0.7).combined(with: .opacity))
    }

    private var skipButton: some View {
        Button("Skip", action: onFinish)
            .font(.subheadline.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.45)))
            .padding(.trailing, 16)
            .padding(.bottom, 4)
            .accessibilityIdentifier(AccessibilityID.GameOver.skipCutscene)
    }
}
