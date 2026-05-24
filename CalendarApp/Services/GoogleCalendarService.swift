import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class GoogleCalendarService {
    enum AuthState: Equatable {
        case signedOut
        case signedIn(email: String)
        case unavailable(String)
    }

    private let calendarScope = "https://www.googleapis.com/auth/calendar"

    var authState: AuthState {
        configureSignInIfPossible()

        if let user = GIDSignIn.sharedInstance.currentUser {
            return .signedIn(email: user.profile?.email ?? "Google Account")
        }

        if clientID == nil {
            return .unavailable("Google OAuth client ID is not configured.")
        }

        if !hasCallbackURLScheme {
            return .unavailable("Google callback URL scheme is not configured.")
        }

        return .signedOut
    }

    func restorePreviousSignInIfPossible() async {
        configureSignInIfPossible()
        guard clientID != nil, hasCallbackURLScheme else { return }
        do {
            _ = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        } catch {
            // Ignore restore failures and stay signed out.
        }
    }

    func signIn(presentingViewController: UIViewController) async throws {
        guard clientID != nil else {
            throw NSError(
                domain: "GoogleCalendarService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing GIDClientID in Info.plist."]
            )
        }

        guard hasCallbackURLScheme else {
            throw NSError(
                domain: "GoogleCalendarService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Missing reversed Google client ID URL scheme in Info.plist."]
            )
        }

        configureSignInIfPossible()
        _ = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: [calendarScope]
        )
    }

    private func configureSignInIfPossible() {
        guard let clientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func fetchCalendars() async throws -> [CalendarSource] {
        var pageToken: String?
        var items: [GoogleCalendarListItem] = []

        repeat {
            var queryItems = [
                URLQueryItem(name: "maxResults", value: "250")
            ]

            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let data = try await authorizedRequest(
                path: "/users/me/calendarList",
                queryItems: queryItems
            )

            let response = try JSONDecoder().decode(CalendarListResponse.self, from: data)
            items.append(contentsOf: response.items)
            pageToken = response.nextPageToken
        } while pageToken != nil

        if let primary = try? await fetchPrimaryCalendar(),
           !items.contains(where: { $0.id == primary.id }) {
            items.insert(primary, at: 0)
        }

        return items.map { item in
            CalendarSource(
                id: item.id,
                provider: .google,
                kind: .event,
                title: item.summary,
                titleOverride: nil,
                colorHex: (item.backgroundColor ?? "#4285F4").trimmingPrefix("#"),
                colorOverrideHex: nil,
                isVisible: item.selected ?? true,
                isWritable: item.accessRole != "reader" && item.accessRole != "freeBusyReader"
            )
        }
    }

    private func fetchPrimaryCalendar() async throws -> GoogleCalendarListItem {
        let data = try await authorizedRequest(
            path: "/users/me/calendarList/primary",
            queryItems: []
        )
        return try JSONDecoder().decode(GoogleCalendarListItem.self, from: data)
    }

    func fetchEvents(in interval: DateInterval, calendars: [CalendarSource]) async throws -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for calendar in calendars where calendar.isVisible {
            var pageToken: String?

            repeat {
                var queryItems = [
                    URLQueryItem(name: "singleEvents", value: "true"),
                    URLQueryItem(name: "orderBy", value: "startTime"),
                    URLQueryItem(name: "maxResults", value: "2500"),
                    URLQueryItem(name: "timeMin", value: formatter.string(from: interval.start)),
                    URLQueryItem(name: "timeMax", value: formatter.string(from: interval.end))
                ]

                if let pageToken {
                    queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
                }

                let data = try await authorizedRequest(
                    path: "/calendars/\(calendar.id.urlPathEncoded)/events",
                    queryItems: queryItems
                )

                let response = try JSONDecoder().decode(EventListResponse.self, from: data)
                result.append(contentsOf: response.items.compactMap { item in
                    guard let start = item.start.resolvedDate,
                          let end = item.end.resolvedDate else {
                        return nil
                    }

                    return CalendarEvent(
                        id: item.id,
                        calendarID: calendar.id,
                        kind: .event,
                        title: item.summary?.isEmpty == false ? item.summary! : "Untitled",
                        location: item.location,
                        notes: item.description,
                        startDate: start,
                        endDate: end,
                        isAllDay: item.start.date != nil,
                        repeatOption: item.recurrence?.first.flatMap(Self.repeatOption) ?? .never,
                        invitees: item.attendees?.compactMap(\.email) ?? [],
                        attachmentURL: item.attachments?.first?.fileUrl,
                        alertOption: EventAlertOption.option(for: item.reminders?.firstOverrideMinutes.map { TimeInterval(-$0 * 60) }),
                        visibility: item.visibility.flatMap(EventVisibilityOption.googleValue) ?? .default,
                        availability: item.transparency == "transparent" ? .free : .busy
                    )
                })
                pageToken = response.nextPageToken
            } while pageToken != nil
        }

        return result.sorted { $0.startDate < $1.startDate }
    }

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String,
        location: String? = nil,
        notes: String? = nil,
        repeatOption: EventRepeatOption = .never,
        invitees: [String] = [],
        attachmentURL: String? = nil,
        alertOption: EventAlertOption = .none,
        visibility: EventVisibilityOption = .default,
        availability: EventAvailabilityOption = .busy
    ) async throws {
        let payload = GoogleCreateEventRequest(
            summary: title.isEmpty ? "Untitled" : title,
            location: location,
            description: notes,
            start: .init(date: isAllDay ? DateFormatter.googleCalendarDay.string(from: startDate) : nil,
                         dateTime: isAllDay ? nil : makeGoogleDateTimeFormatter().string(from: startDate)),
            end: .init(
                date: isAllDay ? DateFormatter.googleCalendarDay.string(from: allDayEndDate(from: startDate, endDate: endDate)) : nil,
                dateTime: isAllDay ? nil : makeGoogleDateTimeFormatter().string(from: max(endDate, startDate.addingTimeInterval(60)))
            ),
            recurrence: recurrence(for: repeatOption),
            attendees: invitees.map { GoogleEventAttendee(email: $0) },
            attachments: attachmentURL.flatMap { URL(string: $0) == nil ? nil : [GoogleEventAttachment(fileUrl: $0, title: URL(string: $0)?.lastPathComponent)] },
            reminders: GoogleEventReminders(useDefault: alertOption == .none, overrides: alertOption.googleOverrides),
            visibility: visibility.googleValue,
            transparency: availability == .free ? "transparent" : "opaque"
        )

        let body = try JSONEncoder().encode(payload)
        _ = try await authorizedRequest(
            path: "/calendars/\(calendarID.urlPathEncoded)/events",
            queryItems: attachmentURL == nil ? [] : [URLQueryItem(name: "supportsAttachments", value: "true")],
            method: "POST",
            body: body
        )
    }

    func updateEvent(
        eventID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String,
        location: String? = nil,
        notes: String? = nil,
        repeatOption: EventRepeatOption = .never,
        invitees: [String] = [],
        attachmentURL: String? = nil,
        alertOption: EventAlertOption = .none,
        visibility: EventVisibilityOption = .default,
        availability: EventAvailabilityOption = .busy
    ) async throws {
        let payload = GoogleCreateEventRequest(
            summary: title.isEmpty ? "Untitled" : title,
            location: location,
            description: notes,
            start: .init(date: isAllDay ? DateFormatter.googleCalendarDay.string(from: startDate) : nil,
                         dateTime: isAllDay ? nil : makeGoogleDateTimeFormatter().string(from: startDate)),
            end: .init(
                date: isAllDay ? DateFormatter.googleCalendarDay.string(from: allDayEndDate(from: startDate, endDate: endDate)) : nil,
                dateTime: isAllDay ? nil : makeGoogleDateTimeFormatter().string(from: max(endDate, startDate.addingTimeInterval(60)))
            ),
            recurrence: recurrence(for: repeatOption),
            attendees: invitees.map { GoogleEventAttendee(email: $0) },
            attachments: attachmentURL.flatMap { URL(string: $0) == nil ? nil : [GoogleEventAttachment(fileUrl: $0, title: URL(string: $0)?.lastPathComponent)] },
            reminders: GoogleEventReminders(useDefault: alertOption == .none, overrides: alertOption.googleOverrides),
            visibility: visibility.googleValue,
            transparency: availability == .free ? "transparent" : "opaque"
        )

        let body = try JSONEncoder().encode(payload)
        _ = try await authorizedRequest(
            path: "/calendars/\(calendarID.urlPathEncoded)/events/\(eventID.urlPathEncoded)",
            queryItems: attachmentURL == nil ? [] : [URLQueryItem(name: "supportsAttachments", value: "true")],
            method: "PUT",
            body: body
        )
    }

    func deleteEvent(eventID: String, calendarID: String) async throws {
        _ = try await authorizedRequest(
            path: "/calendars/\(calendarID.urlPathEncoded)/events/\(eventID.urlPathEncoded)",
            queryItems: [],
            method: "DELETE"
        )
    }

    private func authorizedRequest(
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw NSError(domain: "GoogleCalendarService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No signed-in Google user."])
        }

        let user = try await currentUser.refreshTokensIfNeeded()

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3\(path)")!
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(user.accessToken.tokenString)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "GoogleCalendarService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Google Calendar API request failed."]
            )
        }

        return data
    }

    private var clientID: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
           !value.isEmpty {
            return value
        }

        return bundledOAuthClientValue(for: "CLIENT_ID")
    }

    private var serverClientID: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String,
           !value.isEmpty {
            return value
        }

        return bundledOAuthClientValue(for: "SERVER_CLIENT_ID")
    }

    private var hasCallbackURLScheme: Bool {
        guard let reversedClientID else { return false }
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []

        return urlTypes.contains { item in
            let schemes = item["CFBundleURLSchemes"] as? [String] ?? []
            return schemes.contains(reversedClientID)
        }
    }

    private var reversedClientID: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GIDReversedClientID") as? String,
           !value.isEmpty {
            return value
        }

        if let value = bundledOAuthClientValue(for: "REVERSED_CLIENT_ID") {
            return value
        }

        guard let clientID else { return nil }
        return clientID
            .split(separator: ".")
            .reversed()
            .joined(separator: ".")
    }

    private func bundledOAuthClientValue(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "GoogleOAuthClient", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private func allDayEndDate(from startDate: Date, endDate: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let startDay = calendar.startOfDay(for: startDate)
        let clampedEnd = max(endDate, startDate)
        let daySpan = calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: clampedEnd)).day ?? 0
        return calendar.date(byAdding: .day, value: max(daySpan + 1, 1), to: startDay) ?? startDay.addingTimeInterval(86400)
    }

    private func makeGoogleDateTimeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }

    private func recurrence(for option: EventRepeatOption) -> [String]? {
        switch option {
        case .never:
            return nil
        case .daily:
            return ["RRULE:FREQ=DAILY"]
        case .weekly:
            return ["RRULE:FREQ=WEEKLY"]
        case .monthly:
            return ["RRULE:FREQ=MONTHLY"]
        case .yearly:
            return ["RRULE:FREQ=YEARLY"]
        case .custom(let rule):
            let frequency: String
            switch rule.frequency {
            case .daily: frequency = "DAILY"
            case .weekly: frequency = "WEEKLY"
            case .monthly: frequency = "MONTHLY"
            case .yearly: frequency = "YEARLY"
            }
            var parts = ["FREQ=\(frequency)", "INTERVAL=\(max(1, rule.interval))"]
            if rule.frequency == .weekly, !rule.weekdays.isEmpty {
                parts.append("BYDAY=\(rule.weekdays.compactMap(googleWeekday).joined(separator: ","))")
            }
            if rule.frequency == .monthly, rule.monthlyPattern == .eachDate, !rule.monthDays.isEmpty {
                parts.append("BYMONTHDAY=\(rule.monthDays.map(String.init).joined(separator: ","))")
            }
            if rule.frequency == .monthly, rule.monthlyPattern == .nthWeekday,
               let weekday = rule.nthDaySelector.weekdayNumber,
               let weekdayText = googleWeekday(weekday) {
                parts.append("BYDAY=\(rule.weekdayOrdinal.recurrenceValue)\(weekdayText)")
            }
            if rule.frequency == .yearly, !rule.months.isEmpty {
                parts.append("BYMONTH=\(rule.months.map(String.init).joined(separator: ","))")
            }
            if rule.frequency == .yearly, rule.yearlyUsesWeekdays,
               let weekday = rule.nthDaySelector.weekdayNumber,
               let weekdayText = googleWeekday(weekday) {
                parts.append("BYDAY=\(rule.weekdayOrdinal.recurrenceValue)\(weekdayText)")
            }
            return ["RRULE:\(parts.joined(separator: ";"))"]
        }
    }

    private func googleWeekday(_ weekday: Int) -> String? {
        switch weekday {
        case 1: return "SU"
        case 2: return "MO"
        case 3: return "TU"
        case 4: return "WE"
        case 5: return "TH"
        case 6: return "FR"
        case 7: return "SA"
        default: return nil
        }
    }

    private static func repeatOption(for rule: String) -> EventRepeatOption? {
        let interval = intervalValue(in: rule)
        if rule.contains("FREQ=DAILY") {
            return interval > 1 ? .custom(CustomRepeatRule(frequency: .daily, interval: interval)) : .daily
        }
        if rule.contains("FREQ=WEEKLY") {
            return interval > 1 ? .custom(CustomRepeatRule(frequency: .weekly, interval: interval)) : .weekly
        }
        if rule.contains("FREQ=MONTHLY") {
            return interval > 1 ? .custom(CustomRepeatRule(frequency: .monthly, interval: interval)) : .monthly
        }
        if rule.contains("FREQ=YEARLY") {
            return interval > 1 ? .custom(CustomRepeatRule(frequency: .yearly, interval: interval)) : .yearly
        }
        return nil
    }

    private static func intervalValue(in rule: String) -> Int {
        let parts = rule.split(separator: ";")
        guard let intervalPart = parts.first(where: { $0.hasPrefix("INTERVAL=") }),
              let value = Int(String(intervalPart).replacingOccurrences(of: "INTERVAL=", with: "")) else {
            return 1
        }
        return max(1, value)
    }
}

