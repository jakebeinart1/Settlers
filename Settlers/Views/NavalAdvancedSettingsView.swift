import SwiftUI
import CatanEngine

/// This one aligned row replaces the expanded island families and toggles
/// that pushed ordinary match settings beneath the pinned Start bar.
struct NavalAdvancedSettingsButton: View {
    let options: NavalOptions
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let minimumHeight: CGFloat = 46

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                summaryLabel
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.NewGame.navalSettings)
        .accessibilityLabel("Advanced Settings")
        .accessibilityValue(summary)
    }

    private var summaryLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Advanced Settings")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 20 : SeatCardView.bodyTextSize,
                              weight: .semibold, design: .serif))
            Text(summary)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 14 : 10, design: .serif))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.75)
        }
    }

    private var summary: String {
        "\(options.mapFamily?.displayName ?? "Surprise me") · Mist \(options.fogEnabled ? "on" : "off")"
            + " · Resources \(options.resourceChoiceEnabled ? "on" : "off")"
    }
}

/// A separate match-configuration surface keeps the ordinary New Game rows
/// visible. Edits bind to the same draft setup; Done returns without starting
/// a match, and the choices become fixed only when New Game's Start is pressed.
struct NavalAdvancedSettingsView: View {
    @Binding var options: NavalOptions
    let onDone: () -> Void
    @State private var isShowingIslandHelp = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let inset: CGFloat = 20
    private static let choiceHeight: CGFloat = 46

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                title
                ScrollView {
                    VStack(spacing: 20) {
                        islandsSection
                        discoverySection
                        shipRulesSection
                    }
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("new-game.naval.advanced.content")
                doneBar
            }
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.naval-settings")
    }

    private var background: some View {
        GeometryReader { geometry in
            ThemedBackgroundImage()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(SettingsChrome.screenBackground.opacity(0.82))
        }
        .ignoresSafeArea()
    }

    private var title: some View {
        Text("Naval Settings")
            .font(.system(size: 29, weight: .bold, design: .serif))
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Self.inset)
            .padding(.top, 16)
            .padding(.bottom, 20)
    }

    private var islandsSection: some View {
        VStack(spacing: 10) {
            islandsHeading
            familyRow([nil, .archipelago])
            familyRow([.peninsula, .twinIslands])
            MatchSettingHelpView(entries: visibleFamilyHelp,
                                 identifier: "new-game.naval.advanced.island-help")
        }
    }

    private var islandsHeading: some View {
        HStack(spacing: 12) {
            SettingsSectionHeader(title: "Islands", titleColor: .white)
            Button { isShowingIslandHelp.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(CatanTheme.cityPennantGold)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About Islands")
            .accessibilityValue(isShowingIslandHelp ? "Expanded" : "Collapsed")
        }
    }

    private var visibleFamilyHelp: [MatchSettingHelpEntry] {
        let entries = MatchSettingHelpEntry.board(naval: true)
        return isShowingIslandHelp ? entries : entries.filter {
            $0.title == (options.mapFamily?.displayName ?? "Surprise me")
        }
    }

    private func familyRow(_ families: [NavalMapFamily?]) -> some View {
        PaintedChoiceRow(options: families, title: { $0?.displayName ?? "Surprise me" },
            selection: options.mapFamily, isCompact: true, minimumHeight: Self.choiceHeight,
            fontSize: dynamicTypeSize.isAccessibilitySize ? 20 : 15,
            optionIdentifier: { "new-game.naval.family.\($0?.rawValue ?? "surprise")" },
            onSelect: { options.mapFamily = $0 })
    }

    private var discoverySection: some View {
        VStack(spacing: 10) {
            SettingsSectionHeader(title: "Discovery & Resources", titleColor: .white)
            NavalSetupOptionsView(options: $options)
        }
    }

    private var doneBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(SettingsChrome.ornamentGold.opacity(0.4)).frame(height: 1)
            UniformActionButton(title: "Done", systemImage: "checkmark", isEnabled: true,
                                backgroundImageName: "button-fill-turn", action: onDone)
                .accessibilityIdentifier(AccessibilityID.NewGame.navalSettingsDone)
                .frame(height: 54)
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 12)
        }
        .background(SettingsChrome.screenBackground.opacity(0.95))
        .dynamicTypeSize(.large)
    }

    private var shipRulesSection: some View {
        VStack(spacing: 10) {
            SettingsSectionHeader(title: "Ship Rules", titleColor: .white)
            NavalShipStealingOptionView(options: $options)
        }
    }
}
