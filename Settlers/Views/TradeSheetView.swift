import SwiftUI
import CatanEngine

/// Trade sheet: build a give/want offer with per-resource steppers, either
/// proposing it to the bots (`.proposeTrade`) or - with "Bank/Port Trade"
/// toggled on - trading directly with the bank at the player's best rate for
/// the chosen give resource (`Trading.bestRate`, `.bankTrade`). Also lists
/// any trade offers bots have proposed to the human, with Accept/Reject.
public struct TradeSheetView: View {
    public let viewModel: GameViewModel

    public init(viewModel: GameViewModel) {
        self.viewModel = viewModel
    }

    @State private var give: [Resource: Int] = [:]
    @State private var want: [Resource: Int] = [:]
    @State private var isBankMode = false
    @State private var bankGiveResource: Resource = .brick
    @State private var bankWantResource: Resource = .lumber
    @State private var bankMultiplier = 1
    @State private var errorMessage: String?

    private var human: Player? { viewModel.state.players.first { $0.id == viewModel.humanPlayer } }

    private var incomingOffers: [TradeOffer] {
        viewModel.state.pendingTradeOffers.filter { $0.from != viewModel.humanPlayer }
    }

    public var body: some View {
        NavigationStack {
            Form {
                if !incomingOffers.isEmpty {
                    Section("Incoming Offers") {
                        ForEach(incomingOffers) { offer in
                            incomingOfferRow(offer)
                        }
                    }
                }

                Section {
                    Toggle("Bank / Port Trade", isOn: $isBankMode)
                }

                if isBankMode {
                    bankTradeSection
                } else {
                    playerTradeSection
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Trade")
        }
    }

    // MARK: - Bank trade

    private var bankRate: Int {
        Trading.bestRate(for: bankGiveResource, player: viewModel.humanPlayer, state: viewModel.state)
    }

    @ViewBuilder
    private var bankTradeSection: some View {
        Section("Give") {
            Picker("Resource", selection: $bankGiveResource) {
                ForEach(Resource.allCases, id: \.self) { resource in
                    Text(resource.rawValue.capitalized).tag(resource)
                }
            }
            Text("Rate: \(bankRate) : 1")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Want") {
            Picker("Resource", selection: $bankWantResource) {
                ForEach(Resource.allCases.filter { $0 != bankGiveResource }, id: \.self) { resource in
                    Text(resource.rawValue.capitalized).tag(resource)
                }
            }
            Stepper("Quantity: \(bankMultiplier)", value: $bankMultiplier, in: 1...5)
        }
        Section {
            Text("Give \(bankRate * bankMultiplier) \(bankGiveResource.rawValue) for \(bankMultiplier) \(bankWantResource.rawValue)")
                .font(.caption)
            Button("Trade with Bank") {
                perform(.bankTrade(
                    give: [bankGiveResource: bankRate * bankMultiplier],
                    get: [bankWantResource: bankMultiplier]
                ))
            }
        }
    }

    // MARK: - Player trade

    @ViewBuilder
    private var playerTradeSection: some View {
        Section("Give") {
            ForEach(Resource.allCases, id: \.self) { resource in
                Stepper(
                    "\(resource.rawValue.capitalized): \(give[resource] ?? 0)",
                    value: Binding(
                        get: { give[resource] ?? 0 },
                        set: { give[resource] = $0 == 0 ? nil : $0 }
                    ),
                    in: 0...(human?.resources[resource] ?? 0)
                )
            }
        }
        Section("Want") {
            ForEach(Resource.allCases, id: \.self) { resource in
                Stepper(
                    "\(resource.rawValue.capitalized): \(want[resource] ?? 0)",
                    value: Binding(
                        get: { want[resource] ?? 0 },
                        set: { want[resource] = $0 == 0 ? nil : $0 }
                    ),
                    in: 0...10
                )
            }
        }
        Section {
            Button("Propose to Bots") {
                let offer = TradeOffer(from: viewModel.humanPlayer, give: give, want: want)
                perform(.proposeTrade(offer))
            }
            .disabled(give.isEmpty || want.isEmpty)
        }
    }

    // MARK: - Incoming offers

    private func incomingOfferRow(_ offer: TradeOffer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(CatanTheme.playerLabel(for: offer.from)) offers \(describe(offer.give)) for \(describe(offer.want))")
                .font(.caption)
            HStack {
                Button("Accept") {
                    perform(.respondToTrade(offerID: offer.id, accept: true))
                }
                Button("Reject", role: .destructive) {
                    perform(.respondToTrade(offerID: offer.id, accept: false))
                }
            }
        }
    }

    private func describe(_ resources: [Resource: Int]) -> String {
        resources
            .filter { $0.value > 0 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value) \($0.key.rawValue)" }
            .joined(separator: ", ")
    }

    private func perform(_ move: GameMove) {
        do {
            try viewModel.apply(move)
            errorMessage = nil
            give = [:]
            want = [:]
        } catch {
            errorMessage = "\(error)"
        }
    }
}
