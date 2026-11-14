import Foundation

/// Reads Google calendars on demand. Event data is kept in memory only.
public actor GoogleCalendarService {
    public static let shared = GoogleCalendarService()
    private let account: GoogleCalendarAccount
    private let transport: any GoogleDriveTransport

    public init(
        account: GoogleCalendarAccount = .shared, transport: any GoogleDriveTransport = GoogleDriveHTTPTransport()
    ) {
        self.account = account
        self.transport = transport
    }

    private struct CalendarList: Decodable {
        struct Item: Decodable {
            let id: String
            let summary: String?
            let deleted: Bool?
            let accessRole: String?
        }
        let items: [Item]?
        let nextPageToken: String?
    }
    private struct EventList: Decodable {
        let items: [GoogleCalendarEvent]?
        let nextPageToken: String?
    }

    private func get<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await account.accessToken())", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        try response.requireCalendarSuccess()
        return try JSONDecoder().decode(T.self, from: response.data)
    }

    private func calendars() async throws -> [CalendarList.Item] {
        var results: [CalendarList.Item] = []
        var page: String?
        repeat {
            var url = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
            if let page { url.queryItems = [URLQueryItem(name: "pageToken", value: page)] }
            let response = try await get(url.url!, as: CalendarList.self)
            results.append(
                contentsOf: (response.items ?? []).filter {
                    $0.deleted != true && $0.accessRole != "freeBusyReader" && $0.accessRole != "none"
                })
            page = response.nextPageToken
        } while page != nil
        return results
    }

    public func availableCalendars() async throws -> [CalendarInfo] {
        let marker = await account.sessionMarker()
        let result = try await calendars().map {
            CalendarInfo(id: "google:\($0.id)", title: $0.summary ?? $0.id, sourceTitle: "Google")
        }
        try await account.ensureSession(marker)
        return result
    }

    public func events(from: Date, to: Date) async throws -> [CalendarEvent] {
        let marker = await account.sessionMarker()
        let calendars = try await calendars()
        let formatter = ISO8601DateFormatter()
        var events: [CalendarEvent] = []
        for calendar in calendars {
            var page: String?
            repeat {
                let base = URL(string: "https://www.googleapis.com/calendar/v3/calendars")!
                    .appendingPathComponent(calendar.id).appendingPathComponent("events")
                var url = URLComponents(url: base, resolvingAgainstBaseURL: false)!
                url.queryItems = [
                    URLQueryItem(name: "timeMin", value: formatter.string(from: from)),
                    URLQueryItem(name: "timeMax", value: formatter.string(from: to)),
                    URLQueryItem(name: "singleEvents", value: "true"),
                    URLQueryItem(name: "maxResults", value: "250"),
                ]
                if let page { url.queryItems?.append(URLQueryItem(name: "pageToken", value: page)) }
                let response = try await get(url.url!, as: EventList.self)
                events.append(
                    contentsOf: (response.items ?? []).compactMap {
                        $0.calendarEvent(calendarID: calendar.id, calendarName: calendar.summary ?? calendar.id)
                    }.filter { !$0.userDeclined })
                page = response.nextPageToken
            } while page != nil
        }
        try await account.ensureSession(marker)
        return events.sorted { $0.startTime < $1.startTime }
    }
}
