import SwiftUI
import CatanEngine

/// The single command surface for every uncommitted board action.
///
/// `BoardDecisionPresentation` is the only state input: the dock never
/// reconstructs legality or a `GameMove`. It renders the coordinator's exact
/// proposal and forwards semantic commands so taps, drags, VoiceOver, and QA
/// all travel through the same transaction boundary.
struct BoardDecisionDockView: View {
    let presentation: BoardDecisionPresentation
    let playerIdentity: (PlayerID) -> PlayerIdentity
    let victimResourceCount: (PlayerID) -> Int
    let onConfirm: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    let onUndo: () -> Void
    let onSelectVictim: (PlayerID) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        presentation: BoardDecisionPresentation,
        identity: @escaping (PlayerID) -> PlayerIdentity,
        resourceCount: @escaping (PlayerID) -> Int,
        onSelectVictim: @escaping (PlayerID) -> Void,
        onUndo: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.playerIdentity = identity
        self.victimResourceCount = resourceCount
        self.onConfirm = onConfirm
        self.onClear = onClear
        self.onCancel = onCancel
        self.onUndo = onUndo
        self.onSelectVictim = onSelectVictim
    }

    var body: some View {
        let actor = playerIdentity(presentation.actor)
        HStack(spacing: Layout.itemSpacing) {
            // Once a territory is chosen, the eligible rivals are the
            // decision. The board already keeps the robber in its draggable
            // cradle, so repeating that piece here only hides the third victim
            // on compact phones. Spend the dock width on all three identities.
            if showsPieceCradle {
                DecisionPieceCradle(presentation: presentation, identity: actor)
            }
            messageOrVictims
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsUndo { undoButton }
            clearButton
            if presentation.canCancel { cancelButton }
            confirmButton
        }
        .padding(Layout.inset)
        .frame(height: dockHeight)
        .background(dockBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.BoardDecision.dock)
    }

    @ViewBuilder
    private var messageOrVictims: some View {
        if presentation.requiresVictimChoice {
            victimPicker
        } else {
            decisionMessage
        }
    }

    private var decisionMessage: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.title)
                .font(.system(.caption, design: .serif, weight: .bold))
                .foregroundStyle(CatanTheme.onWaterText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Label {
                Text(presentation.detail)
            } icon: {
                Image(systemName: presentation.errorMessage == nil
                      ? "sparkles" : "exclamationmark.triangle.fill")
            }
            .font(.caption2)
            .foregroundStyle(presentation.errorMessage == nil
                             ? .white.opacity(0.78) : Color.red.opacity(0.95))
            .lineLimit(2)
            .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var victimPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.errorMessage ?? "Steal from")
                .font(.system(.caption2, design: .serif, weight: .bold))
                .foregroundStyle(presentation.errorMessage == nil ? CatanTheme.onWaterText : Color.red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Layout.victimSpacing) {
                    ForEach(presentation.legalVictims, id: \.self) { victim in
                        victimChoice(victim)
                    }
                }
            }
        }
    }

    private func victimChoice(_ victim: PlayerID) -> some View {
        let identity = playerIdentity(victim)
        return DockVictimButton(
            identity: identity,
            resourceCardCount: victimResourceCount(victim),
            isSelected: presentation.selectedVictim == victim,
            action: { onSelectVictim(victim) }
        )
    }

    private var undoButton: some View {
        DockActionButton(
            title: "Undo", systemImage: "arrow.uturn.backward",
            width: Layout.secondaryButtonWidth,
            fill: .color(Color(white: 0.16)),
            accessibilityIdentifier: AccessibilityID.BoardDecision.undo,
            action: onUndo
        )
    }

    private var clearButton: some View {
        DockActionButton(
            title: "Clear",
            systemImage: "eraser.fill",
            width: Layout.secondaryButtonWidth,
            fill: .color(Color(white: 0.16)),
            isEnabled: hasSelection,
            accessibilityIdentifier: AccessibilityID.BoardDecision.clear,
            action: onClear
        )
    }

    private var cancelButton: some View {
        DockActionButton(
            title: "Cancel",
            systemImage: "xmark",
            width: Layout.secondaryButtonWidth,
            fill: .color(Color(white: 0.16)),
            accessibilityIdentifier: AccessibilityID.BoardDecision.cancel,
            action: onCancel
        )
    }

    private var confirmButton: some View {
        DockActionButton(
            title: presentation.confirmTitle,
            systemImage: "checkmark",
            width: Layout.confirmButtonWidth,
            fill: .tintedTexture(Color(red: 0.22, green: 0.48, blue: 0.30)),
            isEnabled: presentation.canConfirm,
            accessibilityIdentifier: AccessibilityID.BoardDecision.confirm,
            action: onConfirm
        )
    }

    private var showsUndo: Bool {
        presentation.intent == .roadBuilding && !presentation.selectedEdges.isEmpty
    }

    private var showsPieceCradle: Bool {
        !presentation.requiresVictimChoice && !presentation.canCancel
    }

    private var hasSelection: Bool {
        presentation.selectedVertex != nil || !presentation.selectedEdges.isEmpty
            || presentation.selectedTile != nil || presentation.selectedVictim != nil
    }

    private var dockHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? Layout.accessibilityDockHeight
            : BottomRowMetrics.height
    }

    private var dockBackground: some View {
        PaintedChromeBackground(
            fill: .tintedTexture(CatanTheme.panelBackground),
            cornerRadius: 10,
            notchScale: 0.75
        )
    }
}

