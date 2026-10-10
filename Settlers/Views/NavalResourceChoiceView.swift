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

/// A quantity draft for one complete harvest. Taps select cards, including
/// repeated resources; confirmation credits them in one durable transaction.
struct NavalResourceChoiceView: View {
    let viewModel: GameViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isHeadingFocused: Bool

    private var obligation: GameViewModel.NavalHarvestObligation? { viewModel.currentNavalHarvestObligation }
    private var selectedCount: Int { viewModel.navalHarvestDraft.selectedCount }
    private var requiredCount: Int { obligation?.requiredCount ?? 0 }
    private var remainingCount: Int { max(requiredCount - selectedCount, 0) }
    private var selectionProgress: String { "\(selectedCount) of \(requiredCount) selected" }

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
                            if let errorMessage = viewModel.navalHarvestDraft.errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.72))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if viewModel.persistenceErrorMessage != nil {
                                GoldRowButton(title: "Reload saved game", systemImage: "arrow.clockwise") {
                                    if viewModel.retryPersistence() {
                                        isHeadingFocused = true
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("naval.resource.scroll")
                    GoldRowButton(title: dynamicTypeSize.isAccessibilitySize ? "Collect" : "Collect resources",
                                  subtitle: selectionProgress,
                                  systemImage: "checkmark",
                                  iconColor: viewModel.canSubmitNavalHarvest ? CatanTheme.cityPennantGold : .white.opacity(0.5),
                                  isEnabled: viewModel.canSubmitNavalHarvest,
                                  fill: viewModel.canSubmitNavalHarvest
                                    ? .tintedTexture(SettingsChrome.selectedOptionFill) : .color(Color(white: 0.18)),
                                  action: collect)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Collect resources")
                        .accessibilityValue(selectionProgress)
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
        .onAppear { viewModel.prepareNavalHarvestPresentation(); isHeadingFocused = true }
        .onChange(of: obligation?.context) { _, _ in
            viewModel.prepareNavalHarvestPresentation()
            isHeadingFocused = true
        }
    }

    private func header(_ harvest: NavalHarvestPresentation) -> some View {
        VStack(spacing: 7) {
            Text(harvest.source)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("naval.resource.source")
            Text("Choose \(requiredCount) \(requiredCount == 1 ? "resource" : "resources")")
                .font(.system(.title2, design: .serif).bold())
                .foregroundStyle(CatanTheme.cityPennantGold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Island harvest. Choose \(requiredCount) \(requiredCount == 1 ? "resource" : "resources").")
                .accessibilityIdentifier("naval.resource.choice")
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isHeadingFocused)
            harvestProgress
            if harvest.progress.collected > 0 {
                Text("\(harvest.progress.collected) of \(harvest.progress.total) already collected")
                    .font(.caption).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("naval.resource.previous-collection")
            }
            if harvest.progress.remaining > requiredCount {
                Text("Only \(requiredCount) \(requiredCount == 1 ? "card remains" : "cards remain") in the bank. The rest of this harvest cannot be collected.")
                    .font(.caption).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("naval.resource.bank-shortage")
            }
        }
        .multilineTextAlignment(.center)
        // Bounded title/progress preserve a usable scrolling choice region on
        // a small phone at maximum text size; the resource rows remain scalable.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var harvestProgress: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(selectedCount), total: Double(max(requiredCount, 1)))
                .tint(CatanTheme.cityPennantGold)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                Text(selectionProgress)
                    .accessibilityIdentifier("naval.resource.progress.collected")
                Spacer(minLength: 0)
                Text(remainingCount == 0 ? "Ready to collect" : "\(remainingCount) remaining").bold()
                    .accessibilityIdentifier("naval.resource.progress.remaining")
            }
            .font(.caption)
            .foregroundStyle(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Harvest progress")
            .accessibilityValue("\(selectionProgress). \(remainingCount) remaining.")
            .accessibilityAddTraits(.isStaticText)
            .accessibilityRespondsToUserInteraction(false)
            .accessibilityIdentifier("naval.resource.progress")
        }
    }

    private var resources: some View {
        VStack(spacing: 7) {
            ForEach(Resource.allCases, id: \.self) { resource in
                resourceRow(resource)
            }
        }
    }

    private func resourceRow(_ resource: Resource) -> some View {
        let picked = viewModel.navalHarvestDraft.counts[resource, default: 0]
        let canAdd = obligation.map {
            viewModel.navalHarvestDraft.canAdd(resource, bank: $0.bank, required: $0.requiredCount)
        } ?? false
        return HStack(spacing: 7) {
            GoldRowButton(
                    title: resource.rawValue.capitalized,
                    subtitle: "You have \(owned(resource)) · Bank \(viewModel.state.bank[resource, default: 0])",
                    systemImage: picked > 0 ? "checkmark.circle.fill" : "plus.circle",
                    iconColor: picked > 0 ? CatanTheme.cityPennantGold : CatanTheme.color(for: resource),
                    isEnabled: canAdd,
                    fill: picked > 0
                        ? .tintedTexture(SettingsChrome.selectedOptionFill) : .color(Color(white: 0.18)),
                    trailing: {
                        Text("\(picked)")
                            .font(.subheadline.bold()).monospacedDigit()
                            .foregroundStyle(picked > 0 ? CatanTheme.cityPennantGold : .white.opacity(0.6))
                    },
                    action: { viewModel.selectForNavalHarvest(resource) }
                )
                .buttonStyle(.plain)
                .accessibilityIdentifier("naval.resource.\(resource.rawValue)")
                .accessibilityLabel("Add \(resource.rawValue.capitalized)")
                .accessibilityValue("\(picked) selected. You have \(owned(resource)). Bank \(viewModel.state.bank[resource, default: 0]).")
                .accessibilityHint("Select one card. You may choose the same resource more than once.")
                .accessibilityAddTraits(picked > 0 ? .isSelected : [])
            Button { viewModel.deselectFromNavalHarvest(resource) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 21))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(picked > 0 ? CatanTheme.cityPennantGold : .white.opacity(0.35))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(picked == 0)
            .accessibilityLabel("Remove one \(resource.rawValue.capitalized)")
            .accessibilityIdentifier("naval.resource.remove.\(resource.rawValue)")
        }
    }

    private func owned(_ resource: Resource) -> Int {
        viewModel.state.players[viewModel.humanPlayer.index].resources[resource, default: 0]
    }

    private func collect() {
        _ = viewModel.submitNavalHarvest()
    }
}
