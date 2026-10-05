# Licensing compatibility

This personal GPLv3 fork is always unlocked. The owner approved removing licensing network calls; [ADR-006](../../../spec/adr/006-trial-and-license-activation.md) and the [local entitlement contract](../../../spec/contracts/licensing-local-only.md) record the decision.

`EntitlementsService` retains its initializer and methods for existing app/CLI callers. It never reads, writes, or clears activation/trial/install fields. Bootstrap and refresh do nothing; activation reports unavailable; deactivation returns unlocked without changing stored credentials. `currentState` is unlocked and `assertCanTranscribe` succeeds.

`LicenseAPI.swift` retains protocol/value types and the inert `DisabledLicenseAPI`; there is no HTTP client or licensing endpoint. App and CLI composition use the disabled implementation. An injected API cannot re-enable calls through `EntitlementsService`. Legacy checkout URLs, product identifiers, CLI `--enforce-entitlements`, and stored credentials are compatibility state, not a commercial roadmap.

Preserve `EntitlementsState`, `EntitlementsChecking`, existing Keychain namespaces, and persisted data. Do not restore network licensing or capture gates without an explicit owner decision and matching ADR/contract changes. The generic Keychain store remains available to existing consumers.

Verify with `swift test --filter EntitlementsServiceTests`. Test existing and empty stored state, stale validation, no API/store accesses, unavailable activation, and non-destructive deactivation. Baseline capture tests remain separate.
