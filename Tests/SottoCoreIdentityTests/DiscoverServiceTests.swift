import XCTest
@testable import SottoCore

final class DiscoverServiceTests: XCTestCase {
    func testBundledBanterHasNoExternalLinksOrSponsoredCards() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/Sotto/Resources/discover-fallback.json"))
        let service = DiscoverService(fallbackData: data)
        let feed = await service.loadContent()
        XCTAssertEqual(feed.items.count, 18)
        XCTAssertEqual(Set(feed.items.map(\.id)).count, feed.items.count)
        for item in feed.items {
            XCTAssertNil(item.url)
            XCTAssertEqual(item.type, .quote)
            XCTAssertTrue(item.body.contains("Rick"))
            XCTAssertTrue(item.body.contains("Morty"))
        }
        let fresh = await service.fetchFresh()
        XCTAssertNil(fresh)
    }

    func testMalformedContentReturnsEmptyFeed() async {
        let feed = await DiscoverService(fallbackData: Data("broken".utf8)).loadContent()
        XCTAssertTrue(feed.items.isEmpty)
    }
}
