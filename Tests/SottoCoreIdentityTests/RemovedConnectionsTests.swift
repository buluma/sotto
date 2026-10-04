import XCTest
@testable import SottoCore

final class RemovedConnectionsTests: XCTestCase {
    func testSharingCannotBeEnabledByLegacyDebugArgument() {
        XCTAssertFalse(AppFeatures.isShareLinksAvailable(arguments: []))
        XCTAssertFalse(AppFeatures.isShareLinksAvailable(arguments: ["sotto", "--enable-share-links"]))
    }

    func testDefaultSharingTransportRejectsEveryOriginWithoutNetworking() async {
        let transport = DisabledShareHTTPTransport()
        for origin in ["https://share.macparakeet.com", "http://localhost:8080", "https://sharing.invalid"] {
            do {
                _ = try await transport.send(
                    ShareHTTPRequest(method: "POST", path: "/api/v1/owners", body: Data("private".utf8)),
                    origin: URL(string: origin)!)
                XCTFail("Sharing must remain unavailable")
            } catch ShareTransportError.unapprovedOrigin {
                // No networking implementation exists.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
