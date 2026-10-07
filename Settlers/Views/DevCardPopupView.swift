import SwiftUI
import CatanEngine

/// The owner's complete development-card surface: purchase reveal, durable
/// hand, inspectable details, legal resource choices, and play actions.
///
/// This deliberately does not use `PopupCard`. A purchase reveal must never
/// disappear from an outside tap, and the longest detail state must remain
/// usable on a 375×667 phone and at large text sizes. The painted card is
/// clamped to the safe frame and only its middle content scrolls; its title
/// and acknowledgement actions stay visible.
struct DevelopmentCardOverlay: View {
    enum Mode: Equatable {
        case hand
        case reveal(DevCardReveal)
    }

    let mode: Mode
    let state: GameState
    let player: PlayerID
    @Binding var selectedType: DevCardType?
    let onBeginBoardCard: (DevCardType) -> Void
    let onCommit: (GameMove) -> String?
    let onViewCards: (DevCardType) -> Void
    let onDismiss: () -> Void
    /// Conquest: the Army tab's Deploy button.
    var onDeployArmy: () -> Void = {}
    var playerName: (PlayerID) -> String = { "Player \($0.index + 1)" }

    private enum HandTab: Hashable { case development, army }
    @State private var tab: HandTab = .development
    @State private var armyStrength: Int?

    @State private var yearOfPlentyPicks: [Resource] = []
    @State private var monopolyPick: Resource?
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var inventory: [DevCardInventoryItem] {
        DevCardInventoryItem.all(for: player, in: state)
    }

