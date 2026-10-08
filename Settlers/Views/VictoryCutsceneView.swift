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
    private static let cardBeat = 1.1
    private static let cardSize: CGFloat = 48
    private static let bannerHold = 2.6

    @State private var revealed = 0
    @State private var spotlight = BoardSpotlight()
    @State private var caption: String?
    /// Dev cards that scored, in the order they flipped in.
    @State private var cards: [DevCardType] = []
    @State private var showsBanner = false
    /// Closed stage curtains open the scene (Jake, 2026-10-08).
    @State private var showsCurtain = true
    @State private var curtainOpenness: CGFloat = 0
    private static let curtainHold = 0.9
    private static let curtainOpening = 1.3
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
                cardShelf
                captionRow
            }
            .padding(.vertical, 24)
            if showsBanner { ending }
            if showsCurtain {
                TheatreCurtain(openness: curtainOpenness, title: "The Final Tally")
            }
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
        guard await raiseCurtain() else { return }
        for beat in tally.beats {
            withAnimation(.easeInOut(duration: 0.45)) { show(beat) }
            guard await pause(duration(of: beat)) else { return }
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

    /// The game screen has already faded into the closed curtain
    /// (`ContentView`); hold it a beat, then part it onto the board. Reduce
    /// Motion skips straight to the board.
    private func raiseCurtain() async -> Bool {
        guard !reduceMotion else {
            showsCurtain = false
            return true
        }
        guard await pause(Self.curtainHold) else { return false }
        withAnimation(.easeInOut(duration: Self.curtainOpening)) { curtainOpenness = 1 }
        guard await pause(Self.curtainOpening) else { return false }
        showsCurtain = false
        return true
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
            reveal(.knight, caption: "Largest Army  \(plus)")
        case .victoryCard:
            reveal(.victoryPoint, caption: "Victory Point card  \(plus)")
        case .colonies:
            caption = "Colonies  \(plus)"
        }
    }

    /// Cards score off the board, so the lens pulls back to the whole island
    /// while they flip in under it.
    private func reveal(_ card: DevCardType, caption text: String) {
        spotlight.focus = nil
        spotlight.label = nil
        cards.append(card)
        caption = text
    }

    private func duration(of beat: VictoryTally.Beat) -> Double {
        switch beat.source {
        case .settlement, .city: return Self.pieceBeat
        case .victoryCard: return Self.cardBeat
        default: return Self.bonusBeat
        }
    }

    /// False once the view is gone (skipped), which ends the sequence.
    private func pause(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil
    }

    // MARK: - Pieces

    private var backdrop: some View {
        GeometryReader { geo in
            ThemedBackgroundImage(isVictory: true)
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

    /// Scoring cards, lit like the board's pieces: the same wide translucent
    /// ring under a narrow gold one, and a "+N" on the card that just landed.
    /// Fixed height from the first frame, so the board never resizes.
    private var cardShelf: some View {
        HStack(spacing: 14) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                cardTile(card, plus: index == cards.count - 1 ? (card == .knight ? 2 : 1) : nil)
                    .transition(.modifier(active: CardFlip(angle: -90), identity: CardFlip(angle: 0)))
            }
        }
        .frame(height: Self.cardSize + 36)
    }

    private func cardTile(_ card: DevCardType, plus: Int?) -> some View {
        let gold = CatanTheme.cityPennantGold
        let shape = RoundedRectangle(cornerRadius: DevCardChrome.borderRadius)
        return DevCardEmblem(type: card)
            .frame(width: Self.cardSize, height: Self.cardSize)
            .padding(6)
            .background(DevCardChrome.background(card))
            .overlay(shape.stroke(gold.opacity(0.35), lineWidth: 9).padding(-4))
            .overlay(shape.stroke(gold, lineWidth: 2.5).padding(-2))
            .overlay(alignment: .top) {
                if let plus {
                    Text("+\(plus)")
                        .font(.system(size: 15, weight: .black, design: .serif))
                        .foregroundStyle(gold)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(.black.opacity(0.75)))
                        .overlay(Capsule().stroke(gold, lineWidth: 1))
                        .offset(y: -14)
                        .transition(.opacity)
                }
            }
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

/// A card turning face-up about its vertical axis; edge-on is invisible.
private struct CardFlip: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .opacity(1 - abs(angle) / 90)
    }
}
