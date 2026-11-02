import CatanEngine
import SwiftUI

/// A person's record against AI, kept separate from ghost ratings. Every
/// number, chart point and result is derived from the same replayed match set.
struct PlayerRatingsView: View {
    let onDismiss: () -> Void
    var statsStore = SeatStatsStore.shared
    var players = PlayerDirectory.shared
    var liveSync = LiveSync.shared

    @State private var playerID: String
    @State private var followsOwnProfile: Bool
    @State private var pool: RatingPool
    @State private var snapshot = PlayerRatingSnapshot.empty
    @State private var syncStatus: LiveSync.Status?
    @State private var isShowingHelp = false
    @State private var isShowingModePicker = false
    @State private var isShowingAllResults = false
    @State private var refreshToken = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(playerID: String, initialPool: RatingPool? = nil, isOwnProfile: Bool? = nil,
         onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _playerID = State(initialValue: playerID)
        _followsOwnProfile = State(initialValue: isOwnProfile ?? (playerID == PlayerDirectory.shared.me))
        _pool = State(initialValue: initialPool ?? RatingPoolPreference.load())
    }

    private var standing: PlayerRatingStanding { snapshot.ratings.standing(for: playerID, in: pool) }
    private var changes: [PlayerRatingChange] {
        snapshot.ratings.changes.filter { $0.playerID == playerID && $0.pool == pool }
    }

    var body: some View {
        ZStack {
            PaintedScreenBackground()
            VStack(spacing: 14) {
                header
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            contextControls.id("ratings.top")
                            ratingPanel
                            overallRecord
                            sharedStandings
                            gameRecord
                            syncNotice
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .refreshable { await refreshNow() }
                    .tint(SettingsChrome.ornamentGold)
                    .onChange(of: playerID) {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            scroll.scrollTo("ratings.top", anchor: .top)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .accessibilityHidden(isShowingModePicker)
            if isShowingModePicker {
                PlayerRatingModePicker(options: modeOptions, selection: pool, onSelect: { option in
                    select(option)
                    isShowingModePicker = false
                }, onCancel: { isShowingModePicker = false })
            }
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.player-ratings")
        .task(id: refreshToken) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToken += 1 }
        }
        .sheet(isPresented: $isShowingHelp) { PlayerRatingHelpView(onClose: { isShowingHelp = false }) }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            titledHeader("Ratings & Record")
            titledHeader("Ratings")
        }
    }

