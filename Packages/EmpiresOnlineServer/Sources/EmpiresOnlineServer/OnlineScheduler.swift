import EmpiresOnline
import Vapor

struct OnlineScheduler: Sendable {
    private static let maxPushesPerPass = 8
    private static let pollInterval: Duration = .seconds(1)

    let authority: OnlineAuthority
    let logger: Logger

    func runDeadlines() async {
        while !Task.isCancelled {
            do {
                try await authority.tick()
            } catch {
                logger.error("Online scheduler could not persist a match update")
            }
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                return
            }
        }
    }

    func runPushes(using delivery: APNSDelivery) async {
        while !Task.isCancelled {
            await deliverBatch(using: delivery)
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                return
            }
        }
    }

    private func deliverBatch(using delivery: APNSDelivery) async {
        let pending = await authority.pendingPushes()
        await withTaskGroup(of: Void.self) { group in
            for candidate in pending.prefix(Self.maxPushesPerPass) {
                group.addTask { await send(candidate, using: delivery) }
            }
        }
    }

    private func send(_ candidate: OnlinePush, using delivery: APNSDelivery) async {
        // The previous read and the current network send cannot share an actor
        // transaction. Avoid a send when the action was answered in between.
        guard !Task.isCancelled,
              await authority.pendingPushes().contains(where: { $0.id == candidate.id }) else { return }
        let result = await delivery.deliver(candidate)
        guard !Task.isCancelled else { return }
        do {
            try await authority.resolvePush(id: candidate.id, result: result)
        } catch {
            logger.error("Online scheduler could not persist a push result")
        }
    }
}
