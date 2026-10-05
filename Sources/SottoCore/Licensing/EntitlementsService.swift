import Foundation

/// Inert entitlement compatibility surface for the personal fork.
/// Stored activation state is never read, written, cleared, or sent to a server.
public actor EntitlementsService: EntitlementsChecking {
    /// Retains the initializer used by app/CLI composition and local test clients.
    /// Dependencies are intentionally ignored; even an injected API cannot run.
    public init(config: LicensingConfig, store: KeyValueStore, api: LicenseAPI) {}

    public func bootstrapTrialIfNeeded(now: Date = Date()) {}

    public func currentState(now: Date = Date()) async -> EntitlementsState {
        EntitlementsState(access: .unlocked, licenseKeyMasked: nil, lastValidatedAt: nil)
    }

    public func assertCanTranscribe(now: Date = Date()) async throws {}

    public func activate(licenseKey: String, now: Date = Date()) async throws -> EntitlementsState {
        throw EntitlementsError.configuration(
            "License activation is unavailable in this personal fork. Sotto is already unlocked.")
    }

    /// Retained as a non-destructive compatibility operation; credentials stay intact.
    public func deactivate(now: Date = Date()) async throws -> EntitlementsState {
        await currentState(now: now)
    }

    public func refreshValidationIfNeeded(now: Date = Date()) async {}
}
