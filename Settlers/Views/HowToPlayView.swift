import CatanEngine
import SwiftUI

/// How to Play, opened from the main menu's top-right corner (Jake, 2026-09-28).
///
/// Three tabs, in the order a new player needs them:
/// - **Walkthrough** - ten cards to click through, each one picture and one
///   sentence, that get a player from "what is this" to "I can play a turn".
/// - **Rules** - one plain statement per topic, with the fine print behind a
///   Details disclosure, so the screen reads in a minute and still answers
///   "wait, can I do that?" mid-game.
/// - **Modes** - Classic first and marked as the main game, then Vast and the
///   Conquest rule, which only change a few numbers and add one mechanic.
///
/// All copy lives in `HowToPlayContent`; this file only draws it.
struct HowToPlayView: View {
    enum Tab: String, CaseIterable {
        case walkthrough, rules, modes

        var title: String { rawValue.capitalized }
    }

    let onDismiss: () -> Void
    let context: HowToPlayContent.Context?

    init(context: HowToPlayContent.Context? = nil, initialTab: Tab = .walkthrough,
         onDismiss: @escaping () -> Void) {
        self.context = context
        self.onDismiss = onDismiss
        _tab = State(initialValue: initialTab)
    }

    @State private var tab: Tab = .walkthrough
    @State private var step = 0
    @State private var expanded: Set<String> = []

    var body: some View {
        ZStack {
            PaintedScreenBackground()
            VStack(spacing: 14) {
                header
                PaintedChoiceRow(
                    options: Tab.allCases,
                    title: \.title,
                    selection: tab,
                    isCompact: true,
                    optionIdentifier: { AccessibilityID.HowToPlay.tab($0.rawValue) },
                    onSelect: { tab = $0 }
                )
                // The row's dividers and chrome are greedy; without this it
                // splits the screen's height with the content below it.
                .fixedSize(horizontal: false, vertical: true)
                switch tab {
                case .walkthrough: walkthrough
                case .rules: sectionList(HowToPlayContent.rules(for: context))
                case .modes: sectionList(HowToPlayContent.modes(for: context))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.howToPlay)
        .foregroundStyle(.white)
        .fontDesign(.serif)
    }

    private var header: some View {
        ZStack {
            Text("How to Play")
                .font(.system(size: 26, weight: .bold, design: .serif))
            HStack {
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityIdentifier(AccessibilityID.HowToPlay.close)
                .accessibilityLabel("Close How to Play")
            }
        }
    }

    // MARK: - Walkthrough

    private var walkthrough: some View {
        let steps = HowToPlayContent.steps(for: context)
        return VStack(spacing: 14) {
            TabView(selection: $step) {
                ForEach(steps) { item in
                    stepCard(item).tag(item.id)
                }
            }
            // No page dots: each card already says "Step n of 10", and the
            // system dots draw over the card's last line of text.
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 12) {
                walkthroughButton("Back", systemImage: "chevron.left", id: AccessibilityID.HowToPlay.back) {
                    step -= 1
                }
                .opacity(step == 0 ? 0 : 1)
                .disabled(step == 0)
                if step == steps.count - 1 {
                    walkthroughButton("See the Rules", systemImage: "book.fill", id: AccessibilityID.HowToPlay.next) {
                        tab = .rules
                    }
                } else {
                    walkthroughButton("Next", systemImage: "chevron.right", id: AccessibilityID.HowToPlay.next) {
                        step += 1
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: step)
            .padding(.bottom, 20)
        }
    }

    private func stepCard(_ item: HowToPlayContent.Step) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Text("Step \(item.id + 1) of \(HowToPlayContent.steps.count)")
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(SettingsChrome.ornamentGold)
            HowToPlayIllustration(kind: item.illustration)
                .frame(height: 150)
            Text(item.title)
                .font(.system(size: 24, weight: .bold, design: .serif))
            Text(item.line)
                .font(.system(size: 17, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            if let cost = item.cost {
                CostRow(cost: cost)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.6))
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.HowToPlay.step(item.id))
    }

    private func walkthroughButton(_ title: String, systemImage: String, id: String,
                                   action: @escaping () -> Void) -> some View {
        GoldRowButton(title: title, systemImage: systemImage, iconColor: SettingsChrome.ornamentGold, action: action)
            .accessibilityIdentifier(id)
    }

    // MARK: - Rules and Modes

    private func sectionList(_ sections: [HowToPlayContent.Section]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                guideIntroduction
                ForEach(sections) { sectionCard($0) }
            }
            .padding(.bottom, 24)
        }
    }

    private var guideIntroduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let context {
                Text(context.title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(SettingsChrome.ornamentGold)
                    .accessibilityIdentifier("how-to-play.match-context")
            }
            Text(HowToPlayContent.introduction)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func sectionCard(_ section: HowToPlayContent.Section) -> some View {
        let isOpen = expanded.contains(section.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(SettingsChrome.ornamentGold)
                    .frame(width: 26)
                Text(section.title)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                if section.id == "classic" {
                    Text("MAIN GAME")
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        // The selected option's painted gold (`PaintedChoiceRow`).
                        .background(PaintedChromeBackground(
                            fill: .tintedTexture(SettingsChrome.selectedOptionFill), cornerRadius: 6, notchScale: 0.4))
                }
                Spacer()
            }
            Text(section.summary)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            detailsToggle(section, isOpen: isOpen)
            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.resourceLosses) { loss in
                        resourceLossRow(loss)
                    }
                    ForEach(section.details, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(SettingsChrome.ornamentGold)
                            Text(line)
                                .font(.system(size: 14, design: .serif))
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if section.showsRollOdds {
                        RollOddsChart()
                            .padding(.top, 6)
                            .accessibilityIdentifier(AccessibilityID.HowToPlay.rollOdds)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.HowToPlay.detailsBody(section.id))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.6))
    }

    /// Three distinct scopes, set as rows rather than squeezed into columns
    /// that would truncate explanations on a small phone or at large text sizes.
    private func resourceLossRow(_ loss: HowToPlayContent.ResourceLoss) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: loss.icon)
                .font(.system(size: 20))
                .foregroundStyle(SettingsChrome.ornamentGold)
                .frame(width: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(loss.title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                Text(loss.amount)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(SettingsChrome.ornamentGold)
                Text(loss.explanation)
                    .foregroundStyle(.white.opacity(0.9))
                Text(loss.example)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 14, design: .serif))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("how-to-play.resource-loss.\(loss.id)")
    }

    private func detailsToggle(_ section: HowToPlayContent.Section, isOpen: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isOpen { expanded.remove(section.id) } else { expanded.insert(section.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(isOpen ? "Hide details" : "Details")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .font(.system(size: 13, weight: .semibold, design: .serif))
            .foregroundStyle(SettingsChrome.ornamentGold)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.HowToPlay.details(section.id))
    }
}

/// A price as the Build popup shows it: each resource's swatch and a count
/// in that resource's color.
private struct CostRow: View {
    let cost: [Resource: Int]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Resource.allCases.filter { cost[$0, default: 0] > 0 }, id: \.self) { resource in
                HStack(spacing: 5) {
                    ResourceSwatch(resource: resource, size: 22)
                    Text("\(cost[resource, default: 0])")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(CatanTheme.color(for: resource))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(cost[resource, default: 0]) \(resource.rawValue.capitalized)")
            }
        }
    }
}
