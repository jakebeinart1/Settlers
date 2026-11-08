import EmpiresOnline
import Foundation
import Vapor

@main
enum ServerMain {
    static func main() async throws {
        let configuration = try ServerConfiguration()
        let authority = try OnlineAuthority(directory: configuration.dataDirectory)
        try await authority.tick()
        let application = try await Application.make(.production)
        do {
            application.http.server.configuration.hostname = configuration.hostname
            application.http.server.configuration.port = configuration.port
            OnlineRoutes.install(on: application, authority: authority)
            try await serve(application, authority: authority, push: configuration.push)
        } catch {
            try await application.asyncShutdown()
            throw error
        }
        try await application.asyncShutdown()
    }

    private static func serve(
        _ application: Application, authority: OnlineAuthority, push: PushConfiguration?
    ) async throws {
        let scheduler = OnlineScheduler(authority: authority, logger: application.logger)
        let delivery = try push.map(APNSDelivery.init(configuration:))
        if delivery == nil { application.logger.notice("APNs disabled. Pending actions remain in Your Games") }
        do {
            try await runWorkers(application, scheduler: scheduler, delivery: delivery)
        } catch {
            try await delivery?.shutdown()
            throw error
        }
        try await delivery?.shutdown()
    }

    private static func runWorkers(
        _ application: Application, scheduler: OnlineScheduler, delivery: APNSDelivery?
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask { try await application.execute() }
            tasks.addTask { await scheduler.runDeadlines() }
            if let delivery { tasks.addTask { await scheduler.runPushes(using: delivery) } }
            defer { tasks.cancelAll() }
            _ = try await tasks.next()
        }
    }
}
