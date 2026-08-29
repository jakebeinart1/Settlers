import SwiftUI
import CatanEngine

/// Small overlay card for playing a dev card, opened by tapping its tile in
/// `HumanPlayerPanel` (replaces the old `DevCardPanelView` sheet + separate
/// `RobberTargetView` sheet). Year of Plenty/Monopoly resolve entirely here
/// (bank-only, no board interaction); Knight/Road Building just confirm
/// intent, then hand off to `GameView` to arm the same inline board flow
/// used for the mandatory post-7-roll robber move.
public struct DevCardPopupView: View {
    public let type: DevCardType
    /// Called once the human confirms playing a Knight or Road Building card
    /// - `GameView` arms the matching inline board flow in response.
    public let onPlayBoardCard: (DevCardType) -> Void
    public let onPlayYearOfPlenty: (Resource, Resource) -> Void
    public let onPlayMonopoly: (Resource) -> Void
    public let onCancel: () -> Void

    public init(
        type: DevCardType,
        onPlayBoardCard: @escaping (DevCardType) -> Void,
        onPlayYearOfPlenty: @escaping (Resource, Resource) -> Void,
        onPlayMonopoly: @escaping (Resource) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.type = type
        self.onPlayBoardCard = onPlayBoardCard
        self.onPlayYearOfPlenty = onPlayYearOfPlenty
        self.onPlayMonopoly = onPlayMonopoly
        self.onCancel = onCancel
    }

    // Picks are counted dictionaries (like `TradePopupView`'s Give/Want)
    // rather than plain `Resource?`/`(Resource, Resource)` state, so the
    // same `ResourceSlotRow`/`ResourceChip` "dots" the trade view uses for
    // Give/Want can display and un-pick them the same way - tap a dot below
    // to add, tap it in the chosen row to take it back out. Year of Plenty
    // allows picking the same resource twice, which a dictionary of counts
    // represents naturally; Monopoly just caps its own dictionary at 1.
    @State private var yopPicks: [Resource: Int] = [:]
    @State private var monopolyPicks: [Resource: Int] = [:]

    public var body: some View {
        PopupCard(onDismiss: onCancel) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.headline)
                }

                switch type {
                case .knight:
                    Text("Move the robber and steal a card from a neighboring player.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    confirmRow(title: "Play Knight") { onPlayBoardCard(.knight) }
                case .roadBuilding:
                    Text("Build two roads for free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    confirmRow(title: "Play Road Building") { onPlayBoardCard(.roadBuilding) }
                case .yearOfPlenty:
                    resourcePickerCard(title: "Choose 2 resources", picks: $yopPicks, limit: 2)
                    confirmRow(title: "Play Year of Plenty", isEnabled: totalPicks(yopPicks) == 2) {
                        let picked = expand(yopPicks)
                        onPlayYearOfPlenty(picked[0], picked[1])
                    }
                case .monopoly:
                    resourcePickerCard(title: "Choose 1 resource", picks: $monopolyPicks, limit: 1)
                    confirmRow(title: "Play Monopoly", isEnabled: totalPicks(monopolyPicks) == 1) {
                        onPlayMonopoly(expand(monopolyPicks)[0])
                    }
                case .victoryPoint:
                    Text("Victory Point cards are never played - they just count toward your total.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: 340)
        }
    }

    // MARK: - Resource picker (Year of Plenty / Monopoly)

    /// Same chosen-slot-plus-palette shape as `TradePopupView`'s Give/Want:
    /// a `ResourceSlotRow` showing what's picked so far (tap a dot there to
    /// un-pick it), then a row of all five resources to tap and add - capped
    /// at `limit` total picks so Monopoly can't take more than one and Year
    /// of Plenty can't take more than two.
    private func resourcePickerCard(title: String, picks: Binding<[Resource: Int]>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ResourceSlotRow(counts: picks.wrappedValue, emptyText: "Tap a resource below") { resource in
                picks.wrappedValue[resource] = (picks.wrappedValue[resource] ?? 0) - 1
                if picks.wrappedValue[resource] == 0 { picks.wrappedValue[resource] = nil }
            }
            HStack(spacing: 8) {
                ForEach(Resource.allCases, id: \.self) { resource in
                    let canAdd = totalPicks(picks.wrappedValue) < limit
                    ResourceChip(resource: resource, count: nil, isEnabled: canAdd) {
                        picks.wrappedValue[resource] = (picks.wrappedValue[resource] ?? 0) + 1
                    }
                }
            }
        }
    }

    private func totalPicks(_ picks: [Resource: Int]) -> Int {
        picks.values.reduce(0, +)
    }

    /// Flattens a counted-picks dictionary back into a plain list, e.g.
    /// `[.brick: 2]` -> `[.brick, .brick]`.
    private func expand(_ picks: [Resource: Int]) -> [Resource] {
        picks.flatMap { resource, count in Array(repeating: resource, count: count) }
    }

    private func confirmRow(title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        // Stacked, not side-by-side - "Play Monopoly"/"Play Year of Plenty"
        // wrapped mid-word when squeezed into half this popup's width
        // alongside Cancel (see chat).
        VStack(spacing: 10) {
            GoldRowButton(title: "Cancel", systemImage: "xmark", action: onCancel)
            GoldRowButton(title: title, systemImage: "checkmark", iconColor: color, isEnabled: isEnabled, action: action)
        }
    }

    // See `DevCardStyle` - shared with the HUD's dev-card strip.
    private var icon: String { DevCardStyle.icon(for: type) }
    private var color: Color { DevCardStyle.color(for: type) }
    private var title: String { DevCardStyle.fullName(for: type) }
}

/// Shared themed card chrome for the popups that replaced sheets in this
/// pass (`DevCardPopupView`, `TradePopupView`): a dimmed scrim behind a
/// rounded card, tap-outside-to-dismiss via the scrim. No scroll mechanism -
/// an earlier version of this scrolled/capped tall content (added when
/// `TradePopupView`'s "a bot will accept" banner briefly overflowed its
/// reserved space - see `TradePopupView.statusRegionHeight`'s own doc
/// comment), but that overflow was the actual bug, not something to scroll
/// around; every popup's content is sized to always fit on screen as-is, so
/// there's nothing here that needs to scroll (per Jake's ask).
public struct PopupCard<Content: View>: View {
    public let onDismiss: () -> Void
    @ViewBuilder public let content: Content

    public init(onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        ZStack {
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
                .shadow(radius: 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
