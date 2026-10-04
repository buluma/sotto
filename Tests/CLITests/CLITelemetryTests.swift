import ArgumentParser
import XCTest
@testable import CLI
@testable import SottoCore

final class CLITelemetryTests: XCTestCase {

    func testSuccessfulThrownExitHasNoTelemetryError() {
        let result: Result<Void, Error> = .failure(ExitCode.success)
        XCTAssertEqual(result.cliTelemetryOutcome, .success)
        XCTAssertEqual(result.cliTelemetryExitCode, 0)
        XCTAssertNil(result.cliTelemetryErrorType)
    }

    func testRuntimeFailureStillHasTelemetryError() {
        let result: Result<Void, Error> = .failure(ExitCode.failure)
        XCTAssertEqual(result.cliTelemetryOutcome, .failure)
        XCTAssertEqual(result.cliTelemetryExitCode, 1)
        XCTAssertNotNil(result.cliTelemetryErrorType)
    }

    func testEnvironmentCannotEnableRemoteTelemetry() async {
        CLITelemetry.configureIfNeeded(env: ["SOTTO_TELEMETRY": "1"])
        await Telemetry.flush()
    }

    // MARK: - operation metadata

    func testMetadataUsesCanonicalNestedCommandPath() throws {
        let command = try CLI.parseAsRoot(["config", "set", "telemetry", "off"])

        let metadata = CLITelemetry.metadata(for: command)

        XCTAssertEqual(metadata.command, "config")
        XCTAssertEqual(metadata.subcommand, "set")
        XCTAssertNil(metadata.inputKind)
        XCTAssertNil(metadata.outputFormat)
        XCTAssertEqual(metadata.json, false)
        XCTAssertTrue(metadata.suppressEvent)
    }

    func testConfigSetTelemetryOnDoesNotSuppressTelemetryEvent() throws {
        let command = try CLI.parseAsRoot(["config", "set", "telemetry", "on"])

        let metadata = CLITelemetry.metadata(for: command)

        XCTAssertEqual(metadata.command, "config")
        XCTAssertEqual(metadata.subcommand, "set")
        XCTAssertFalse(metadata.suppressEvent)
    }

    func testTranscribeMetadataKeepsPrivacySafeInputKindAndOutputFormat() throws {
        let command = try CLI.parseAsRoot([
            "transcribe",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "--format",
            "json",
        ])

        let metadata = CLITelemetry.metadata(for: command)

        XCTAssertEqual(metadata.command, "transcribe")
        XCTAssertNil(metadata.subcommand)
        XCTAssertEqual(metadata.inputKind, .youtube)
        XCTAssertEqual(metadata.outputFormat, "json")
        XCTAssertEqual(metadata.json, true)
        XCTAssertFalse(metadata.suppressEvent)
    }

    func testTranscribeMetadataUsesMediaInputKindForGenericURL() throws {
        let command = try CLI.parseAsRoot([
            "transcribe",
            "https://www.facebook.com/reel/1998924354042801",
            "--format",
            "json",
        ])

        let metadata = CLITelemetry.metadata(for: command)

        XCTAssertEqual(metadata.command, "transcribe")
        XCTAssertEqual(metadata.inputKind, .media)
        XCTAssertEqual(metadata.outputFormat, "json")
        XCTAssertEqual(metadata.json, true)
    }

    func testRetranscribeEnvelopeMetadataUsesJSONOutputFormat() throws {
        let command = try CLI.parseAsRoot([
            "retranscribe",
            "abcd",
            "--update",
            "--envelope",
        ])

        let metadata = CLITelemetry.metadata(for: command)

        XCTAssertEqual(metadata.command, "retranscribe")
        XCTAssertEqual(metadata.outputFormat, "json")
        XCTAssertEqual(metadata.json, true)
    }

    func testTranscribeMetadataClassifiesApplePodcastsInputKind() throws {
        let command = try CLI.parseAsRoot([
            "transcribe",
            "https://podcasts.apple.com/us/podcast/the-daily/id1200361736?i=1000654321987",
        ])

        let metadata = CLITelemetry.metadata(for: command)

        XCTAssertEqual(metadata.command, "transcribe")
        XCTAssertEqual(metadata.inputKind, .podcast)
        XCTAssertFalse(metadata.suppressEvent)
    }

    func testTranscribeMetadataClassifiesPodcastSearchInputKind() throws {
        let command = try CLI.parseAsRoot([
            "transcribe",
            "--podcast",
            "Lex Fridman episode 400",
        ])

        let metadata = CLITelemetry.metadata(for: command)

        XCTAssertEqual(metadata.command, "transcribe")
        XCTAssertEqual(metadata.inputKind, .podcast)
        XCTAssertFalse(metadata.suppressEvent)
    }

    func testTelemetryOutcomeTreatsSuccessfulExitCodeAsSuccess() {
        let result = Result<Void, Error>.failure(ExitCode.success)

        XCTAssertEqual(result.cliTelemetryOutcome, .success)
        XCTAssertEqual(result.cliTelemetryExitCode, 0)
    }
}
