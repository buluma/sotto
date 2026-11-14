import Foundation

/// Google Calendar event payload. Instances are converted at fetch time and
/// are not stored as a separate calendar cache.
struct GoogleCalendarEvent: Decodable, Sendable {
    struct EventDate: Decodable, Sendable {
        let dateTime: String?
        let date: String?
    }

    struct Attendee: Decodable, Sendable {
        let email: String?
        let displayName: String?
        let responseStatus: String?
        let isSelf: Bool?

        enum CodingKeys: String, CodingKey {
            case email, displayName, responseStatus
            case isSelf = "self"
        }

        var participantStatus: EventParticipant.ParticipantStatus {
            switch responseStatus {
            case "accepted": return .accepted
            case "declined": return .declined
            case "tentative": return .tentative
            case "needsAction": return .pending
            default: return .unknown
            }
        }
    }

    struct Organizer: Decodable, Sendable {
        let email: String?
        let displayName: String?
    }

    struct ConferenceData: Decodable, Sendable {
        struct EntryPoint: Decodable, Sendable {
            let entryPointType: String?
            let uri: String?
        }
        let entryPoints: [EntryPoint]?
    }

    let id: String
    let status: String?
    let summary: String?
    let start: EventDate?
    let end: EventDate?
    let location: String?
    let description: String?
    let hangoutLink: String?
    let recurringEventId: String?
    let attendees: [Attendee]?
    let organizer: Organizer?
    let conferenceData: ConferenceData?

    func calendarEvent(calendarID: String, calendarName: String) -> CalendarEvent? {
        guard status != "cancelled", let startValue = start?.dateTime,
            let endValue = end?.dateTime
        else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalStart = formatter.date(from: startValue)
        let fractionalEnd = formatter.date(from: endValue)
        formatter.formatOptions = [.withInternetDateTime]
        guard let startDate = fractionalStart ?? formatter.date(from: startValue),
            let endDate = fractionalEnd ?? formatter.date(from: endValue), endDate > startDate
        else { return nil }
        let sourceID = "google:\(calendarID)"
        return CalendarEvent(
            id: "\(sourceID):\(id)", title: summary ?? "Untitled",
            startTime: startDate, endTime: endDate, location: location,
            meetUrl: MeetingLinkParser().extractMeetingUrl(
                location: location, notes: description,
                url: hangoutLink ?? conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri),
            participants: (attendees ?? []).filter { $0.isSelf != true }.map {
                EventParticipant(email: $0.email, name: $0.displayName, status: $0.participantStatus)
            },
            organizer: organizer.map { EventParticipant(email: $0.email, name: $0.displayName) },
            calendarName: calendarName, calendarIdentifier: sourceID,
            userStatus: attendees?.first(where: { $0.isSelf == true })?.participantStatus,
            externalId: recurringEventId.map { "\(sourceID):\($0)" },
            isRecurring: recurringEventId != nil)
    }
}
