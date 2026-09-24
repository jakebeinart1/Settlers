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

    @State private var yearOfPlentyPicks: [Resource: Int] = [:]
    @State private var monopolyPick: Resource?
    @State private var errorMessage: String?

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
                    panel(scrolling: false, maxHeight: nil)
                    panel(scrolling: true, maxHeight: max(320, geometry.size.height - 28))
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
    private func panel(scrolling: Bool, maxHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

            Divider().overlay(SettingsChrome.ornamentGold.opacity(0.35))

            if scrolling {
                ScrollView { middle }
                    .scrollIndicators(.visible)
            } else {
                middle
            }

            Divider().overlay(SettingsChrome.ornamentGold.opacity(0.35))
            actionArea
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
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .shadow(color: .black.opacity(0.65), radius: 28, y: 12)
    }

    private var middle: some View {
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
                if mode == .hand { handStrip }
                if let type = displayedType {
                    cardDetail(type)
                } else {
                    emptyHand
                }
            }
        }
        .padding(16)
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
                  : mode == .hand ? "rectangle.stack.fill" : "sparkles.rectangle.stack.fill")
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

    private var handStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOUR HAND")
                    .font(.caption.bold())
                    .foregroundStyle(SettingsChrome.ornamentGold)
                Spacer()
                Text("\(inventory.reduce(0) { $0 + $1.held }) cards")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }

            if inventory.isEmpty {
                SettingsInfoPlaque(text: "Your first purchased development card will appear here.")
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(inventory) { item in
                            DevCardHandTile(item: item, isSelected: displayedType == item.type) {
                                selectedType = item.type
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func cardDetail(_ type: DevCardType) -> some View {
        let status = displayedStatus(for: type)
        return VStack(spacing: 12) {
            DevCardArtwork(type: type)

            VStack(spacing: 5) {
                Text(DevCardStyle.fullName(for: type))
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(AccessibilityID.DevCards.detail(type))
                Text(DevCardStyle.effect(for: type))
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
            resourceChooser(
                title: "Choose two from the bank",
                selected: yearOfPlentyPicks,
                canSelect: canAddYearOfPlenty,
                onSelect: addYearOfPlenty,
                onRemove: removeYearOfPlenty
            )
        case .monopoly:
            resourceChooser(
                title: "Name one resource",
                selected: monopolyPick.map { [$0: 1] } ?? [:],
                canSelect: { _ in true },
                onSelect: { monopolyPick = $0 },
                onRemove: { _ in monopolyPick = nil }
            )
        case .knight, .roadBuilding, .victoryPoint:
            EmptyView()
        }
    }

    private func resourceChooser(
        title: String,
        selected: [Resource: Int],
        canSelect: @escaping (Resource) -> Bool,
        onSelect: @escaping (Resource) -> Void,
        onRemove: @escaping (Resource) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(SettingsChrome.ornamentGold)
            ResourceSlotRow(counts: selected, onTap: onRemove)
            HStack(spacing: 8) {
                ForEach(Resource.allCases, id: \.self) { resource in
                    ResourceChip(
                        resource: resource,
                        count: state.bank[resource] ?? 0,
                        isEnabled: canSelect(resource)
                    ) {
                        onSelect(resource)
                    }
                    .accessibilityIdentifier(AccessibilityID.DevCards.resource(resource))
                }
            }
        }
        .padding(10)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
    }

    private var emptyHand: some View {
        VStack(spacing: 14) {
            DevCardArtwork(type: .victoryPoint, isEmpty: true)
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
                    iconColor: DevCardStyle.color(for: reveal.card)
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
                        iconColor: DevCardStyle.color(for: type),
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
        case .yearOfPlenty: "\(yearOfPlentyPicks.values.reduce(0, +)) of 2 selected"
        case .monopoly: monopolyPick.map { $0.rawValue.capitalized } ?? "Choose a resource"
        case .victoryPoint: nil
        }
    }

    private func canSubmit(_ type: DevCardType, status: DevCardPlayStatus) -> Bool {
        guard status.isPlayable else { return false }
        switch type {
        case .yearOfPlenty: return yearOfPlentyPicks.values.reduce(0, +) == 2
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
            Array(repeating: resource, count: yearOfPlentyPicks[resource] ?? 0)
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
        yearOfPlentyPicks[resource, default: 0] += 1
    }

    private func removeYearOfPlenty(_ resource: Resource) {
        yearOfPlentyPicks[resource, default: 0] -= 1
        if yearOfPlentyPicks[resource] == 0 { yearOfPlentyPicks[resource] = nil }
    }

    private func resetChoices() {
        yearOfPlentyPicks = [:]
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
        PopupCard(onDismiss: {}, content: {
            VStack(spacing: 14) {
                DevCardArtwork(type: resolution.card)
                Text("\(DevCardStyle.fullName(for: resolution.card)) resolved")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .accessibilityIdentifier(AccessibilityID.DevCards.result)
                Text(message)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                GoldRowButton(
                    title: isWinningResult ? "Claim Victory" : "Continue",
                    systemImage: isWinningResult ? "crown.fill" : "checkmark",
                    iconColor: SettingsChrome.ornamentGold,
                    action: onContinue
                )
                .accessibilityIdentifier(AccessibilityID.DevCards.resultContinue)
            }
            .padding(18)
            .frame(maxWidth: 330)
        })
    }

    private var message: String {
        switch resolution {
        case .knight(_, let victim, let stolen):
            guard let victim else { return "The robber moved. No rival was eligible to steal from." }
            let name = playerIdentity(victim).displayName
            if let stolen { return "You stole 1 \(stolen.rawValue) from \(name)." }
            return "The robber moved beside \(name), who had no resource card to steal."
        case .roadBuilding:
            return "Both free roads were placed together and your network has been updated."
        case .yearOfPlenty(_, let taken):
            let parts = Resource.allCases.compactMap { resource -> String? in
                guard let count = taken[resource], count > 0 else { return nil }
                return "\(count) \(resource.rawValue)"
            }
            return "The bank gave you \(parts.joined(separator: " and "))."
        case .monopoly(_, let resource, let gained):
            if gained == 0 { return "No rival held any \(resource.rawValue). You collected 0 cards." }
            return "Every rival surrendered their \(resource.rawValue). You collected \(gained) cards."
        }
    }
}

private struct DevCardArtwork: View {
    let type: DevCardType
    var isEmpty = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(DevCardStyle.color(for: type).opacity(isEmpty ? 0.14 : 0.32).gradient)
            Circle()
                .stroke(SettingsChrome.ornamentGold.opacity(0.32), lineWidth: 1)
                .frame(width: 104, height: 104)
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: 78, height: 78)
            Image(systemName: isEmpty ? "rectangle.stack.badge.plus" : DevCardStyle.icon(for: type))
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(isEmpty ? .white.opacity(0.5) : DevCardStyle.color(for: type))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        }
        .frame(height: 124)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(SettingsChrome.ornamentGold.opacity(0.7), lineWidth: 1.25)
        )
        .accessibilityHidden(true)
    }
}

