import Foundation
import XCTest
@testable import SottoCore

private final class RecordingLicenseStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var accesses = 0

    init(values: [String: String]) {
        self.values = values
    }

    func getString(_ key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        accesses += 1
        return values[key]
    }

    func setString(_ value: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        accesses += 1
        values[key] = value
    }

    func delete(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        accesses += 1
        values.removeValue(forKey: key)
    }

    func snapshot() -> (values: [String: String], accesses: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (values, accesses)
    }
}

private actor RecordingLicenseAPI: LicenseAPI {
    private(set) var calls = 0

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        calls += 1
        throw EntitlementsError.network("Unexpected activation")
    }

    func validate(licenseKey: String, instanceID: String?) async throws -> LicenseValidation {
        calls += 1
        throw EntitlementsError.network("Unexpected validation")
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {
        calls += 1
        throw EntitlementsError.network("Unexpected deactivation")
    }
}

final class EntitlementsServiceTests: XCTestCase {
    func testLegacyOperationsPreserveCredentialsWithoutCallingInjectedAPI() async throws {
        let legacy = [
            "licenseKey": "synthetic-key",
            "licenseInstanceID": "synthetic-instance",
            "lastValidatedISO": "2000-01-01T00:00:00Z",
            "trialStartISO": "2000-01-01T00:00:00Z",
            "installID": "synthetic-install",
        ]
        let store = RecordingLicenseStore(values: legacy)
        let api = RecordingLicenseAPI()
        let service = EntitlementsService(
            config: LicensingConfig(checkoutURL: nil, expectedVariantID: 123), store: store, api: api)
        await service.bootstrapTrialIfNeeded()
        await service.refreshValidationIfNeeded()
        try await service.assertCanTranscribe()
        let state = try await service.deactivate()
        XCTAssertEqual(state.access, .unlocked)
        XCTAssertNil(state.licenseKeyMasked)
        XCTAssertNil(state.lastValidatedAt)
        do {
            _ = try await service.activate(licenseKey: "replacement-key")
            XCTFail("Activation must be unavailable")
        } catch EntitlementsError.configuration {
            // Unavailable without consulting a provider or changing credentials.
        }
        let calls = await api.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(store.snapshot().values, legacy)
        XCTAssertEqual(store.snapshot().accesses, 0)
    }

    func testFreshInstallStaysUnlockedWithoutCreatingTrialOrInstallState() async throws {
        let store = RecordingLicenseStore(values: [:])
        let api = RecordingLicenseAPI()
        let service = EntitlementsService(
            config: LicensingConfig(checkoutURL: nil, expectedVariantID: nil), store: store, api: api)
        await service.bootstrapTrialIfNeeded()
        await service.refreshValidationIfNeeded()
        try await service.assertCanTranscribe()
        let state = await service.currentState()
        XCTAssertEqual(state.access, .unlocked)
        XCTAssertTrue(store.snapshot().values.isEmpty)
        XCTAssertEqual(store.snapshot().accesses, 0)
        let calls = await api.calls
        XCTAssertEqual(calls, 0)
    }

    func testDisabledAPIRejectsEveryOperation() async {
        let api = DisabledLicenseAPI()
        do {
            _ = try await api.activate(licenseKey: "synthetic-key", instanceName: "synthetic-instance")
            XCTFail("Activation must be unavailable")
        } catch EntitlementsError.configuration {
        } catch {
            XCTFail("Unexpected error type")
        }
        do {
            _ = try await api.validate(licenseKey: "synthetic-key", instanceID: "synthetic-instance")
            XCTFail("Validation must be unavailable")
        } catch EntitlementsError.configuration {
        } catch {
            XCTFail("Unexpected error type")
        }
        do {
            try await api.deactivate(licenseKey: "synthetic-key", instanceID: "synthetic-instance")
            XCTFail("Deactivation must be unavailable")
        } catch EntitlementsError.configuration {
        } catch {
            XCTFail("Unexpected error type")
        }
    }
}