/// A horizontal victim card sized specifically for the fixed-height dock.
/// The full-size picker card is intentionally not squeezed into this slot:
/// doing so clips its three vertical labels before a 44-point tap target fits.
private struct DockVictimButton: View {
    let identity: PlayerIdentity
    let resourceCardCount: Int
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                CivilizationCrest(civilization: identity.civilization, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(identity.displayName)
                        .font(.caption2.bold())
                    Text("\(resourceCardCount) \(cardNoun)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            }
            .padding(.horizontal, 3)
            .frame(
                width: Layout.victimWidth,
                height: dynamicTypeSize.isAccessibilitySize
                    ? Layout.accessibilityVictimHeight : Layout.victimHeight,
                alignment: .leading
            )
            .background(TintedTextureBackground(
                tint: identity.civilization.cardBackgroundColor(active: true)
            ))
            .clipShape(FrameCornerRect(cornerRadius: 8, notchScale: 0.7))
            .playerCardBorder(color: identity.civilization.accentColor, cornerRadius: 8, lineWidth: 2)
            .overlay { selectionBorder }
            .overlay(alignment: .topTrailing) { selectionMark }
            .foregroundStyle(.white)
            // This card is a dense, icon-led chooser. Its complete identity is
            // exposed below to assistive technologies; letting two short
            // visual labels grow to Accessibility sizes would hide the other
            // eligible victims instead of making the decision more legible.
            .dynamicTypeSize(...DynamicTypeSize.large)
        }
        .accessibilityIdentifier(AccessibilityID.Robber.victim(identity.seat))
        .accessibilityLabel(
            "\(identity.displayName), \(identity.civilization.displayName), "
                + "\(resourceCardCount) resource \(cardNoun)"
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Select as the player to steal from")
    }

    private var cardNoun: String { resourceCardCount == 1 ? "card" : "cards" }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            FrameCornerRect(cornerRadius: 8, notchScale: 0.7)
                .strokeBorder(PaintedChromeBackground.gold, lineWidth: 3)
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .black))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, CatanTheme.chipGold)
                .offset(x: 2, y: -2)
                .accessibilityHidden(true)
        }
    }
}

private struct DecisionPieceCradle: View {
    let presentation: BoardDecisionPresentation
    let identity: PlayerIdentity

    var body: some View {
        ZStack {
            PaintedChromeBackground(
                fill: .tintedTexture(identity.civilization.cardBackgroundColor(active: true)),
                cornerRadius: 9,
                notchScale: 0.7
            )
            piece
        }
        .frame(width: Layout.cradleSize, height: Layout.cradleSize)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var piece: some View {
        switch presentation.intent {
        case .initialSettlement, .buildSettlement:
            CivilizationBadge(civilization: identity.civilization, isCity: false, size: 33)
        case .buildCity:
            CivilizationBadge(civilization: identity.civilization, isCity: true, size: 35)
        case .initialRoad, .buildRoad:
            RoadCradleGlyph(count: 1, color: identity.civilization.accentColor)
        case .roadBuilding:
            RoadCradleGlyph(count: 2, color: identity.civilization.accentColor)
        case .robberAfterSeven, .knight:
            Image(systemName: "person.fill")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(CatanTheme.robber)
                .shadow(color: CatanTheme.chipGold, radius: 1)
        }
    }
}

private struct RoadCradleGlyph: View {
    let count: Int
    let color: Color

    var body: some View {
        ZStack {
            road
                .rotationEffect(.degrees(-24))
                .offset(x: count == 1 ? 0 : -4, y: count == 1 ? 0 : 5)
            if count == 2 {
                road.rotationEffect(.degrees(24)).offset(x: 4, y: -5)
            }
        }
    }