    private func titledHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(.title2, design: .serif, weight: .bold))
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Ratings and record")
            Spacer(minLength: 0)
            headerActions
        }
    }

    private var headerActions: some View {
        HStack(spacing: 4) {
            Button { isShowingHelp = true } label: { Image(systemName: "info.circle").font(.system(size: 22)) }
                .frame(width: 44, height: 44)
                .accessibilityLabel("About ratings")
                .accessibilityIdentifier("ratings.help")
            Button(action: onDismiss) { Image(systemName: "xmark.circle.fill").font(.system(size: 22)) }
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 44, height: 44)
                .accessibilityLabel("Close ratings")
                .accessibilityIdentifier("ratings.close")
        }
    }

    private var contextControls: some View {
        VStack(spacing: 10) {
            Button { isShowingModePicker = true } label: { modeLabel }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ratings.mode")
            PaintedChoiceRow(
                options: BotDifficulty.allCases, title: { "\($0.displayName) AI" }, selection: pool.difficulty,
                minimumHeight: 44, optionIdentifier: { "ratings.difficulty.\($0.rawValue)" },
                onSelect: { difficulty in select(RatingPool(mode: pool.mode, variant: pool.variant, difficulty: difficulty)) }
            )
        }
    }

    private var modeOptions: [RatingPool] {
        snapshot.ratings.pools.filter { $0.difficulty == pool.difficulty }
    }

    private var modeLabel: some View {
        HStack {
            Text(pool.displayName).font(.system(.body, design: .serif, weight: .semibold))
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
    }

    private var ratingPanel: some View {
        VStack(alignment: .leading, spacing: 17) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    playerHeading
                    HStack(alignment: .firstTextBaseline, spacing: 8) { ratingValue; eloLabel }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    playerHeading
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) { ratingValue; eloLabel }
                }
            }
            recordMetrics
            if changes.isEmpty {
                Text("Ratings start at 1000 Elo. No rated games in this mode yet.")
                    .font(.system(.subheadline, design: .serif)).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            } else { PlayerRatingChart(changes: changes) }
        }
        .padding(16)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 12))
    }

    private var playerHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.name(for: playerID)).font(.system(.title2, design: .serif, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Against \(pool.difficulty.displayName) AI")
                .font(.system(dynamicTypeSize.isAccessibilitySize ? .caption : .subheadline, design: .serif))
                .foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ratingValue: some View {
        Text(standing.isRated ? "\(standing.displayedRating)" : "Unrated")
            .font(.system(standing.isRated ? .largeTitle : .title3, design: .serif, weight: .bold))
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(SettingsChrome.ornamentGold)
            .accessibilityIdentifier("ratings.rating")
    }

    private var eloLabel: some View {
        Text("Elo").font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
    }

    @ViewBuilder private var recordMetrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                metricItems
            }
        } else {
            HStack(alignment: .top, spacing: 12) { metricItems }
        }
    }

    @ViewBuilder private var metricItems: some View {
        metric("\(standing.wins)", label: "Wins", identifier: "ratings.wins")
        metric("\(standing.losses)", label: "Losses", identifier: "ratings.losses")
        let rate = standing.games == 0 ? "—" : "\(Int((Double(standing.wins) / Double(standing.games) * 100).rounded()))%"
        metric(rate, label: "Win rate", identifier: "ratings.win-rate")
        metric("\(standing.games)", label: "Games", identifier: "ratings.games")
    }

    private func metric(_ value: String, label: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(.title3, design: .serif, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var overallRecord: some View {
        let record = snapshot.ratings.overallRecord(for: playerID)
        return VStack(alignment: .leading, spacing: 5) {
            Text("All modes against AI").font(.system(.subheadline, design: .serif, weight: .semibold))
            Text(RatingPresentation.record(wins: record.wins, losses: record.losses))
                .font(.system(.body, design: .serif)).foregroundStyle(.white.opacity(0.9))
            Text("Each mode and AI difficulty has its own Elo.")
                .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ratings.overall-record")
    }

    private var sharedStandings: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsSectionHeader(title: "Player standings")
            Text("\(pool.displayName) · \(pool.difficulty.displayName) AI")
                .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
            ForEach(standingsOrder, id: \.self) { id in playerRow(id) }
            Text("\(pool.difficulty.displayName) AI: \(snapshot.ratings.aiStanding(in: pool).displayedRating) Elo. "
                + "Only this mode's games affect these ratings.")
                .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var standingsOrder: [String] {
        snapshot.playerIDs.sorted {
            let first = snapshot.ratings.standing(for: $0, in: pool)
            let second = snapshot.ratings.standing(for: $1, in: pool)
            if first.isRated != second.isRated { return first.isRated }
            if first.rating != second.rating { return first.rating > second.rating }
            return (snapshot.name(for: $0).localizedLowercase, $0) < (snapshot.name(for: $1).localizedLowercase, $1)
        }
    }

    private func playerRow(_ id: String) -> some View {
        let record = snapshot.ratings.standing(for: id, in: pool)
        return Button {
            playerID = id
            followsOwnProfile = id == snapshot.me
            isShowingAllResults = false
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize { expandedPlayerRow(id, record: record) } else {
                    compactPlayerRow(id, record: record)
                }
            }
            .padding(12)
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(id == playerID ? [.isSelected] : [])
        .accessibilityIdentifier("ratings.player.\(id)")
    }

    private func compactPlayerRow(_ id: String, record: PlayerRatingStanding) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                playerName(id)
                playerRecord(record)
            }
            Spacer(minLength: 8)
            Text(record.isRated ? "\(record.displayedRating)" : "Unrated")
                .font(.system(.headline, design: .serif)).foregroundStyle(SettingsChrome.ornamentGold)
            playerIndicator(id)
        }
    }

    private func expandedPlayerRow(_ id: String, record: PlayerRatingStanding) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                playerName(id).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                playerIndicator(id)
            }
            Text(record.isRated ? "\(record.displayedRating) Elo" : "Unrated")
                .font(.system(.headline, design: .serif)).foregroundStyle(SettingsChrome.ornamentGold)
                .lineLimit(1).minimumScaleFactor(0.7)
            playerRecord(record).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playerName(_ id: String) -> some View {
        Text(snapshot.name(for: id) + (id == snapshot.me ? " (you)" : ""))
            .font(.system(.subheadline, design: .serif, weight: .semibold))
    }

    private func playerRecord(_ record: PlayerRatingStanding) -> some View {
        Text(RatingPresentation.record(wins: record.wins, losses: record.losses))
            .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
    }

    private func playerIndicator(_ id: String) -> some View {
        Image(systemName: id == playerID ? "checkmark" : "chevron.right").font(.system(size: 12))
            .frame(width: 12).foregroundStyle(SettingsChrome.ornamentGold).accessibilityHidden(true)
    }

    private var gameRecord: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Game record")
            Text("\(snapshot.name(for: playerID)) · \(pool.displayName) · \(pool.difficulty.displayName) AI")
                .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ratings.record-context")
            if changes.isEmpty {
                Text("No games in this mode yet.").font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                ForEach(Array(changes.reversed().prefix(isShowingAllResults ? changes.count : 8))) { change in
                    PlayerRatingResultRow(change: change)
                }
                if changes.count > 8 && !isShowingAllResults {
                    Button("Show all \(changes.count) games") { isShowingAllResults = true }
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .foregroundStyle(SettingsChrome.ornamentGold).frame(minHeight: 44)
                        .accessibilityIdentifier("ratings.show-all-games")
                }
            }
        }
    }

    private var syncNotice: some View {
        Text(RatingPresentation.syncDescription(syncStatus))
            .font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ratings.sync-status")
    }

    private func select(_ selection: RatingPool) {
        pool = selection
        isShowingAllResults = false
        RatingPoolPreference.save(selection)
    }

    private func refresh() async {
        while !Task.isCancelled {
            await readSnapshot()
            if let liveSync {
                syncStatus = await liveSync.refreshIfDue()
                await readSnapshot()
            }
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }

    /// Pull-to-refresh is an explicit request, unlike the automatic timer.
    /// It bypasses the interval and then follows any newly adopted account id.
    private func refreshNow() async {
        if let liveSync { syncStatus = await liveSync.sync() }
        await readSnapshot()
    }

    private func readSnapshot() async {
        snapshot = await PlayerRatingSnapshot.load(stats: statsStore, players: players)
        if followsOwnProfile || playerID.isEmpty { playerID = snapshot.me }
    }
}
