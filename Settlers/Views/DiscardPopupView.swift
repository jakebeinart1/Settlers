import SwiftUI
import CatanEngine

/// Mandatory post-seven discard editor and its inspect-only collapsed dock.
///
/// The draft remains in `GameViewModel`; minimizing, opening Settings, or
/// rebuilding `GameView` after a recoverable write error cannot silently erase
/// it. Only `submitDiscard()` asks the engine to mutate the match.
public struct DiscardPopupView: View {
    public let viewModel: GameViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(viewModel: GameViewModel) {
        self.viewModel = viewModel
    }

    private enum FocusTarget: Hashable {
        case editor, dock, error
    }

    @AccessibilityFocusState private var focusTarget: FocusTarget?

    private var obligation: GameViewModel.DiscardObligation? {
        viewModel.currentDiscardObligation
    }

    private var requiredCount: Int { obligation?.requiredCount ?? 0 }
    private var selectedCount: Int { viewModel.discardDraft.selectedCount }
    private var remainingCount: Int { max(requiredCount - selectedCount, 0) }

    public var body: some View {
        Group {
            if viewModel.isDiscardEditorMinimized {
                minimizedDock
            } else {
                expandedEditor
            }
        }
        .onAppear {
            viewModel.prepareDiscardPresentation()
            focusTarget = viewModel.isDiscardEditorMinimized ? .dock : .editor
        }
        .onChange(of: viewModel.humanPlayer) { _, _ in
            viewModel.prepareDiscardPresentation()
            focusTarget = .editor
        }
    }

