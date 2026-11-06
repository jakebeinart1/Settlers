import CatanEngine
import SwiftUI

/// One home for people, their AI records, and the existing ghost ladder. The
/// overview has a finite table; charts and past games are navigated to, never
/// appended below the last visible player.
struct LeaderboardView: View {
    let onDismiss: () -> Void
    var statsStore = SeatStatsStore.shared
    var players = PlayerDirectory.shared
    var liveSync = LiveSync.shared

    @State private var snapshot = PlayerRatingSnapshot.empty
    @State private var pool: RatingPool
    @State private var destination: RatingDestination
    @State private var followsOwnProfile: Bool
    @State private var scope = LeaderboardScope.players
    @State private var overlay: RatingOverlay?
    @State private var sheet: RatingSheet?
    @State private var syncStatus: LiveSync.Status? = LiveSync.shared == nil ? nil : .never
    @State private var refreshToken = 0
    @State private var ghostRefreshToken = 0
    @State private var selectedGhostRowKey: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(initialSelection: RatingPageSelection? = nil, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _pool = State(initialValue: initialSelection?.pool ?? RatingPoolPreference.load())
        _destination = State(initialValue: initialSelection.map { .profile($0.playerID) } ?? .standings)
        // A result link belongs to that match's owner, even if this device
        // subsequently changes accounts. Only opening your own row follows me.
        _followsOwnProfile = State(initialValue: false)
    }