private struct CalendarListResponse: Decodable {
    let nextPageToken: String?
    let items: [GoogleCalendarListItem]
}

private struct GoogleCalendarListItem: Decodable {
    let id: String
    let summary: String
    let backgroundColor: String?
    let selected: Bool?
    let accessRole: String
}

private struct EventListResponse: Decodable {
    let nextPageToken: String?
    let items: [GoogleCalendarEventItem]
}

private struct GoogleCalendarEventItem: Decodable {
    let id: String
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

private struct GoogleEventDateValue: Decodable {
    let date: String?
    let dateTime: String?

    var resolvedDate: Date? {
        if let dateTime {
            return ISO8601DateFormatter().date(from: dateTime)
        }

        if let date {
            return DateFormatter.googleCalendarDay.date(from: date)
        }

        return nil
    }
}

private struct GoogleCreateEventRequest: Encodable {
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

private struct GoogleCreateEventDateValue: Encodable {
    let date: String?
    let dateTime: String?
}

private struct GoogleEventAttendee: Codable {
    let email: String
}

private struct GoogleEventAttachment: Codable {
    let fileUrl: String
    let title: String?
}

private struct GoogleEventReminders: Codable {
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

private extension EventAlertOption {
    var googleOverrides: [GoogleEventReminders.Override]? {
        guard let offset, offset < 0 else {
            return nil
        }
        return [GoogleEventReminders.Override(method: "popup", minutes: Int(abs(offset) / 60))]
    }
}

private extension EventVisibilityOption {
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

private extension DateFormatter {
    static let googleCalendarDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}


private extension String {
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
