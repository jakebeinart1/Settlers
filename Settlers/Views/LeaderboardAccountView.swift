import SwiftUI

/// Account and sync details are a deliberate drill-in. Long offline guidance
/// or a name-entry form must never consume the leaderboard's standings space.
struct LeaderboardAccountView: View {
    let status: LiveSync.Status?
    let onRefresh: @MainActor () async -> LiveSync.Status?
    /// Reports a completed name claim. Refresh already updates the host.
    let onJoined: (LiveSync.Status?) -> Void
    let onClose: () -> Void

    @State private var displayedStatus: LiveSync.Status?
    @State private var isEditingName = false
    @State private var isRefreshing = false
    @State private var refreshTask: Task<Void, Never>?

    init(status: LiveSync.Status?, onRefresh: @escaping @MainActor () async -> LiveSync.Status?,
         onJoined: @escaping (LiveSync.Status?) -> Void, onClose: @escaping () -> Void) {
        self.status = status
        self.onRefresh = onRefresh
        self.onJoined = onJoined
        self.onClose = onClose
        _displayedStatus = State(initialValue: status)
    }

    var body: some View {
        ZStack {
            PaintedScreenBackground()
            VStack(spacing: 14) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        statusDetails
                        accountActions
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(20)
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .onChange(of: status) { _, next in displayedStatus = next }
        .onDisappear(perform: cancelRefresh)
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Record sync")
                .font(.system(.title2, design: .serif, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 22))
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("Close record sync")
            .accessibilityIdentifier("leaderboard.account-close")
        }
    }

    private var statusDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Record status")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(SettingsChrome.ornamentGold)
            Text(RatingPresentation.syncDescription(displayedStatus))
                .font(.system(.body, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.Leaderboard.syncStatus)
            Text(accountExplanation)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountExplanation: String {
        guard displayedStatus != nil else {
            return "This build is not connected to the online leaderboard. "
                + "Its records remain available on this device; they are not syncing to other devices."
        }
        return "Your iCloud account identifies you across devices. "
            + "Changing your leaderboard name keeps your games and ratings. "
            + "Saved results remain on this device when a connection is unavailable."
    }

    @ViewBuilder private var accountActions: some View {
        if let displayedStatus {
            nameControls(displayedStatus)
            GoldRowButton(title: isRefreshing ? "Refreshing…" : "Refresh records", systemImage: "arrow.clockwise",
                          iconColor: SettingsChrome.ornamentGold, action: beginRefresh)
                .frame(minHeight: 44)
                .disabled(isRefreshing)
                .accessibilityIdentifier("leaderboard.account-refresh")
        }
    }

    @ViewBuilder private func nameControls(_ status: LiveSync.Status) -> some View {
        if needsName(status) || isEditingName {
            VStack(alignment: .leading, spacing: 10) {
                Text("Leaderboard name").font(.system(.headline, design: .serif))
                LadderNameEntry(onJoined: didJoin)
            }
        } else {
            switch status {
            case .online, .partiallySynced:
                GoldRowButton(title: "Change name", systemImage: "pencil",
                              iconColor: SettingsChrome.ornamentGold, action: { isEditingName = true })
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(AccessibilityID.Leaderboard.changeName)
            default: EmptyView()
            }
        }
    }

    private func needsName(_ status: LiveSync.Status) -> Bool {
        switch status {
        case .noName, .nameTaken: return true
        default: return false
        }
    }

    private func didJoin(_ next: LiveSync.Status?) {
        displayedStatus = next
        isEditingName = false
        onJoined(next)
    }

    private func beginRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTask = Task {
            let next = await onRefresh()
            guard !Task.isCancelled else { return }
            displayedStatus = next
            isRefreshing = false
        }
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }
}
