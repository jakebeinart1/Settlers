import SwiftUI
import CatanEngine

/// Copy describes the original producing buildings; progress describes only
/// committed cards. Both survive a reload through the engine's derived query.
nonisolated struct NavalHarvestPresentation: Equatable {
    let progress: NavalHarvestProgress

    var title: String { "Choose \(progress.total) \(progress.total == 1 ? "resource" : "resources")" }
    var collected: String { "\(progress.collected) of \(progress.total) collected" }
    var remaining: String { "\(progress.remaining) remaining" }

    var source: String {
        if progress.settlements == 1 && progress.cities == 0 { return "Settlement harvest" }
        if progress.cities == 1 && progress.settlements == 0 { return "City harvest" }
        var buildings: [String] = []
        if progress.settlements > 0 {
            buildings.append("\(progress.settlements) \(progress.settlements == 1 ? "settlement" : "settlements")")
        }
        if progress.cities > 0 { buildings.append("\(progress.cities) \(progress.cities == 1 ? "city" : "cities")") }
        return buildings.joined(separator: " + ")
    }
}

/// A durable production obligation with an ephemeral selection. Confirming
/// credits exactly one stocked card through the normal checkpoint transaction.
struct NavalResourceChoiceView: View {
    let viewModel: GameViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: Resource?
    @State private var errorMessage: String?
    @AccessibilityFocusState private var isHeadingFocused: Bool

    private var available: [Resource] {
        RulesEngine.legalMoves(for: viewModel.state, seat: viewModel.humanPlayer).compactMap {
            if case .chooseResource(let resource) = $0 { resource } else { nil }
        }
    }

    private var harvest: NavalHarvestPresentation? {
        Naval.harvestProgress(for: viewModel.humanPlayer, in: viewModel.state).map {
            NavalHarvestPresentation(progress: $0)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            PopupCard(onDismiss: {}, content: {
                VStack(spacing: 12) {
                    if let harvest { header(harvest) }
                    ScrollView {
                        VStack(spacing: 14) {
                            resources
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.72))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if viewModel.persistenceErrorMessage != nil {
                                GoldRowButton(title: "Reload saved game", systemImage: "arrow.clockwise") {
                                    if viewModel.retryPersistence() {
                                        selected = nil
                                        errorMessage = nil
                                    } else {
                                        errorMessage = viewModel.persistenceErrorMessage
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("naval.resource.scroll")
                    GoldRowButton(title: dynamicTypeSize.isAccessibilitySize ? "Collect" : "Collect resource",
                                  systemImage: "checkmark",
                                  isEnabled: selected != nil, action: collect)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Collect selected resource")
                        .accessibilityIdentifier("naval.resource.confirm")
                }
                .padding(18)
                .frame(maxWidth: 340)
                .frame(height: dynamicTypeSize.isAccessibilitySize
                    ? max(280, geometry.size.height - 32) : min(540, max(280, geometry.size.height - 32)))
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
            })
        }
        .onAppear { isHeadingFocused = true }
        .onChange(of: viewModel.state) { _, _ in selected = nil }
        .onChange(of: harvest?.progress.remaining) { _, _ in isHeadingFocused = true }
    }

    private func header(_ harvest: NavalHarvestPresentation) -> some View {
        VStack(spacing: 7) {
            Text(harvest.source)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("naval.resource.source")
            Text(harvest.title)
                .font(.system(.title2, design: .serif).bold())
                .foregroundStyle(CatanTheme.cityPennantGold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Island harvest. \(harvest.title).")
                .accessibilityIdentifier("naval.resource.choice")
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isHeadingFocused)
            harvestProgress(harvest)
        }
        .multilineTextAlignment(.center)
        // Bounded title/progress preserve a usable scrolling choice region on
        // a small phone at maximum text size; the resource rows remain scalable.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func harvestProgress(_ harvest: NavalHarvestPresentation) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(harvest.progress.collected), total: Double(harvest.progress.total))
                .tint(CatanTheme.cityPennantGold)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                Text(harvest.collected)
                    .accessibilityIdentifier("naval.resource.progress.collected")
                Spacer(minLength: 0)
                Text(harvest.remaining).bold()
                    .accessibilityIdentifier("naval.resource.progress.remaining")
            }
            .font(.caption)
            .foregroundStyle(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Harvest progress")
            .accessibilityValue("\(harvest.collected). \(harvest.remaining).")
            .accessibilityAddTraits(.isStaticText)
            .accessibilityRespondsToUserInteraction(false)
            .accessibilityIdentifier("naval.resource.progress")
        }
    }

    private var resources: some View {
        VStack(spacing: 7) {
            ForEach(Resource.allCases, id: \.self) { resource in
                GoldRowButton(
                    title: resource.rawValue.capitalized,
                    subtitle: "You have \(owned(resource)) · Bank \(viewModel.state.bank[resource, default: 0])",
                    systemImage: selected == resource ? "checkmark.circle.fill" : "circle",
                    iconColor: selected == resource ? CatanTheme.cityPennantGold : CatanTheme.color(for: resource),
                    isEnabled: available.contains(resource),
                    fill: selected == resource
                        ? .tintedTexture(SettingsChrome.selectedOptionFill) : .color(Color(white: 0.18)),
                    action: { selected = resource; errorMessage = nil }
                )
                .buttonStyle(.plain)
                .accessibilityIdentifier("naval.resource.\(resource.rawValue)")
                .accessibilityValue(String(owned(resource)))
                .accessibilityAddTraits(selected == resource ? .isSelected : [])
            }
        }
    }

    private func owned(_ resource: Resource) -> Int {
        viewModel.state.players[viewModel.humanPlayer.index].resources[resource, default: 0]
    }

    private func collect() {
        guard let selected else { return }
        do { try viewModel.apply(.chooseResource(selected)) } catch {
            errorMessage = error.localizedDescription
        }
    }
}