    var body: some View {
        ZStack {
            PaintedScreenBackground()
            VStack(spacing: 12) {
                header
                if destination == .standings {
                    scopeControl
                    if scope == .players { overview } else {
                        GhostLeaderboardView(refreshToken: ghostRefreshToken, selectedRowKey: $selectedGhostRowKey,
                                             onPersonRatings: openPlayer)
                    }
                    accountButton
                } else {
                    contextControls
                    detail
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(RatingViewportMarker(identifier: "leaderboard.content-frame"))
            .accessibilityHidden(overlay != nil)
            if let overlay { picker(overlay) }
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.leaderboard)
        .task(id: refreshToken) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToken += 1 }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .help: PlayerRatingHelpView(onClose: { self.sheet = nil })
            case .account:
                LeaderboardAccountView(status: syncStatus, onRefresh: refreshNow, onJoined: { status in
                    syncStatus = status
                    refreshToken += 1
                }, onClose: { self.sheet = nil })
            }
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            if destination != .standings {
                Button(action: goBack) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)) }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("ratings.back")
            }
            Text(title).font(.system(.title2, design: .serif, weight: .bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("leaderboard.title")
            Button { sheet = .help } label: { Image(systemName: "info.circle").font(.system(size: 22)) }
                .frame(width: 44, height: 44)
                .accessibilityLabel("About ratings")
                .accessibilityIdentifier("ratings.help")
            Button(action: onDismiss) { Image(systemName: "xmark.circle.fill").font(.system(size: 22)) }
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 44, height: 44)
                .accessibilityLabel("Close leaderboard")
                .accessibilityIdentifier(AccessibilityID.Leaderboard.close)
        }
    }

    private var title: String {
        switch destination {
        case .standings: return "Leaderboard"
        case .profile(let id): return snapshot.me.isEmpty ? "Player record" : snapshot.name(for: id)
        case .games: return "Games"
        case .trend: return "Rating history"
        }
    }

    private var scopeControl: some View {
        PaintedChoiceRow(options: LeaderboardScope.allCases, title: \.rawValue, selection: scope,
                         minimumHeight: 44, optionIdentifier: { "leaderboard.scope.\($0.id)" },
                         onSelect: { scope = $0 })
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(height: 44)
    }

    private var overview: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 12) {
            contextControls
            if snapshot.me.isEmpty { loading("Loading standings…") } else {
                overallRecord
                PlayerRatingStandingsView(snapshot: snapshot, pool: pool, onPlayer: openPlayer)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
    }

    private var contextControls: some View {
        HStack(spacing: 10) {
            contextButton(modeTitle, identifier: "ratings.mode") { overlay = .mode }
                .accessibilityValue(pool.displayName)
            contextButton("\(pool.difficulty.displayName) AI", identifier: "ratings.tier") { overlay = .tier }
        }
    }

    private var modeTitle: String {
        pool.mode == .classic && pool.variant == .conquest ? "Conquest" : pool.displayName
    }

    private func contextButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(.subheadline, design: .serif, weight: .semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var overallRecord: some View {
        let record = snapshot.ratings.overallRecord(for: snapshot.me)
        return ViewThatFits(in: .horizontal) {
            Text("Your overall record · \(record.wins)W · \(record.losses)L")
                .fixedSize()
            Text("All modes · \(record.wins)W · \(record.losses)L")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.subheadline, design: .serif))
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your overall record, \(RatingPresentation.record(wins: record.wins, losses: record.losses))")
        .accessibilityIdentifier("ratings.overall")
    }

    @ViewBuilder private var detail: some View {
        if snapshot.me.isEmpty { loading("Loading record…") } else {
            switch destination {
            case .standings: EmptyView()
            case .profile(let id):
                PlayerRatingsView(snapshot: snapshot, playerID: id, pool: pool,
                                  onGames: { destination = .games(id) }, onTrend: { destination = .trend(id) })
            case .games(let id):
                recordContext(id)
                PlayerRatingGamesView(changes: changes(for: id))
            case .trend(let id):
                recordContext(id)
                ScrollView { PlayerRatingChart(changes: changes(for: id)).padding(14) }
                    .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 12))
                    .background(RatingViewportMarker(identifier: "ratings.trend-frame"))
            }
        }
    }

    private func loading(_ title: String) -> some View {
        ProgressView(title).tint(SettingsChrome.ornamentGold)
            .font(.system(.subheadline, design: .serif))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recordContext(_ id: String) -> some View {
        Text("\(snapshot.name(for: id)) · \(pool.displayName) · \(pool.difficulty.displayName) AI")
            .font(.system(.subheadline, design: .serif)).foregroundStyle(.white.opacity(0.75))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("ratings.record-context")
    }

    private var accountButton: some View {
        Button { sheet = .account } label: {
            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle").font(.system(size: 17))
                Text(accountTitle).font(.system(.caption, design: .serif))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leaderboard.account")
    }

    private var accountTitle: String {
        switch syncStatus {
        case nil: return "Saved on this device"
        case .never: return "Connecting records…"
        case .online(let date): return "Records synced · \(date.formatted(date: .omitted, time: .shortened))"
        case .offline: return "Offline · saved records"
        case .failed: return "Sync unavailable · saved records"
        case .noName, .nameTaken: return "Choose your leaderboard name"
        case .noAccount: return "Set up iCloud sync"
        }
    }

    @ViewBuilder private func picker(_ picker: RatingOverlay) -> some View {
        switch picker {
        case .mode:
            PlayerRatingModePicker(options: snapshot.ratings.pools.filter { $0.difficulty == pool.difficulty },
                                   selection: pool, onSelect: select, onCancel: { overlay = nil })
        case .tier:
            PlayerRatingTierPicker(selection: pool.difficulty, onSelect: { difficulty in
                select(RatingPool(mode: pool.mode, variant: pool.variant, difficulty: difficulty))
            }, onCancel: { overlay = nil })
        }
    }

    private func select(_ selection: RatingPool) {
        pool = selection
        overlay = nil
        RatingPoolPreference.save(selection)
    }

    private func openPlayer(_ id: String) {
        followsOwnProfile = id == snapshot.me
        destination = .profile(id)
    }

    private func goBack() {
        switch destination {
        case .games(let id), .trend(let id): destination = .profile(id)
        case .profile, .standings: destination = .standings
        }
    }

    private func changes(for id: String) -> [PlayerRatingChange] {
        snapshot.ratings.changes.filter { $0.playerID == id && $0.pool == pool }
    }

    private func refresh() async {
        #if DEBUG
        if QALaunchFlag.seedLeaderboard.isSet {
            GhostLeaderboardView.seedForQA(ratings: .shared, stats: statsStore, players: players)
        }
        #endif
        while !Task.isCancelled {
            await readSnapshot()
            guard !Task.isCancelled else { return }
            if let liveSync {
                let status = await liveSync.refreshIfDue()
                guard !Task.isCancelled else { return }
                syncStatus = status
                await readSnapshot()
            }
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }

    private func refreshNow() async -> LiveSync.Status? {
        if let liveSync {
            let status = await liveSync.sync()
            guard !Task.isCancelled else { return syncStatus }
            syncStatus = status
        }
        await readSnapshot()
        return syncStatus
    }

    private func readSnapshot() async {
        let updated = await PlayerRatingSnapshot.load(stats: statsStore, players: players)
        guard !Task.isCancelled else { return }
        snapshot = updated
        if followsOwnProfile { destination = destination.replacingPlayer(with: updated.me) } else if let id = destination.playerID {
            destination = destination.replacingPlayer(with: updated.resolvedPlayerID(id))
        }
        ghostRefreshToken += 1
    }
}

private enum LeaderboardScope: String, CaseIterable {
    case players = "Players"
    case ghosts = "Ghosts"
    var id: String { self == .players ? "players" : "ghosts" }
}

private enum RatingDestination: Equatable {
    case standings, profile(String), games(String), trend(String)

    var playerID: String? {
        switch self {
        case .standings: return nil
        case .profile(let id), .games(let id), .trend(let id): return id
        }
    }

    func replacingPlayer(with id: String) -> Self {
        switch self {
        case .standings: return .standings
        case .profile: return .profile(id)
        case .games: return .games(id)
        case .trend: return .trend(id)
        }
    }
}

private enum RatingOverlay { case mode, tier }
private enum RatingSheet: String, Identifiable {
    case help, account
    var id: String { rawValue }
}

/// The painted board scene behind a scrim, shared by the app's records pages.
struct PaintedScreenBackground: View {
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ThemedBackgroundImage().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
            LinearGradient(colors: [.black.opacity(0.62), .black.opacity(0.4), .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
