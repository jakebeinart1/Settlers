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

    /// Playable dev card types (VP cards are never "played"), in a fixed
    /// display order, paired with (heldCount, newCount).
    private var rows: [(type: DevCardType, held: Int, new: Int)] {
        guard let human else { return [] }
        let boughtThisTurn = viewModel.state.devCardsBoughtThisTurn[viewModel.humanPlayer] ?? []
        return [DevCardType.knight, .roadBuilding, .yearOfPlenty, .monopoly].compactMap { type in
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
            ForEach(rows, id: \.type) { row in
                let isPlayable = DevCards.canPlay(row.type, by: viewModel.humanPlayer, in: viewModel.state)
                Button {
                    play(row.type)
                } label: {
                    HStack {
                        Text(label(for: row.type))
                        Text("x\(row.held)")
                            .foregroundStyle(.secondary)
                        if row.new > 0 {
                            Text("\(row.new) NEW")
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.yellow.opacity(0.3), in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16)))
                }
                .disabled(!isPlayable)
                .opacity(isPlayable ? 1 : 0.5)
            }
        }
        .sheet(isPresented: $showYearOfPlenty) {
            yearOfPlentySheet
        }
        .sheet(isPresented: $showMonopoly) {
            monopolySheet
        }
    }

    private func label(for type: DevCardType) -> String {
        switch type {
        case .knight: return "Knight"
        case .roadBuilding: return "Road Building"
        case .yearOfPlenty: return "Year of Plenty"
        case .monopoly: return "Monopoly"
        case .victoryPoint: return "Victory Point"
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
