import Foundation
import XCTest
@testable import SottoCore

final class GoogleCalendarEventTests: XCTestCase {
    func testRecurringEventPreservesIdentityMeetingLinkAndRSVP() throws {
        let json = #"""
            {"id":"occurrence","summary":"Planning","start":{"dateTime":"2026-11-14T10:00:00Z"},"end":{"dateTime":"2026-11-14T11:00:00Z"},"hangoutLink":"https://meet.google.com/abc-defg-hij","recurringEventId":"series","attendees":[{"self":true,"responseStatus":"needsAction"},{"email":"other@example.com","responseStatus":"accepted"}]}
            """#
        let payload = try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(json.utf8))
        let event = try XCTUnwrap(payload.calendarEvent(calendarID: "work@example.com", calendarName: "Work"))
        XCTAssertEqual(event.id, "google:work@example.com:occurrence")
        XCTAssertEqual(event.externalId, "google:work@example.com:series")
        XCTAssertTrue(event.isRecurring)
        XCTAssertEqual(event.userStatus, .pending)
        XCTAssertEqual(event.participants.first?.email, "other@example.com")
        XCTAssertEqual(event.meetUrl, "https://meet.google.com/abc-defg-hij")
    }

    func testCancelledAndAllDayEventsAreExcluded() throws {
        for json in [
            #"{"id":"x","status":"cancelled"}"#,
            #"{"id":"x","start":{"date":"2026-11-14"},"end":{"date":"2026-11-15"}}"#,
        ] {
            let payload = try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(json.utf8))
            XCTAssertNil(payload.calendarEvent(calendarID: "primary", calendarName: "Work"))
        }
    }

    func testAuthorizationUsesReadOnlyScopesAndRejectsWrongState() async throws {
        let account = GoogleCalendarAccount(store: CalendarTestStore())
        try await account.importClient(Data(#"{"installed":{"client_id":"test.apps.googleusercontent.com"}}"#.utf8))
        let authorization = try await account.authorization(redirectURI: "http://127.0.0.1:12345/oauth/callback")
        let items = try XCTUnwrap(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)?.queryItems)
        let scopes = try XCTUnwrap(items.first(where: { $0.name == "scope" })?.value)
        XCTAssertEqual(Set(scopes.split(separator: " ").map(String.init)), Set(GoogleCalendarAccount.scopes))
        XCTAssertEqual(items.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        do {
            _ = try await account.complete(
                authorization, callback: URL(string: "http://127.0.0.1:12345/oauth/callback?state=incorrect&code=x")!)
            XCTFail("A callback with the wrong state must be rejected")
        } catch {
            let identity = try await account.identity()
            XCTAssertNil(identity)
        }
    }

    func testCalendarAndEventPagesAreReadWithBearerToken() async throws {
        let store = CalendarTestStore()
        try store.setString(
            #"{"accessToken":"access","refreshToken":"refresh","expiresAt":9000000000,"identity":{"permissionID":"me","email":"me@example.com"}}"#,
            forKey: "credential")
        let transport = CalendarTestTransport()
        let account = GoogleCalendarAccount(store: store, transport: transport)
        let service = GoogleCalendarService(account: account, transport: transport)
        let events = try await service.events(
            from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(events.map(\.id), ["google:me@example.com:event"])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer access" })
        XCTAssertTrue(requests[2].url?.query?.contains("pageToken=next") == true)
    }

    func testDisconnectInvalidatesAnInFlightSession() async throws {
        let store = CalendarTestStore()
        try store.setString(
            #"{"accessToken":"access","refreshToken":"refresh","expiresAt":9000000000,"identity":{"permissionID":"me","email":"me@example.com"}}"#,
            forKey: "credential")
        let account = GoogleCalendarAccount(store: store)
        let marker = await account.sessionMarker()
        try await account.disconnect()
        do {
            try await account.ensureSession(marker)
            XCTFail("Disconnected sessions must not return stale events")
        } catch is CancellationError {
        }
    }

    func testCredentialNamespacesAreSeparate() {
        XCTAssertEqual(
            GoogleCalendarAccount.keychainService(bundleIdentifier: "com.sotto.dev"), "com.sotto.dev.google-calendar")
        XCTAssertEqual(
            GoogleCalendarAccount.keychainService(bundleIdentifier: "com.sotto"), "com.sotto.google-calendar")
    }

    func testReusesDriveClientWithoutDriveCredentialsAndPreservesCalendarClient() async throws {
        let driveStore = CalendarTestStore()
        let calendarStore = CalendarTestStore()
        let drive = GoogleDriveAccount(store: driveStore)
        let calendar = GoogleCalendarAccount(store: calendarStore)
        let driveClient = Data(
            #"{"installed":{"client_id":"drive.apps.googleusercontent.com","client_secret":"client-secret"}}"#.utf8)
        try await drive.importClient(driveClient)
        try driveStore.setString("drive-token-must-not-be-copied", forKey: "credential")

        let copied = try await calendar.reuseDriveClient(from: drive)
        XCTAssertTrue(copied)
        XCTAssertNil(try calendarStore.getString("credential"))
        let auth = try await calendar.authorization(redirectURI: "http://127.0.0.1:12345/oauth/callback")
        let items = try XCTUnwrap(URLComponents(url: auth.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first(where: { $0.name == "client_id" })?.value, "drive.apps.googleusercontent.com")

        let copiedAgain = try await calendar.reuseDriveClient(from: drive)
        XCTAssertFalse(copiedAgain)
        XCTAssertEqual(try driveStore.getString("credential"), "drive-token-must-not-be-copied")
    }
}

private final class CalendarTestStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func getString(_ key: String) throws -> String? { lock.withLock { values[key] } }
    func setString(_ value: String, forKey key: String) throws { lock.withLock { values[key] = value } }
    func delete(_ key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

private actor CalendarTestTransport: GoogleDriveTransport {
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> GoogleDriveResponse {
        requests.append(request)
        let json: String
        if request.url?.path.hasSuffix("calendarList") == true {
            json = #"{"items":[{"id":"me@example.com","summary":"Work"}]}"#
        } else if request.url?.query?.contains("pageToken=next") == true {
            json =
                #"{"items":[{"id":"event","start":{"dateTime":"2026-11-14T10:00:00Z"},"end":{"dateTime":"2026-11-14T11:00:00Z"}}]}"#
        } else {
            json = #"{"items":[],"nextPageToken":"next"}"#
        }
        return GoogleDriveResponse(data: Data(json.utf8), status: 200)
    }
}
