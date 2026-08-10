import SwiftUI
import CatanEngine

/// Lists the human's development cards (grouped by type), each row showing
/// how many are held and, if any were bought this turn, how many of those
/// are still "new" (unplayable until next turn - see `DevCards.canPlay`) via
/// a badge; a row is only tappable when at least one playable-now card of
/// that type is held.
///
/// Year-of-plenty and monopoly are simple enough (bank-only, no board
/// interaction) to resolve entirely within this view's own sheets. Knight
/// and road-building both need to drive `BoardView` (robber placement / two
/// free road picks), so those are handed off to `GameView` via `onPlay`.
public struct DevCardPanelView: View {
    public let viewModel: GameViewModel
    public let onPlay: (DevCardType) -> Void

    public init(viewModel: GameViewModel, onPlay: @escaping (DevCardType) -> Void) {
        self.viewModel = viewModel
        self.onPlay = onPlay
    }

    @State private var showYearOfPlenty = false
    @State private var yopFirst: Resource = .brick
    @State private var yopSecond: Resource = .brick
    @State private var showMonopoly = false
    @State private var monopolyResource: Resource = .brick
    @State private var errorMessage: String?

    private var human: Player? { viewModel.state.players.first { $0.id == viewModel.humanPlayer } }

    /// All dev card types the human may hold, in a fixed display order,
    /// paired with (heldCount, newCount). Victory Point cards are included
    /// so they're visible in the panel, but are never tappable/playable
    /// (see `isPlayable` below - `DevCards.canPlay` doesn't special-case
    /// them, so this view excludes `.victoryPoint` explicitly).
    private var rows: [(type: DevCardType, held: Int, new: Int)] {
        guard let human else { return [] }
        let boughtThisTurn = viewModel.state.devCardsBoughtThisTurn[viewModel.humanPlayer] ?? []
        return [DevCardType.knight, .roadBuilding, .yearOfPlenty, .monopoly, .victoryPoint].compactMap { type in
            let held = human.devCards.filter { $0 == type }.count
            guard held > 0 else { return nil }
            let new = boughtThisTurn.filter { $0 == type }.count
            return (type, held, new)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            if rows.isEmpty {
                Text("No development cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(rows, id: \.type) { row in
                        // `DevCards.canPlay` is generic across types and
                        // doesn't know Victory Point cards are never played;
                        // exclude them here so they never render as
                        // tappable.
                        let isPlayable = row.type != .victoryPoint
                            && DevCards.canPlay(row.type, by: viewModel.humanPlayer, in: viewModel.state)
                        DevCardTile(type: row.type, held: row.held, new: row.new, isPlayable: isPlayable) {
                            play(row.type)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .sheet(isPresented: $showYearOfPlenty) {
            yearOfPlentySheet
        }
        .sheet(isPresented: $showMonopoly) {
            monopolySheet
        }
    }

    private func play(_ type: DevCardType) {
        switch type {
        case .knight, .roadBuilding:
            onPlay(type)
        case .yearOfPlenty:
            showYearOfPlenty = true
        case .monopoly:
            showMonopoly = true
        case .victoryPoint:
            break
        }
    }

    private var yearOfPlentySheet: some View {
        NavigationStack {
            Form {
                Picker("First resource", selection: $yopFirst) {
                    ForEach(Resource.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Second resource", selection: $yopSecond) {
                    ForEach(Resource.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button("Play Year of Plenty") {
                    do {
                        try viewModel.apply(.playYearOfPlenty(yopFirst, yopSecond))
                        showYearOfPlenty = false
                        errorMessage = nil
                    } catch {
                        errorMessage = "\(error)"
                    }
                }
            }
            .navigationTitle("Year of Plenty")
        }
    }

    private var monopolySheet: some View {
        NavigationStack {
            Form {
                Picker("Resource", selection: $monopolyResource) {
                    ForEach(Resource.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button("Play Monopoly") {
                    do {
                        try viewModel.apply(.playMonopoly(monopolyResource))
                        showMonopoly = false
                        errorMessage = nil
                    } catch {
                        errorMessage = "\(error)"
                    }
                }
            }
            .navigationTitle("Monopoly")
        }
    }
}

/// One development card rendered as a little playing-card-like tile - a
/// distinct icon/color per `DevCardType`, the held count as a corner badge,
/// and the "NEW" (bought-this-turn, unplayable until next turn) badge -
/// replacing the previous plain list row. Tap-to-play and the `isPlayable`
/// disable/dim behavior are unchanged from the row version.
private struct DevCardTile: View {
    let type: DevCardType
    let held: Int
    let new: Int
    let isPlayable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("x\(held)")
                    .font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(width: 92, height: 128)
            .background(RoundedRectangle(cornerRadius: 12).fill(color.gradient))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if new > 0 {
                    Text("\(new) NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.9), in: Capsule())
                        .padding(4)
                }
            }
        }
        .disabled(!isPlayable)
        .opacity(isPlayable ? 1 : 0.5)
    }

    private var icon: String {
        switch type {
        case .knight: return "shield.fill"
        case .roadBuilding: return "road.lanes"
        case .yearOfPlenty: return "sparkles"
        case .monopoly: return "crown.fill"
        case .victoryPoint: return "star.fill"
        }
    }

    private var color: Color {
        switch type {
        case .knight: return .red
        case .roadBuilding: return .brown
        case .yearOfPlenty: return .green
        case .monopoly: return .purple
        case .victoryPoint: return Color(red: 0.85, green: 0.65, blue: 0.1)
        }
    }

    private var label: String {
        switch type {
        case .knight: return "Knight"
        case .roadBuilding: return "Road Building"
        case .yearOfPlenty: return "Year of Plenty"
        case .monopoly: return "Monopoly"
        case .victoryPoint: return "Victory Point"
        }
    }
}
