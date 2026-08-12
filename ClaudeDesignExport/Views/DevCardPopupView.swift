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

    @State private var yopFirst: Resource = .brick
    @State private var yopSecond: Resource = .brick
    @State private var monopolyResource: Resource = .brick

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
                    HStack(spacing: 10) {
                        resourcePicker("First", selection: $yopFirst)
                        resourcePicker("Second", selection: $yopSecond)
                    }
                    confirmRow(title: "Play Year of Plenty") { onPlayYearOfPlenty(yopFirst, yopSecond) }
                case .monopoly:
                    resourcePicker("Resource", selection: $monopolyResource)
                    confirmRow(title: "Play Monopoly") { onPlayMonopoly(monopolyResource) }
                case .victoryPoint:
                    Text("Victory Point cards are never played - they just count toward your total.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func resourcePicker(_ label: String, selection: Binding<Resource>) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                ForEach(Resource.allCases, id: \.self) { resource in
                    Label(resource.rawValue.capitalized, systemImage: CatanTheme.symbolName(for: resource))
                        .tag(resource)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func confirmRow(title: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
        }
    }

    private var icon: String {
        switch type {
        case .knight: return "shield.fill"
        case .roadBuilding: return "road.lanes"
        case .yearOfPlenty: return "sparkles"
        case .monopoly: return "crown.fill"
        case .victoryPoint: return "star.fill"
        }
    }

    private var color: Color {
        switch type {
        case .knight: return .red
        case .roadBuilding: return .brown
        case .yearOfPlenty: return .green
        case .monopoly: return .purple
        case .victoryPoint: return Color(red: 0.85, green: 0.65, blue: 0.1)
        }
    }

    private var title: String {
        switch type {
        case .knight: return "Knight"
        case .roadBuilding: return "Road Building"
        case .yearOfPlenty: return "Year of Plenty"
        case .monopoly: return "Monopoly"
        case .victoryPoint: return "Victory Point"
        }
    }
}

/// Shared themed card chrome for the popups that replaced sheets in this
/// pass (`DevCardPopupView`, `TradePopupView`): a dimmed scrim behind a
/// rounded card, tap-outside-to-dismiss via the scrim.
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