    private var expandedEditor: some View {
        GeometryReader { geometry in
            PopupCard(onDismiss: {}, content: {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityEditorContents
                        .padding(12)
                        .frame(maxWidth: 340)
                        .frame(height: max(280, geometry.size.height - 32))
                } else {
                    editorContents
                        .padding(16)
                        .frame(maxWidth: 340)
                        // Keep this after the flexible-width frame. A
                        // vertical max frame accepted PopupCard's full-screen
                        // proposal and painted a mostly empty blue sheet even
                        // though the editor itself was only ~430pt tall.
                        .fixedSize(horizontal: false, vertical: true)
                }
            })
        }
    }

    /// On accessibility text sizes, the two decisions stay pinned while the
    /// descriptive content and card rows scroll between them. A single
    /// scrolling stack put "View Board" above the viewport and the disabled
    /// submit button below it on a 375x667 phone, leaving no usable escape
    /// from a mandatory decision.
    private var accessibilityEditorContents: some View {
        VStack(spacing: 10) {
            viewBoardButton
                .frame(maxWidth: .infinity, alignment: .trailing)

            ScrollView {
                editorFields(showsBoardAction: false)
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.basedOnSize)

            submitButton
        }
    }

    private var editorContents: some View {
        VStack(spacing: 12) {
            editorFields(showsBoardAction: true)
            submitButton
        }
    }

    private func editorFields(showsBoardAction: Bool) -> some View {
        VStack(spacing: 12) {
            if showsBoardAction {
                header
            } else {
                headerMessage
            }
            progress

            resourceSection(title: "SELECTED TO DISCARD") {
                ResourceSlotRow(
                    counts: viewModel.discardDraft.counts,
                    actionHint: "Return one card to your hand"
                ) {
                    viewModel.deselectFromDiscard($0)
                }
            }

            Divider().overlay(Color.white.opacity(0.2))

            resourceSection(title: "YOUR REMAINING HAND") {
                handTray
            }

            if let error = viewModel.discardDraft.errorMessage {
                errorPlaque(error)
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                headerMessage
                Spacer(minLength: 4)
                viewBoardButton
            }
            VStack(alignment: .leading, spacing: 8) {
                headerMessage
                viewBoardButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var headerMessage: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(SettingsChrome.ornamentGold)

            VStack(alignment: .leading, spacing: 2) {
                Text(dynamicTypeSize.isAccessibilitySize ? "Discard" : "Discard Required")
                    .font(.headline)
                    .accessibilityFocused($focusTarget, equals: .editor)
                    .accessibilityIdentifier(AccessibilityID.Discard.editor)
                Text(dynamicTypeSize.isAccessibilitySize
                    ? "Choose \(requiredCount) cards."
                    : "A seven was rolled. Choose exactly \(requiredCount) cards.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var viewBoardButton: some View {
        Button {
            viewModel.setDiscardEditorMinimized(true)
            focusTarget = .dock
        } label: {
            Label(dynamicTypeSize.isAccessibilitySize ? "Board" : "View Board", systemImage: "eye.fill")
                .font(.caption.bold())
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(
                    PaintedChromeBackground(
                        fill: .color(SettingsChrome.plaqueFill),
                        cornerRadius: 9,
                        notchScale: 0.55
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Minimize discard to inspect the board")
        .accessibilityIdentifier(AccessibilityID.Discard.minimize)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedCount) of \(requiredCount) selected")
                    Text(remainingCount == 0 ? "Ready" : "\(remainingCount) remaining")
                        .foregroundStyle(remainingCount == 0 ? .green : SettingsChrome.ornamentGold)
                }
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text("\(selectedCount) of \(requiredCount) selected")
                    Spacer()
                    Text(remainingCount == 0 ? "Ready" : "\(remainingCount) remaining")
                        .foregroundStyle(remainingCount == 0 ? .green : SettingsChrome.ornamentGold)
                }
                .font(.caption.bold())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(SettingsChrome.ornamentGold.gradient)
                        .frame(width: geometry.size.width * progressFraction)
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Discard selection")
        .accessibilityValue("\(selectedCount) of \(requiredCount) cards selected, \(remainingCount) remaining")
        .accessibilityIdentifier(AccessibilityID.Discard.progress)
    }

    private var progressFraction: CGFloat {
        guard requiredCount > 0 else { return 0 }
        return min(CGFloat(selectedCount) / CGFloat(requiredCount), 1)
    }

    private func resourceSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.65))
            content()
                .frame(maxWidth: .infinity)
        }
    }

    private var handTray: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                let owned = obligation?.holding[resource] ?? 0
                let staged = viewModel.discardDraft.counts[resource] ?? 0
                let remaining = owned - staged
                ResourceChip(
                    resource: resource,
                    count: remaining,
                    isEnabled: remaining > 0 && remainingCount > 0
                ) {
                    viewModel.selectForDiscard(resource)
                }
                .accessibilityValue("\(remaining) remaining, \(staged) selected")
                .accessibilityHint(remaining > 0 && remainingCount > 0
                    ? "Select one to discard" : "No card can be selected")
                .accessibilityIdentifier(AccessibilityID.Discard.hand(resource))
            }
        }
    }

    private func errorPlaque(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityFocused($focusTarget, equals: .error)
    }

    private var submitButton: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Button(action: submit) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Submit")
                            .font(.headline.bold())
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        PaintedChromeBackground(
                            fill: .tintedTexture(Color.green.opacity(0.32)),
                            cornerRadius: 10
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(remainingCount != 0)
                .opacity(remainingCount == 0 ? 1 : 0.5)
            } else {
                GoldRowButton(
                    title: "Discard \(requiredCount) Cards",
                    subtitle: remainingCount == 0 ? "Confirm this choice" : "Choose \(remainingCount) more",
                    systemImage: "checkmark.seal.fill",
                    iconColor: .green,
                    isEnabled: remainingCount == 0,
                    fill: .tintedTexture(Color.green.opacity(0.32)),
                    action: submit
                )
            }
        }
        .accessibilityLabel("Discard \(requiredCount) cards")
        .accessibilityValue("\(selectedCount) of \(requiredCount) selected")
        .accessibilityIdentifier(AccessibilityID.Discard.submit)
    }

    private func submit() {
        if !viewModel.submitDiscard() { focusTarget = .error }
    }

    private var minimizedDock: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                viewModel.setDiscardEditorMinimized(false)
                focusTarget = .editor
            } label: {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SettingsChrome.ornamentGold)
                            Text("\(remainingCount) left")
                                .font(.headline.bold())
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up")
                                .foregroundStyle(SettingsChrome.ornamentGold)
                        }
                    } else {
                        HStack(spacing: 12) {
                            dockIcon
                            dockMessage
                            Spacer(minLength: 8)
                            Label("Continue", systemImage: "chevron.up")
                                .foregroundStyle(SettingsChrome.ornamentGold)
                        }
                        .font(.caption.bold())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(minHeight: BottomRowMetrics.height)
                .background(
                    PaintedChromeBackground(
                        fill: .color(SettingsChrome.plaqueFill),
                        cornerRadius: 10,
                        notchScale: 0.6
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard required. Continue selecting")
            .accessibilityValue("\(selectedCount) of \(requiredCount) selected, \(remainingCount) remaining")
            .accessibilityFocused($focusTarget, equals: .dock)
            .accessibilityIdentifier(AccessibilityID.Discard.dock)
            .padding(.horizontal, 12)
        }
    }

    private var dockIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.title3)
            .foregroundStyle(SettingsChrome.ornamentGold)
            .accessibilityHidden(true)
    }

    private var dockMessage: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Discard required")
                .font(.subheadline.bold())
            Text(dockProgressText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var dockProgressText: String {
        "\(selectedCount) of \(requiredCount) selected · \(remainingCount) remaining"
    }
}
