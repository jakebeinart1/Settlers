import SwiftUI
import CatanEngine

/// Modal presented when the human must discard half their hand after a
/// 7-roll (`state.phase == .discarding` with `humanPlayer` in `pending`).
/// Per-resource steppers pick exactly `Robber.discardCount(for:)` cards; the
/// submit button stays disabled until the picked total matches.
public struct DiscardView: View {
    public let viewModel: GameViewModel

    public init(viewModel: GameViewModel) {
        self.viewModel = viewModel
    }

    @State private var discard: [Resource: Int] = [:]
    @State private var errorMessage: String?

    private var human: Player? { viewModel.state.players.first { $0.id == viewModel.humanPlayer } }
    private var requiredCount: Int { human.map { Robber.discardCount(for: $0) } ?? 0 }
    private var selectedCount: Int { discard.values.reduce(0, +) }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Discard \(selectedCount) of \(requiredCount) cards")
                        .font(.headline)
                }
                Section {
                    ForEach(Resource.allCases, id: \.self) { resource in
                        Stepper(
                            "\(resource.rawValue.capitalized): \(discard[resource] ?? 0)",
                            value: Binding(
                                get: { discard[resource] ?? 0 },
                                set: { discard[resource] = $0 == 0 ? nil : $0 }
                            ),
                            in: 0...(human?.resources[resource] ?? 0)
                        )
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Discard") {
                    do {
                        try viewModel.apply(.discard(discard))
                        discard = [:]
                        errorMessage = nil
                    } catch {
                        errorMessage = "\(error)"
                    }
                }
                .disabled(selectedCount != requiredCount)
            }
            .navigationTitle("Discard")
        }
    }
}
