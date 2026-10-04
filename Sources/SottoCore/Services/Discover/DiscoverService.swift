import Foundation

public protocol DiscoverServiceProtocol: Sendable {
    func loadContent() async -> DiscoverFeed
    func fetchFresh() async -> DiscoverFeed?
}

/// Personal Discover cards come only from bundled content. Legacy caches and
/// remote feeds are never read, so upstream content cannot replace the banter.
public final class DiscoverService: DiscoverServiceProtocol {
    private let fallbackData: Data

    public init(fallbackData: Data) {
        self.fallbackData = fallbackData
    }

    public func loadContent() async -> DiscoverFeed {
        (try? JSONDecoder().decode(DiscoverFeed.self, from: fallbackData))
            ?? DiscoverFeed(version: 0, items: [])
    }

    /// Retained protocol boundary for view-model refresh/cancellation tests.
    public func fetchFresh() async -> DiscoverFeed? { nil }
}