    private var displayedType: DevCardType? {
        switch mode {
        case .reveal(let reveal): reveal.card
        case .hand: selectedType ?? inventory.first?.type
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()

                // A `ScrollView` accepts every point it is offered, so the
                // panel used to be full-height whatever was in it: a Knight's
                // three short paragraphs left roughly 300pt of empty painted
                // panel between the description and the buttons, which reads
                // as a screen with something missing from it.
                //
                // `ViewThatFits` picks the hugging layout when the content
                // fits the screen and the scrolling one when it does not, so
                // the long states - Year of Plenty's resource chooser at large
                // text sizes, the one this sheet's height rules were written
                // for - still scroll with the title and actions pinned. The
                // alternative, measuring the content and capping the scroller,
                // sizes the SCROLLER but leaves the panel behind it full
                // height, which is the same empty panel with the buttons
                // floating in the middle of it.
                ViewThatFits(in: .vertical) {
                    panel(scrolling: false, maxHeight: nil, width: geometry.size.width)
                    panel(scrolling: true, maxHeight: geometry.size.height - 28, width: geometry.size.width)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.DevCards.overlay)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .onChange(of: selectedType) { _, _ in resetChoices() }
    }

    /// The sheet itself. `maxHeight` is `nil` for the hugging variant, which
    /// is what lets `ViewThatFits` measure its true height and reject it when
    /// it is too tall.
    private func panel(scrolling: Bool, maxHeight: CGFloat?, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

            Divider().overlay(SettingsChrome.ornamentGold.opacity(0.35))

            if scrolling {
                ScrollView { middle(width: width) }
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("dev-cards.middle-scroll")
                    .background { cardFrameMarker("dev-cards.content-frame") }
            } else {
                middle(width: width).background { cardFrameMarker("dev-cards.content-frame") }
            }

            Divider().overlay(SettingsChrome.ornamentGold.opacity(0.35))
            actionArea
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
        .frame(maxWidth: 366)
        .frame(maxHeight: maxHeight)
        .background(
            PaintedChromeBackground(
                fill: .tintedTexture(SettingsChrome.screenBackground),
                cornerRadius: 18,
                notchScale: 0.9
            )
        )
        .background { cardFrameMarker("dev-cards.panel-frame") }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .shadow(color: .black.opacity(0.65), radius: 28, y: 12)
    }

    private func middle(width: CGFloat) -> some View {
        VStack(spacing: 14) {
            if showsArmyTab {
                PaintedChoiceRow(
                    options: [HandTab.development, .army],
                    title: { $0 == .army ? "Army" : "Development" },
                    selection: tab,
                    isCompact: true,
                    fontSize: 14,
                    onSelect: { tab = $0 }
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if tab == .army && showsArmyTab {
                armyStrip
                armyDetail
            } else {
                if mode == .hand, !inventory.isEmpty { handStrip(width: min(366, width - 28) - 32) }
                if let type = displayedType {
                    cardDetail(type)
                } else {
                    emptyHand
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func cardFrameMarker(_ identifier: String) -> some View {
#if DEBUG
        Color.clear.accessibilityElement(children: .ignore)
            .accessibilityLabel("Development card content frame")
            .accessibilityIdentifier(identifier)
            .accessibilityRespondsToUserInteraction(false).allowsHitTesting(false)
#endif
    }

    // MARK: - Army tab (Conquest)

    private var showsArmyTab: Bool { mode == .hand && state.variant == .conquest }
    private var isArmyTab: Bool { showsArmyTab && tab == .army }

    /// The army hand grouped by strength, ascending.
    private var armyRows: [(strength: Int, count: Int)] {
        let counts = Dictionary(grouping: state.armyHands[player, default: []], by: { $0 }).mapValues(\.count)
        return counts.keys.sorted().map { ($0, counts[$0]!) }
    }

    private var displayedStrength: Int? { armyStrength ?? armyRows.first?.strength }

    private var armyStrip: some View {
        let hand = state.armyHands[player, default: []]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOUR ARMY")
                    .font(.caption.bold())
                    .foregroundStyle(SettingsChrome.ornamentGold)
                Spacer()
                Text("\(hand.count) cards · strength \(hand.reduce(0, +))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }
            if hand.isEmpty {
                SettingsInfoPlaque(text: "Raise your first army card from Build, paying \(state.armyPrice.label).")
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(armyRows, id: \.strength) { row in
                            ArmyHandTile(strength: row.strength, count: row.count,
                                         isSelected: displayedStrength == row.strength) {
                                armyStrength = row.strength
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var armyDetail: some View {
        VStack(spacing: 12) {
            ArmyArtwork(strength: displayedStrength)
            if let strength = displayedStrength {
                VStack(spacing: 5) {
                    Text("Army \(strength)")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier(AccessibilityID.Army.handDetail(strength))
                    Text(ArmyStyle.effect(strength: strength))
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("\(state.armyDeck.count) left in the deck\nRivals' army cards: " + rivalArmyCounts)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Public: how many army cards each rival holds, never their strengths.
    private var rivalArmyCounts: String {
        state.players.map(\.id).filter { $0 != player }.sorted()
            .map { "\(playerName($0)) \(state.armyHands[$0, default: []].count)" }
            .joined(separator: " · ")
    }

    private var canDeployArmy: Bool {
        guard case .mainTurn(let seat) = state.phase, seat == player.index else { return false }
        return !Conquest.deployMoves(for: player, in: state).isEmpty
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isArmyTab ? "shield.lefthalf.filled"
                  : mode == .hand ? "rectangle.stack.fill" : "rectangle.stack.badge.plus")
                .font(.title3)
                .foregroundStyle(SettingsChrome.ornamentGold)
            VStack(alignment: .leading, spacing: 2) {
                Text(isArmyTab ? "Army Cards" : mode == .hand ? "Development Cards" : "New Development Card")
                    .font(.system(size: 21, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text(isArmyTab ? "Inspect your army, then deploy it."
                     : mode == .hand ? "Inspect your hand and choose a card." : "Added safely to your private hand.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
    }

    private func handStrip(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your hand")
                    .font(.caption.bold())
                    .foregroundStyle(SettingsChrome.ornamentGold)
                Spacer()
                let count = inventory.reduce(0) { $0 + $1.held }
                Text("\(count) \(count == 1 ? "card" : "cards")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }

            if inventory.isEmpty {
                SettingsInfoPlaque(text: "Your first purchased development card will appear here.")
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(inventory) { item in
                            DevCardInventoryTile(item: item, isSelected: displayedType == item.type,
                                                 maximumWidth: width) {
                                selectedType = item.type
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .scrollTargetLayout()
                }
                .accessibilityIdentifier("dev-cards.hand-scroll")
                .scrollTargetBehavior(.viewAligned)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cardDetail(_ type: DevCardType) -> some View {
        let status = displayedStatus(for: type)
        return VStack(spacing: 12) {
            DevCardFace(type: type, countLabel: detailCount(for: type), isCompact: mode == .hand)
            if mode == .hand, type != .victoryPoint,
               let item = inventory.first(where: { $0.type == type }),
               item.ready > 0, item.boughtThisTurn > 0 {
                Text(DevCardDisplay.inventoryBadge(item))
                    .font(.caption).foregroundStyle(DevCardChrome.ivory.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Only when the card CANNOT be played. A playable card already
            // says so three times over - the hand tile badges it READY, the
            // action button reads "Play Knight", and the button's subtitle
            // names what playing it will ask for - so the plaque's "Ready to
            // play / This card can be used now" was a fourth copy sitting
            // between the description and the button it describes. When the
            // card is blocked the plaque is the ONLY place the reason appears
            // in full, which is why it stays for exactly that case.
            if !status.isPlayable {
                DevCardStatusPlaque(type: type, status: status)
            }

            if mode == .hand, status.isPlayable {
                choiceArea(for: type)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detailCount(for type: DevCardType) -> String {
        if case .reveal = mode { return "+1 card" }
        return "×\(inventory.first(where: { $0.type == type })?.held ?? 0)"
    }

    /// A purchase reveal describes the one card that just entered the hand,
    /// not the aggregate stack. If an older Monopoly is ready and a second is
    /// bought, the new copy still becomes playable on a later turn.
    private func displayedStatus(for type: DevCardType) -> DevCardPlayStatus {
        if case .reveal(let reveal) = mode,
           reveal.card == type,
           type != .victoryPoint {
            return .boughtThisTurn
        }
        return DevCards.playStatus(type, by: player, in: state)
    }

    @ViewBuilder
    private func choiceArea(for type: DevCardType) -> some View {
        switch type {
        case .yearOfPlenty:
            plentyChooser
        case .monopoly:
            monopolyChooser
        case .knight, .roadBuilding, .victoryPoint:
            EmptyView()
        }
    }

    private var monopolyChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collect from rivals").font(.subheadline.bold()).foregroundStyle(DevCardChrome.gold)
            LazyVGrid(columns: resourceColumns, spacing: 8) {
                ForEach(Resource.allCases, id: \.self) { resource in
                    DevCardResourceChoice(resource: resource, count: nil, isEnabled: true,
                                          isSelected: monopolyPick == resource) { monopolyPick = resource }
                        .accessibilityIdentifier(AccessibilityID.DevCards.resource(resource))
                }
            }
        }
    }

    private var plentyChooser: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Choose two resources").font(.subheadline.bold()).foregroundStyle(DevCardChrome.gold)
            Text("\(yearOfPlentyPicks.count) of 2 selected · tap a chosen card to remove it")
                .font(.caption).foregroundStyle(DevCardChrome.ivory.opacity(0.8))
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in plentySlot(index) }
            }
            Text("Bank supply").font(.caption).foregroundStyle(DevCardChrome.ivory.opacity(0.8))
            LazyVGrid(columns: resourceColumns, spacing: 8) {
                ForEach(Resource.allCases, id: \.self) { resource in
                    DevCardResourceChoice(resource: resource, count: state.bank[resource] ?? 0,
                                          isEnabled: canAddYearOfPlenty(resource)) { addYearOfPlenty(resource) }
                        .accessibilityIdentifier(AccessibilityID.DevCards.resource(resource))
                }
            }
        }
        .padding(10)
        .background(PaintedChromeBackground(fill: .tintedTexture(DevCardChrome.ink), cornerRadius: 10))
    }

    private var resourceColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6),
              count: dynamicTypeSize.isAccessibilitySize ? 2 : Resource.allCases.count)
    }

    private func plentySlot(_ index: Int) -> some View {
        let picks = yearOfPlentyPicks
        let resource = index < picks.count ? picks[index] : nil
        let identifier = resource.map {
            picks.firstIndex(of: $0) == index ? "dev-cards.selected.\($0.rawValue)" : "dev-cards.selected.slot.\(index)"
        } ?? "dev-cards.selected.slot.\(index)"
        return DevCardPickSlot(resource: resource, identifier: identifier) {
            if let resource { removeYearOfPlenty(resource) }
        }
    }

    private var emptyHand: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(DevCardChrome.gold)
                .accessibilityHidden(true)
            Text("No development cards yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Buy one from Build using 1 ore, 1 grain, and 1 wool.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch mode {
        case .reveal(let reveal):
            VStack(spacing: 9) {
                GoldRowButton(
                    title: "View My Cards",
                    systemImage: "rectangle.stack.fill",
                    iconColor: DevCardChrome.gold
                ) {
                    onViewCards(reveal.card)
                }
                .accessibilityIdentifier(AccessibilityID.DevCards.viewHand)

                GoldRowButton(
                    title: revealButtonTitle(reveal),
                    systemImage: revealButtonIcon(reveal),
                    iconColor: SettingsChrome.ornamentGold,
                    action: onDismiss
                )
                .accessibilityIdentifier(AccessibilityID.DevCards.continueAction)
            }
        case .hand:
            VStack(spacing: 9) {
                if tab == .army && showsArmyTab {
                    GoldRowButton(
                        title: "Deploy Army",
                        subtitle: canDeployArmy ? "Tap a hex your buildings touch" : "Deploy on your own turn",
                        systemImage: "flag.fill",
                        iconColor: ArmyStyle.color,
                        isEnabled: canDeployArmy,
                        action: onDeployArmy
                    )
                    .accessibilityIdentifier(AccessibilityID.Army.handDeploy)
                } else if let type = displayedType, type != .victoryPoint {
                    let status = DevCards.playStatus(type, by: player, in: state)
                    GoldRowButton(
                        title: playButtonTitle(for: type),
                        subtitle: status.isPlayable ? playButtonSubtitle(for: type) : DevCardStyle.statusTitle(for: status),
                        systemImage: "play.fill",
                        iconColor: DevCardChrome.gold,
                        isEnabled: canSubmit(type, status: status)
                    ) {
                        submit(type)
                    }
                    .accessibilityIdentifier(AccessibilityID.DevCards.play(type))
                }
                GoldRowButton(title: "Close", systemImage: "xmark", action: onDismiss)
                    .accessibilityIdentifier(AccessibilityID.DevCards.close)
            }
        }
    }

    private func revealButtonTitle(_ reveal: DevCardReveal) -> String {
        if reveal.card == .victoryPoint, case .gameOver = state.phase { return "Claim Victory" }
        return "Continue"
    }

    private func revealButtonIcon(_ reveal: DevCardReveal) -> String {
        if reveal.card == .victoryPoint, case .gameOver = state.phase { return "crown.fill" }
        return "checkmark"
    }

    private func playButtonTitle(for type: DevCardType) -> String {
        "Play \(DevCardStyle.fullName(for: type))"
    }

    private func playButtonSubtitle(for type: DevCardType) -> String? {
        switch type {
        case .knight: "Choose the robber's destination"
        case .roadBuilding: "Choose two roads on the board"
        case .yearOfPlenty: "\(yearOfPlentyPicks.count) of 2 selected"
        case .monopoly: monopolyPick.map { $0.rawValue.capitalized } ?? "Choose a resource"
        case .victoryPoint: nil
        }
    }

    private func canSubmit(_ type: DevCardType, status: DevCardPlayStatus) -> Bool {
        guard status.isPlayable else { return false }
        switch type {
        case .yearOfPlenty: return yearOfPlentyPicks.count == 2
        case .monopoly: return monopolyPick != nil
        case .knight, .roadBuilding: return true
        case .victoryPoint: return false
        }
    }

    private func submit(_ type: DevCardType) {
        switch type {
        case .knight, .roadBuilding:
            onBeginBoardCard(type)
        case .yearOfPlenty:
            let resources = expandedYearOfPlenty
            guard resources.count == 2 else { return }
            errorMessage = onCommit(.playYearOfPlenty(resources[0], resources[1]))
        case .monopoly:
            guard let monopolyPick else { return }
            errorMessage = onCommit(.playMonopoly(monopolyPick))
        case .victoryPoint:
            break
        }
    }

    private var expandedYearOfPlenty: [Resource] {
        Resource.allCases.flatMap { resource in
            yearOfPlentyPicks.filter { $0 == resource }
        }
    }

    private func canAddYearOfPlenty(_ resource: Resource) -> Bool {
        let picks = expandedYearOfPlenty
        guard picks.count < 2 else { return false }
        guard let first = picks.first else { return (state.bank[resource] ?? 0) > 0 }
        return DevCards.canTakeForYearOfPlenty(first, resource, from: state)
    }

    private func addYearOfPlenty(_ resource: Resource) {
        guard canAddYearOfPlenty(resource) else { return }
        yearOfPlentyPicks.append(resource)
    }

    private func removeYearOfPlenty(_ resource: Resource) {
        guard let index = yearOfPlentyPicks.firstIndex(of: resource) else { return }
        yearOfPlentyPicks.remove(at: index)
    }

    private func resetChoices() {
        yearOfPlentyPicks = []
        monopolyPick = nil
        errorMessage = nil
    }
}

/// Explicit result acknowledgement for successful active-card plays.
struct DevelopmentCardResultOverlay: View {
    let resolution: DevCardResolution
    let playerIdentity: (PlayerID) -> PlayerIdentity
    let isWinningResult: Bool
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.68).ignoresSafeArea()
                ViewThatFits(in: .vertical) {
                    panel(scrolling: false, maxHeight: nil)
                    panel(scrolling: true, maxHeight: max(320, geometry.size.height - 28))
                }
            }
        }
        .transition(.opacity)
    }

    /// Result text can grow with names and Dynamic Type. Only the message
    /// scrolls; the explicit acknowledgement must always remain reachable.
    private func panel(scrolling: Bool, maxHeight: CGFloat?) -> some View {
        VStack(spacing: 14) {
            Text("\(DevCardStyle.fullName(for: resolution.card)) resolved")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.DevCards.result)
            if scrolling {
                ScrollView { resultContent }.scrollIndicators(.visible)
            } else {
                resultContent
            }
            GoldRowButton(
                title: isWinningResult ? "Claim Victory" : "Continue",
                systemImage: isWinningResult ? "crown.fill" : "checkmark",
                iconColor: DevCardChrome.gold,
                action: onContinue
            )
            .accessibilityIdentifier(AccessibilityID.DevCards.resultContinue)
        }
        .fontDesign(.serif)
        .foregroundStyle(DevCardChrome.ivory)
        .padding(18)
        .frame(maxWidth: 366, maxHeight: maxHeight)
        .background(PaintedChromeBackground(fill: .tintedTexture(DevCardChrome.ink), cornerRadius: 18))
        .padding(14)
    }

    private var resultContent: some View {
        VStack(spacing: 14) {
            DevCardIllustration(type: resolution.card)
            message
                .accessibilityLabel(spokenMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The same sentence without the square glyphs, which VoiceOver would
    /// otherwise read aloud as "square fill".
    private var spokenMessage: String {
        switch resolution {
        case .knight(_, let victim, let stolen):
            guard let victim else { return "The robber moved. No rival was eligible to steal from." }
            let name = playerIdentity(victim).displayName
            if let stolen { return "You stole 1 \(stolen.rawValue.capitalized) from \(name)." }
            return "The robber moved beside \(name), who had no resource card to steal."
        case .roadBuilding:
            return "Both free roads were placed together and your network has been updated."
        case .yearOfPlenty(_, let taken):
            return "The bank gave you \(IncomingTradeSummary.resources(taken, separator: " and "))."
        case .monopoly(_, let resource, let gained):
            let name = resource.rawValue.capitalized
            if gained == 0 { return "No rival held any \(name). You collected 0 cards." }
            return "Every rival surrendered their \(name). You collected \(gained) cards."
        }
    }

    private var message: Text {
        switch resolution {
        case .knight(_, let victim, let stolen):
            guard let victim else { return Text("The robber moved. No rival was eligible to steal from.") }
            let name = playerIdentity(victim).displayName
            if let stolen { return Text("You stole ") + ResourceText.term(stolen, count: 1) + Text(" from \(name).") }
            return Text("The robber moved beside \(name), who had no resource card to steal.")
        case .roadBuilding:
            return Text("Both free roads were placed together and your network has been updated.")
        case .yearOfPlenty(_, let taken):
            return Text("The bank gave you ") + ResourceText.list(taken, separator: " and ") + Text(".")
        case .monopoly(_, let resource, let gained):
            if gained == 0 {
                return Text("No rival held any ") + ResourceText.term(resource) + Text(". You collected 0 cards.")
            }
            return Text("Every rival surrendered their ") + ResourceText.term(resource)
                + Text(". You collected \(gained) cards.")
        }
    }
}

private struct DevCardStatusPlaque: View {
    let type: DevCardType
    let status: DevCardPlayStatus

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(DevCardChrome.gold)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(DevCardStyle.statusTitle(for: status))
                    .font(.subheadline.bold())
                Text(DevCardStyle.statusDetail(for: status, type: type))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.DevCards.status)
    }

    private var icon: String {
        switch status {
        case .playable: "checkmark.seal.fill"
        case .passiveVictoryPoint: "star.circle.fill"
        case .boughtThisTurn: "clock.badge.checkmark"
        case .notOwned, .waitingForYourTurn, .alreadyPlayedThisTurn,
             .resolveRequiredAction, .noLegalChoices, .gameOver: "hourglass.circle.fill"
        }
    }
}

/// Shared themed card chrome for compact popups. Persistent development-card
/// content uses `DevelopmentCardOverlay` because it has different dismissal
/// and safe-height requirements.
public struct PopupCard<Content: View>: View {
    public let onDismiss: () -> Void
    @ViewBuilder public let content: Content
    public var alignment: Alignment = .center

    public init(onDismiss: @escaping () -> Void,
                alignment: Alignment = .center,
                @ViewBuilder content: () -> Content) {
        self.onDismiss = onDismiss
        self.alignment = alignment
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: alignment) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(CatanTheme.panelBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .foregroundStyle(CatanTheme.onWaterText)
                .padding(.horizontal, 32)
                .padding(.top, alignment == .top ? 96 : 0)
                .shadow(radius: 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
