import XCTest
@testable import SottoCore

final class TelemetryServiceTests: XCTestCase {
    func testPersonalBuildDiscardsEventsIncludingOptOut() async {
        let service = NoOpTelemetryService()
        service.send(.appLaunched)
        let completed = await service.sendAndFlush(.telemetryOptedOut)
        XCTAssertTrue(completed)
        service.clearQueue()
        await service.flush()
        service.flushForTermination()
    }

    func testTelemetryPreferenceDefaultsOff() {
        let name = "SottoTests.telemetry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(AppPreferences.isTelemetryEnabled(defaults: defaults))
    }
}
