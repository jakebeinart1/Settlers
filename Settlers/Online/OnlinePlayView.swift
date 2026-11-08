import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CatanEngine
import EmpiresOnline

struct OnlinePlayView: View {
    static var isConfigured: Bool { OnlineTransport.configuredEndpoint != nil }

    let onClose: () -> Void
    @State private var model = OnlinePlayModel()
    @State private var router = OnlineNotificationRouter.shared
    @State private var panel: OnlineEntryPanel?
    @State private var inviteCode = ""
    @State private var showingLeave = false
    @State private var routeRetry: RouteRetry?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            OnlineScenery()
            VStack(spacing: 0) {
                header
                if model.match?.status != .playing && model.match?.status != .finished { banners }
                contents
            }
        }
        .foregroundStyle(.white)
        .sheet(item: $panel) { panel in
            panelView(panel)
                .preferredColorScheme(.dark)
        }
        .confirmationDialog("Leave this table?", isPresented: $showingLeave, titleVisibility: .visible) {
            Button("Leave table", role: .destructive) {
                guard let match = model.match else { return }
                Task { await model.leave(match.id) }
            }
        } message: {
            Text("In a game in progress, the other players continue with an AI in your seat.")
        }
        .task {
            await model.restore()
            await followRoute()
            await model.refresh()
            if model.account != nil { await OnlineDeviceRegistrar.shared.resume() }
        }
        .task(id: scenePhase) { await refreshWhileVisible() }
        .onChange(of: router.route, initial: true) { _, _ in Task { await followRoute() } }
        .onChange(of: model.account?.id) { _, _ in
            Task {
                await followRoute()
                await model.refresh()
            }
        }
        .onChange(of: model.match?.id, initial: true) { _, id in router.activeMatchID = id }
        .onChange(of: router.registrationFailed) { _, failed in
            if failed { model.message = "Turn alerts could not be registered. Your Games still shows pending actions." }
        }
        .onDisappear { router.activeMatchID = nil }
        .accessibilityIdentifier("online.screen")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if model.match != nil { Task { await model.showGames() } } else { onClose() }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.match == nil ? "Main Menu" : "Your Games")
            VStack(alignment: .leading, spacing: 2) {
                Text("E M P I R E S   O N L I N E")
                    .font(.system(.caption2, design: .serif, weight: .semibold))
                    .foregroundStyle(SettingsChrome.ornamentGold)
                    .accessibilityHidden(true)
                Text(title).font(.system(.title2, design: .serif, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 4)
            if model.account != nil {
                Button { panel = .account } label: {
                    Image(systemName: "person.crop.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Online account")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .background(.black.opacity(0.25))
    }

    private var title: String {
        switch model.match?.status {
        case .lobby: "Waiting Room"
        case .playing: "Match"
        case .finished: "Result"
        case .cancelled: "Table Closed"
        case nil: model.account == nil ? "Online Play" : "Your Games"
        }
    }

    @ViewBuilder
    private var contents: some View {
        if model.isChangingAccount {
            ProgressView("Updating online account…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !Self.isConfigured {
            scroll { OnlineInformation(title: "Online play is unavailable",
                                       detail: "This build is not connected to the match server.") }
        } else if model.account == nil {
            scroll {
                OnlineAccountEntry(model: model) {
                    if model.account != nil { await OnlineDeviceRegistrar.shared.resume() }
                }
            }
        } else if let position = model.match {
            matchContents(position)
        } else {
            scroll { gameList }
                .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder
    private func matchContents(_ position: OnlineMatchView) -> some View {
        switch position.status {
        case .lobby:
            scroll {
                OnlineLobby(position: position, model: model, router: router,
                            edit: { panel = .edit }, leave: { showingLeave = true })
            }
        case .playing, .finished:
            if let gameplay = position.gameplay {
                OnlineMatchBoard(position: position, gameplay: gameplay, model: model,
                                 leave: { showingLeave = true })
                    .id(position.id)
            } else {
                scroll { OnlineInformation(title: "Match unavailable", detail: "Return to Your Games and try again.") }
            }
        case .cancelled:
            scroll { OnlineInformation(title: "This table closed", detail: "Return to Your Games to start or join another.") }
        }
    }

    private var gameList: some View {
        VStack(alignment: .leading, spacing: 14) {
            GoldRowButton(title: "Create Table", subtitle: "Invite friends to async or timed play.",
                          systemImage: "plus", iconColor: SettingsChrome.ornamentGold,
                          isEnabled: !model.isWorking) { panel = .create }
                .accessibilityIdentifier("online.create")
            GoldRowButton(title: "Join by Code", systemImage: "link",
                          iconColor: SettingsChrome.ornamentGold, isEnabled: !model.isWorking) {
                inviteCode = ""
                panel = .join
            }
            .accessibilityIdentifier("online.join")
            gamesSection("Needs Your Action", rows: model.games.filter(\.needsYou))
            gamesSection("Waiting", rows: model.games.filter { !$0.needsYou && ($0.status == .playing || $0.status == .lobby) })
            gamesSection("History", rows: model.games.filter { $0.status == .finished || $0.status == .cancelled })
            if model.games.isEmpty && !model.isWorking {
                OnlineInformation(title: "Your next game starts here",
                                  detail: "Create a private table, or join a friend with an invitation.")
            }
        }
    }

    @ViewBuilder
    private func gamesSection(_ heading: String, rows: [OnlineGameSummary]) -> some View {
        if !rows.isEmpty {
            Text(heading).font(.system(.headline, design: .serif)).accessibilityAddTraits(.isHeader)
                .padding(.top, 5)
            ForEach(rows, id: \.id) { row in
                GoldRowButton(title: row.title, subtitle: row.onlineCaption,
                              systemImage: row.needsYou ? "bell.badge.fill" : "hexagon",
                              iconColor: row.needsYou ? SettingsChrome.ornamentGold : .white,
                              isEnabled: !model.isWorking) {
                    Task { await model.run(.view(matchID: row.id)) }
                }
                .accessibilityIdentifier("online.game.\(row.id)")
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if model.hasPendingSubmission {
            HStack {
                Label("Waiting for move confirmation", systemImage: "clock.arrow.circlepath")
                Spacer()
                Button("Retry") { Task { await model.retrySubmission() } }
                    .disabled(model.isWorking)
            }
            .font(.footnote)
            .padding(10)
            .background(.black.opacity(0.72))
        } else if model.isOffline {
            Label("Reconnecting. Game actions are paused on this device.", systemImage: "wifi.slash")
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.black.opacity(0.72))
        }
        if let message = model.message {
            HStack(spacing: 8) {
                Text(message).font(.footnote)
                Spacer()
                Button { model.message = nil } label: {
                    Image(systemName: "xmark").frame(minWidth: 38, minHeight: 38)
                }
                .accessibilityLabel("Dismiss message")
            }
            .padding(.leading, 10)
            .background(.black.opacity(0.72))
        }
    }

    private func scroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content().frame(maxWidth: 520)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func panelView(_ panel: OnlineEntryPanel) -> some View {
        switch panel {
        case .create:
            OnlineRoomForm(position: nil, initialCode: "", model: model) { self.panel = nil }
        case .join:
            OnlineRoomForm(position: nil, initialCode: inviteCode, model: model, joining: true) { self.panel = nil }
        case .edit:
            OnlineRoomForm(position: model.match, initialCode: "", model: model) { self.panel = nil }
        case .account:
            OnlineAccountPanel(model: model, router: router, onClose: { self.panel = nil },
                               copyKey: copyRecoveryKey)
        }
    }

    private func copyRecoveryKey() {
        guard let key = model.recoveryKey else { return }
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: key]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(90)])
        model.message = "Recovery key copied for 90 seconds."
    }

    private func followRoute() async {
        guard model.account != nil, !model.isWorking, let route = router.route else { return }
        switch route {
        case .match(let id):
            if let routeRetry, routeRetry.matchID == id, ContinuousClock.now < routeRetry.nextAttempt { return }
            let opened = await model.run(.view(matchID: id)) && model.match?.id == id
            guard router.route == route else { return }
            if opened || model.lastRequestError?.matchUnavailable == true {
                router.route = nil
                routeRetry = nil
                if !opened { await model.showGames(keepingMessage: true) }
            } else {
                routeRetry = RouteRetry(matchID: id, nextAttempt: ContinuousClock.now.advanced(by: .seconds(8)))
            }
        case .join(let code):
            router.route = nil
            routeRetry = nil
            inviteCode = code
            panel = .join
        }
    }

    private func refreshWhileVisible() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            if let token = router.deviceToken { await OnlineDeviceRegistrar.shared.register(token: token) }
            await followRoute()
            await model.refresh()
            let interval = model.match?.configuration.pace == .timedLive ? 1 : model.match != nil ? 3 : 8
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
        }
    }

    private struct RouteRetry {
        let matchID: UUID
        let nextAttempt: ContinuousClock.Instant
    }
}

private enum OnlineEntryPanel: String, Identifiable {
    case create, join, edit, account
    var id: String { rawValue }
}

private extension OnlineGameSummary {
    var onlineCaption: String {
        if needsYou { return "\(pace.onlineLabel) · Your action is needed" }
        switch status {
        case .lobby: return "\(pace.onlineLabel) · Waiting room"
        case .playing: return "\(pace.onlineLabel) · \(turnName.map { "\($0)’s turn" } ?? "In progress")"
        case .finished: return "\(pace.onlineLabel) · Completed"
        case .cancelled: return "Table closed"
        }
    }
}

extension OnlinePace {
    var onlineLabel: String { self == .timedLive ? "Timed Live" : "Asynchronous" }
}

struct OnlineScenery: View {
    var body: some View {
        GeometryReader { geometry in
            ThemedBackgroundImage()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .overlay {
            LinearGradient(colors: [.black.opacity(0.78), .black.opacity(0.36), .black.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct OnlineInformation: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.headline, design: .serif)).foregroundStyle(SettingsChrome.ornamentGold)
            Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))
    }
}
