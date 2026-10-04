import Foundation

public protocol TelemetryServiceProtocol: Sendable {
    func send(_ event: TelemetryEventSpec)
    @discardableResult
    func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool
    func clearQueue()
    func flush() async
    func flushForTermination()
}

/// Local event hooks only. Sotto has no remote telemetry transport.
public enum Telemetry {
    private final class ServiceStore: @unchecked Sendable {
        private let lock = NSLock()
        private var service: TelemetryServiceProtocol?

        func set(_ service: TelemetryServiceProtocol) {
            lock.lock()
            self.service = service
            lock.unlock()
        }

        func get() -> TelemetryServiceProtocol? {
            lock.lock()
            defer { lock.unlock() }
            return service
        }
    }

    private static let serviceStore = ServiceStore()

    private static func configuredService() -> TelemetryServiceProtocol? {
        serviceStore.get()
    }

    public static func configure(_ service: TelemetryServiceProtocol) {
        serviceStore.set(service)
    }

    public static func send(_ event: TelemetryEventSpec) {
        configuredService()?.send(event)
    }

    public static func clearQueue() {
        configuredService()?.clearQueue()
    }

    public static func flush() async {
        await configuredService()?.flush()
    }

    public static func flushForTermination() {
        configuredService()?.flushForTermination()
    }
}

// MARK: - No-Op Implementation

public final class NoOpTelemetryService: TelemetryServiceProtocol {
    public init() {}
    public func send(_ event: TelemetryEventSpec) {}
    public func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool { true }
    public func clearQueue() {}
    public func flush() async {}
    public func flushForTermination() {}
}
