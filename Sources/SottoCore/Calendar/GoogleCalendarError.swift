import Foundation

public enum GoogleCalendarError: LocalizedError, Sendable {
    case message(String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .http(401): return "Google Calendar authorization expired. Disconnect and connect again."
        case .http(403):
            return "Google Calendar denied access. Check the Calendar API and OAuth configuration in Google Cloud."
        case .http(let status): return "Google Calendar returned an error (\(status)). Try again."
        }
    }
}

extension GoogleDriveResponse {
    func requireCalendarSuccess() throws {
        guard (200..<300).contains(status) else { throw GoogleCalendarError.http(status) }
    }
}
