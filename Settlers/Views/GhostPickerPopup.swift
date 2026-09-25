import CatanAI
import SwiftUI

/// The ghosts a seat can take (Jake, 2026-09-25: "when you select the player
/// you will have an option of the ghosts to choose from"). Each row shows how
/// many games the ghost learned from and its Elo. A ghost already in another
/// seat is shown but cannot be taken twice.
struct GhostPickerPopup: View {
    let seatIndex: Int
    let ghosts: [GhostProfile]
    let taken: Set<String>
    let ratings: Ratings
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        PopupCard(onDismiss: onCancel) {
            VStack(spacing: 14) {
                Text("Seat \(seatIndex + 1) Ghost")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                ForEach(ghosts) { ghost in row(ghost) }
                GoldRowButton(title: "Close", systemImage: "xmark", action: onCancel)
            }
            .padding(16)
            .foregroundStyle(.white)
        }
    }

    private func row(_ ghost: GhostProfile) -> some View {
        let isTaken = taken.contains(ghost.id)
        let elo = ratings.ratings[RatedEntity.ghost(ghost.id).key] ?? Elo.start
        return GoldRowButton(
            title: ghost.name,
            subtitle: isTaken ? "Already seated" : "Learned from \(ghost.gamesLearned) games · Elo \(Int(elo.rounded()))",
            systemImage: "person.crop.circle.badge.clock",
            iconColor: SettingsChrome.ornamentGold,
            isEnabled: !isTaken,
            action: { onSelect(ghost.id) }
        )
        .accessibilityIdentifier(AccessibilityID.NewGame.ghostOption(ghost.id))
    }
}