    private var road: some View {
        Capsule()
            .fill(color)
            .overlay(Capsule().strokeBorder(Color.black, lineWidth: 1.5))
            .frame(width: 34, height: 9)
    }
}

private struct DockActionButton: View {
    let title: String
    let systemImage: String
    let width: CGFloat
    let fill: PaintedChromeBackground.Fill
    var isEnabled = true
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.black))
                Text(title)
                    .font(.caption2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 2)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(
                PaintedChromeBackground(fill: fill, cornerRadius: 8, notchScale: 0.65)
            )
            // Command labels must remain intact inside a 44-point control.
            // The surrounding title and instructions still scale, while the
            // full action name and hint remain available to VoiceOver.
            .dynamicTypeSize(...DynamicTypeSize.large)
        }
        .frame(minWidth: Layout.minimumTapSize, minHeight: Layout.minimumTapSize)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(title)
        .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
        .accessibilityHint(isEnabled ? actionHint : "Choose a complete preview first")
    }

    private var actionHint: String {
        switch title {
        case let value where value.hasPrefix("Confirm"): "Commit this preview to the match"
        case "Cancel": "Abandon this uncommitted action"
        case "Clear": "Remove the preview and keep choosing"
        case "Undo": "Remove the most recently staged road"
        default: "Change this uncommitted preview"
        }
    }
}

private enum Layout {
    static let inset: CGFloat = 5
    static let itemSpacing: CGFloat = 5
    static let cradleSize: CGFloat = 48
    // Three distinct players can border one tile. These dimensions let every
    // eligible identity remain visible together on a 375-point screen.
    static let victimWidth: CGFloat = 64
    static let victimHeight: CGFloat = 48
    static let accessibilityVictimHeight: CGFloat = 58
    static let victimSpacing: CGFloat = 3
    static let secondaryButtonWidth: CGFloat = 44
    static let confirmButtonWidth: CGFloat = 80
    static let minimumTapSize: CGFloat = 44
    static let accessibilityDockHeight: CGFloat = 100
}

private extension BoardDecisionPresentation {
    var requiresVictimChoice: Bool {
        selectedTile != nil && !legalVictims.isEmpty
    }

    var title: String {
        switch intent {
        case .initialSettlement: setupRound == 2 ? "Second settlement" : "First settlement"
        case .initialRoad: setupRound == 2 ? "Second road" : "First road"
        case .buildRoad: "Build a road"
        case .buildSettlement: "Build a settlement"
        case .buildCity: "Build a city"
        case .roadBuilding where selectedEdges.count == 1: "Road Building · 1 of 2"
        case .roadBuilding where selectedEdges.count == 2: "Two roads staged"
        case .roadBuilding: "Road Building"
        case .robberAfterSeven: "Move the robber"
        case .knight: "Play Knight"
        }
    }

    var detail: String {
        if let errorMessage { return errorMessage }
        return switch intent {
        case .initialSettlement:
            selectionDetail("corner", selected: selectedVertex != nil)
        case .initialRoad:
            selectionDetail("edge", selected: !selectedEdges.isEmpty)
        case .buildRoad:
            buildDetail("edge", cost: "Brick + lumber", selected: !selectedEdges.isEmpty)
        case .buildSettlement:
            buildDetail(
                "corner", cost: "Brick + lumber + grain + wool",
                selected: selectedVertex != nil
            )
        case .buildCity:
            buildDetail("settlement", cost: "3 ore + 2 grain", selected: selectedVertex != nil)
        case .roadBuilding:
            roadBuildingDetail
        case .robberAfterSeven, .knight:
            robberDetail
        }
    }

    var confirmTitle: String {
        switch intent {
        case .initialSettlement, .buildSettlement: "Confirm Settlement"
        case .initialRoad, .buildRoad: "Confirm Road"
        case .buildCity: "Confirm City"
        case .roadBuilding: "Confirm 2 Roads"
        case .robberAfterSeven, .knight:
            legalVictims.isEmpty ? "Confirm Move" : "Confirm Steal"
        }
    }

    private func selectionDetail(_ target: String, selected: Bool) -> String {
        selected
            ? "Preview ready. Confirm or choose another \(target)."
            : "Choose a highlighted \(target)."
    }

    private func buildDetail(_ target: String, cost: String, selected: Bool) -> String {
        selected
            ? "Preview ready. Confirm or choose another \(target)."
            : "Choose a highlighted \(target). \(cost)."
    }

    private var roadBuildingDetail: String {
        switch selectedEdges.count {
        case 0: "Choose the first highlighted edge."
        case 1: "Choose a connected second edge."
        default: "Confirm both roads or revise."
        }
    }

    private var robberDetail: String {
        if selectedTile == nil { return "Choose or drag to a highlighted territory." }
        if legalVictims.isEmpty { return "No rival is eligible here. Confirm Move." }
        if selectedVictim == nil { return "Choose a rival before confirming." }
        return "Victim selected. Confirm Steal or choose another rival."
    }
}
