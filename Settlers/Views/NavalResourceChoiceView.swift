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
    // Display rounding must leave the realized quantity target above 44 points.
    private static let quantityControlSize: CGFloat = 48
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
                            if let errorMessage = viewModel.navalHarvestErrorMessage {
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
                                  subtitleColor: .white,
                                  isEnabled: viewModel.canSubmitNavalHarvest,
                                  fill: viewModel.canSubmitNavalHarvest
                                    ? .tintedTexture(SettingsChrome.selectedOptionFill) : .color(Color(white: 0.18)),
                                  action: collect)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .fixedSize(horizontal: false, vertical: true)
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
                .font(dynamicTypeSize.isAccessibilitySize ? .caption.bold() : .subheadline.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("naval.resource.source")
            Text("Choose \(requiredCount) \(requiredCount == 1 ? "resource" : "resources")")
                .font(.system(dynamicTypeSize.isAccessibilitySize ? .headline : .title2, design: .serif).bold())
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
                Text(remainingCount == 0
                    ? (dynamicTypeSize.isAccessibilitySize ? "Ready" : "Ready to collect") : "\(remainingCount) remaining").bold()
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
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    resourceLabelButton(resource, picked: picked, canAdd: canAdd)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        quantityControls(resource, picked: picked, canAdd: canAdd)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    resourceLabelButton(resource, picked: picked, canAdd: canAdd)
                    quantityControls(resource, picked: picked, canAdd: canAdd)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(PaintedChromeBackground(fill: picked > 0
            ? .tintedTexture(SettingsChrome.selectedOptionFill) : .color(Color(white: 0.18)), cornerRadius: 10))
    }

    /// The label and quantity controls are sibling buttons. A row-wide gesture
    /// would also add a resource when its minus button is tapped.
    private func resourceLabelButton(_ resource: Resource, picked: Int, canAdd: Bool) -> some View {
        Button { viewModel.selectForNavalHarvest(resource) } label: {
            HStack(spacing: 8) {
                Image(systemName: picked > 0 ? "checkmark.circle.fill" : "circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(picked > 0 ? CatanTheme.cityPennantGold : CatanTheme.color(for: resource))
                    .accessibilityHidden(true)
                resourceLabel(resource, picked: picked)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: Self.quantityControlSize, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HarvestLabelButtonStyle())
        .disabled(!canAdd)
        .accessibilityIdentifier("naval.resource.\(resource.rawValue)")
        .accessibilityLabel("Add \(resource.rawValue.capitalized)")
        .accessibilityValue(selectionValue(resource, picked: picked))
        .accessibilityHint(addHint(resource, canAdd: canAdd))
        .accessibilityAddTraits(picked > 0 ? .isSelected : [])
    }

    private func resourceLabel(_ resource: Resource, picked: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(resource.rawValue.capitalized)
                .font(.subheadline.bold()).foregroundStyle(.white)
                .accessibilityIdentifier("naval.resource.title.\(resource.rawValue)")
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text("You have \(owned(resource))")
                    Text("Bank \(viewModel.state.bank[resource, default: 0])")
                } else {
                    Text("You have \(owned(resource)) · Bank \(viewModel.state.bank[resource, default: 0])")
                }
            }
            .font(.caption2).foregroundStyle(picked > 0 ? .white : .white.opacity(0.85))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func quantityControls(_ resource: Resource, picked: Int, canAdd: Bool) -> some View {
        HStack(spacing: 0) {
            Text("\(picked)")
                .font(.subheadline.bold()).monospacedDigit()
                .foregroundStyle(.white)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .frame(minWidth: 18)
                .accessibilityLabel("\(resource.rawValue.capitalized) selected")
                .accessibilityValue("\(picked)")
                .accessibilityIdentifier("naval.resource.quantity.\(resource.rawValue)")
            addResourceButton(resource, picked: picked, canAdd: canAdd)
            removeResourceButton(resource, picked: picked)
        }
    }

    private func addResourceButton(_ resource: Resource, picked: Int, canAdd: Bool) -> some View {
        Button { viewModel.selectForNavalHarvest(resource) } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .frame(width: Self.quantityControlSize, height: Self.quantityControlSize)
                .foregroundStyle(canAdd ? CatanTheme.cityPennantGold : .white.opacity(0.35))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .accessibilityIdentifier("naval.resource.add.\(resource.rawValue)")
        .accessibilityLabel("Add one \(resource.rawValue.capitalized)")
        .accessibilityValue(selectionValue(resource, picked: picked))
        .accessibilityHint(addHint(resource, canAdd: canAdd))
    }

    private func removeResourceButton(_ resource: Resource, picked: Int) -> some View {
        Button { viewModel.deselectFromNavalHarvest(resource) } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 24))
                .frame(width: Self.quantityControlSize, height: Self.quantityControlSize)
                .foregroundStyle(picked > 0 ? CatanTheme.cityPennantGold : .white.opacity(0.35))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(picked == 0)
        .accessibilityLabel("Remove one \(resource.rawValue.capitalized)")
        .accessibilityValue("\(picked) selected")
        .accessibilityIdentifier("naval.resource.remove.\(resource.rawValue)")
    }

    private func selectionValue(_ resource: Resource, picked: Int) -> String {
        "\(picked) selected. You have \(owned(resource)). Bank \(viewModel.state.bank[resource, default: 0])."
    }

    private func addHint(_ resource: Resource, canAdd: Bool) -> String {
        if canAdd { return "Select one card. You may choose the same resource more than once." }
        if remainingCount == 0 { return "All resources selected. Remove one to change your choice." }
        return "No more \(resource.rawValue.capitalized) is available in the bank."
    }

    /// Disabled additions must not fade the selected name or stock information.
    private struct HarvestLabelButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.9 : 1)
        }
    }

    private func owned(_ resource: Resource) -> Int {
        viewModel.state.players[viewModel.humanPlayer.index].resources[resource, default: 0]
    }

    private func collect() {
        _ = viewModel.submitNavalHarvest()
    }
}
