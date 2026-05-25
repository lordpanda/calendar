import Foundation

struct CalendarListResponse: Decodable {
    let nextPageToken: String?
    let items: [GoogleCalendarListItem]
}

struct GoogleCalendarListItem: Decodable {
    let id: String
    let summary: String
    let backgroundColor: String?
    let selected: Bool?
    let accessRole: String
}

struct EventListResponse: Decodable {
    let nextPageToken: String?
    let items: [GoogleCalendarEventItem]
}

struct GoogleCalendarEventItem: Decodable {
    let id: String
    let recurringEventId: String?
    let summary: String?
    let location: String?
    let description: String?
    let start: GoogleEventDateValue
    let end: GoogleEventDateValue
    let recurrence: [String]?
    let attendees: [GoogleEventAttendee]?
    let attachments: [GoogleEventAttachment]?
    let reminders: GoogleEventReminders?
    let visibility: String?
    let transparency: String?
}

struct GoogleTaskListsResponse: Decodable {
    let nextPageToken: String?
    let items: [GoogleTaskListItem]?
}

struct GoogleTaskListItem: Decodable {
    let id: String
    let title: String
}

struct GoogleTasksResponse: Decodable {
    let nextPageToken: String?
    let items: [GoogleTaskItem]?
}

struct GoogleUpdateTaskRequest: Encodable {
    let title: String?
    let notes: String?
    let due: String?
    let status: String?
}

struct GoogleTaskItem: Decodable {
    let id: String
    let title: String?
    let notes: String?
    let due: String?
    let status: String?
    let deleted: Bool?
    let hidden: Bool?

    var dueDate: Date? {
        guard let due else { return nil }
        return DateFormatter.googleTaskDue.date(from: due)
            ?? ISO8601DateFormatter.googleDate(from: due)
            ?? ISO8601DateFormatter.googleFractionalDate(from: due)
    }

    var dueIncludesTime: Bool {
        guard let dueDate else { return false }
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: dueDate)
        return components.hour != 0 || components.minute != 0 || components.second != 0
    }
}

struct GoogleEventDateValue: Decodable {
    let date: String?
    let dateTime: String?

    var resolvedDate: Date? {
        if let dateTime {
            return ISO8601DateFormatter.googleDate(from: dateTime)
                ?? ISO8601DateFormatter.googleFractionalDate(from: dateTime)
        }

        if let date {
            return DateFormatter.googleCalendarDay.date(from: date)
        }

        return nil
    }
}

struct GoogleCreateEventRequest: Encodable {
    let summary: String
    let location: String?
    let description: String?
    let start: GoogleCreateEventDateValue
    let end: GoogleCreateEventDateValue
    let recurrence: [String]?
    let attendees: [GoogleEventAttendee]
    let attachments: [GoogleEventAttachment]?
    let reminders: GoogleEventReminders
    let visibility: String?
    let transparency: String
}

struct GoogleCreateEventDateValue: Encodable {
    let date: String?
    let dateTime: String?
}

struct GoogleEventAttendee: Codable {
    let email: String
}

struct GoogleEventAttachment: Codable {
    let fileUrl: String
    let title: String?
}

struct GoogleEventReminders: Codable {
    struct Override: Codable {
        let method: String
        let minutes: Int
    }

    let useDefault: Bool
    let overrides: [Override]?

    var firstOverrideMinutes: Int? {
        overrides?.first?.minutes
    }
}

extension EventAlertOption {
    var googleOverrides: [GoogleEventReminders.Override]? {
        guard let offset, offset < 0 else {
            return nil
        }
        return [GoogleEventReminders.Override(method: "popup", minutes: Int(abs(offset) / 60))]
    }
}

extension EventVisibilityOption {
    var googleValue: String? {
        switch self {
        case .default: return nil
        case .publicEvent: return "public"
        case .privateEvent: return "private"
        case .confidential: return "confidential"
        }
    }

    static func googleValue(_ value: String) -> EventVisibilityOption? {
        switch value {
        case "public": return .publicEvent
        case "private": return .privateEvent
        case "confidential": return .confidential
        default: return .default
        }
    }
}

extension DateFormatter {
    static let googleCalendarDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let googleTaskDue: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}

extension ISO8601DateFormatter {
    static func googleDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func googleFractionalDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}


extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    var urlPathEncoded: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

extension GoogleCalendarService.AuthState {
    var isSignedIn: Bool {
        if case .signedIn = self {
            return true
        }

        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self {
            return true
        }

        return false
    }
}