private struct DevCardStatusPlaque: View {
    let type: DevCardType
    let status: DevCardPlayStatus

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
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

    private var color: Color {
        status.isPlayable || status == .passiveVictoryPoint ? .green : SettingsChrome.ornamentGold
    }
}

private struct DevCardHandTile: View {
    let item: DevCardInventoryItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: DevCardStyle.icon(for: item.type))
                    .font(.title3)
                Text(DevCardStyle.shortName(for: item.type))
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("×\(item.held)")
                    .font(.caption2.bold())
                Text(badge)
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .lineLimit(1)
                    // "1 READY · 1 NEW" is wider than the 70pt tile at 8pt
                    // serif, and `lineLimit(1)` alone let it hang off both
                    // sides of the tile rather than truncate. It is the
                    // longest badge this tile can hold, so it is the one the
                    // width has to be sized against.
                    .minimumScaleFactor(0.62)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(width: 70, height: 76)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(DevCardStyle.color(for: item.type).opacity(0.48).gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isSelected ? SettingsChrome.ornamentGold : .white.opacity(0.28),
                                  lineWidth: isSelected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier(AccessibilityID.DevCards.tile(item.type))
    }

    private var badge: String {
        if item.status == .passiveVictoryPoint { return "PASSIVE" }
        if item.ready > 0, item.boughtThisTurn > 0 {
            return "\(item.ready) READY · \(item.boughtThisTurn) NEW"
        }
        if item.ready > 0 { return "\(item.ready) READY" }
        return "\(item.boughtThisTurn) NEW"
    }

    private var accessibilityLabel: String {
        let name = DevCardStyle.fullName(for: item.type)
        if item.status == .passiveVictoryPoint { return "\(name), \(item.held) owned, passive" }
        return "\(name), \(item.held) owned, \(item.ready) ready, \(item.boughtThisTurn) new"
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
