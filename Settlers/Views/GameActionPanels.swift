import SwiftUI
import CatanEngine

/// The fixed-height command surface used while choosing a robber destination
/// and, when required, a victim. Keeping it outside `GameView` prevents the
/// game's orchestration view from also owning the layout implementation.
struct GameRobberTargetingPanel: View {
    let targetSelected: Bool
    let victims: [PlayerID]
    let identity: (PlayerID) -> PlayerIdentity
    let resourceCount: (PlayerID) -> Int
    let isKnight: Bool
    let errorMessage: String?
    let onChooseVictim: (PlayerID) -> Void
    let onRepick: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if targetSelected { victimPicker } else { destinationPrompt }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .frame(height: BottomRowMetrics.height)
    }

    private var victimPicker: some View {
        VStack(spacing: 8) {
            Text("Steal from:")
                .font(.subheadline.bold())
                .foregroundStyle(CatanTheme.onWaterText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(victims, id: \.self) { victim in
                        RobberVictimButton(
                            identity: identity(victim),
                            resourceCardCount: resourceCount(victim),
                            action: { onChooseVictim(victim) }
                        )
                    }
                    UniformActionButton(
                        title: "Re-pick",
                        systemImage: "arrow.uturn.backward",
                        isEnabled: true,
                        action: onRepick
                    )
                    if isKnight {
                        UniformActionButton(
                            title: "Cancel Card",
                            systemImage: "xmark",
                            isEnabled: true,
                            action: onCancel
                        )
                    }
                }
            }
        }
    }

    private var destinationPrompt: some View {
        HStack(spacing: 10) {
            Text("🏜️ Move the Robber — tap a highlighted tile above")
                .font(.subheadline.bold())
                .foregroundStyle(CatanTheme.onWaterText)
                .frame(maxWidth: .infinity)
            if isKnight {
                UniformActionButton(
                    title: "Cancel Card",
                    systemImage: "xmark",
                    isEnabled: true,
                    action: onCancel
                )
                .frame(width: 100)
            }
        }
    }
}

/// Holds Road Building's first-road draft without committing either road until
/// the second legal edge is chosen. Undo and cancel remain visible throughout.
struct GameRoadBuildingPanel: View {
    let hasFirstRoad: Bool
    let onUndo: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Text(hasFirstRoad
                 ? "First road staged — choose the second"
                 : "Road Building — choose the first highlighted road")
                .font(.caption.bold())
                .foregroundStyle(CatanTheme.onWaterText)
            HStack(spacing: 8) {
                if hasFirstRoad {
                    UniformActionButton(
                        title: "Undo First",
                        systemImage: "arrow.uturn.backward",
                        isEnabled: true,
                        action: onUndo
                    )
                }
                UniformActionButton(
                    title: "Cancel Card",
                    systemImage: "xmark",
                    isEnabled: true,
                    action: onCancel
                )
            }
        }
        .frame(height: BottomRowMetrics.height)
    }
}
