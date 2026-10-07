import CatanEngine

/// Monopoly takes a resource from every rival. Its combined collectible count
/// is public: finite supply minus bank stock minus the owner's hand. Keeping
/// only those inputs here prevents presentation from inspecting rival hands.
/// Missing or impossible stock is unknown, rather than a fabricated zero or a
/// guess from a legacy save whose bank field was absent.
struct MonopolyCollectionPreview: Sendable {
    let totalPerResource: Int
    let bank: [Resource: Int]
    let ownHand: [Resource: Int]

    func collectibleCount(for resource: Resource) -> Int? {
        let owned = ownHand[resource, default: 0]
        guard totalPerResource > 0,
              let stock = bank[resource],
              (0...totalPerResource).contains(stock),
              (0...totalPerResource).contains(owned),
              stock <= totalPerResource - owned else { return nil }
        return totalPerResource - owned - stock
    }
}
