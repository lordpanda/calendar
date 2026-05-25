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
    private let tasksScope = "https://www.googleapis.com/auth/tasks"
    private let googleTaskListIDPrefix = "google-tasks:"

    var authState: AuthState {
        configureSignInIfPossible()

        if let user = GIDSignIn.sharedInstance.currentUser {
            return .signedIn(email: user.profile?.email ?? L.tr("Google Account", language: .system))
        }

        if clientID == nil {
            return .unavailable(L.tr("Google OAuth client ID is not configured.", language: .system))
        }

        if !hasCallbackURLScheme {
            return .unavailable(L.tr("Google callback URL scheme is not configured.", language: .system))
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
                userInfo: [NSLocalizedDescriptionKey: L.tr("Missing GIDClientID in Info.plist.", language: .system)]
            )
        }

        guard hasCallbackURLScheme else {
            throw NSError(
                domain: "GoogleCalendarService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: L.tr("Missing reversed Google client ID URL scheme in Info.plist.", language: .system)]
            )
        }

        configureSignInIfPossible()
        _ = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: [calendarScope, tasksScope]
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

        let calendarSources = items.map { item in
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

        let taskSources: [CalendarSource]
        do {
            taskSources = try await fetchTaskLists()
        } catch {
            print("Google Tasks lists fetch failed: \(error.localizedDescription)")
            taskSources = []
        }
        return calendarSources + taskSources
    }

    private func fetchPrimaryCalendar() async throws -> GoogleCalendarListItem {
        let data = try await authorizedRequest(
            path: "/users/me/calendarList/primary",
            queryItems: []
        )
        return try JSONDecoder().decode(GoogleCalendarListItem.self, from: data)
    }

    func fetchEvents(
        in interval: DateInterval,
        calendars: [CalendarSource],
        showsCompletedTasks: Bool = true
    ) async throws -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for calendar in calendars where calendar.isVisible && calendar.kind == .event {
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
                        recurringEventID: item.recurringEventId,
                        kind: .event,
                        title: item.summary?.isEmpty == false ? item.summary! : L.tr("Untitled", language: .system),
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

        do {
            let taskEvents = try await fetchTasks(
                in: interval,
                taskLists: calendars.filter { $0.isVisible && $0.kind == .reminder },
                showsCompletedTasks: showsCompletedTasks
            )
            result.append(contentsOf: taskEvents)
        } catch {
            print("Google Tasks fetch failed: \(error.localizedDescription)")
        }

        return result.sorted { $0.startDate < $1.startDate }
    }

    private func fetchTaskLists() async throws -> [CalendarSource] {
        var pageToken: String?
        var items: [GoogleTaskListItem] = []

        repeat {
            var queryItems = [
                URLQueryItem(name: "maxResults", value: "100")
            ]

            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let data = try await authorizedRequest(
                baseURLString: "https://tasks.googleapis.com/tasks/v1",
                path: "/users/@me/lists",
                queryItems: queryItems
            )

            let response = try JSONDecoder().decode(GoogleTaskListsResponse.self, from: data)
            items.append(contentsOf: response.items ?? [])
            pageToken = response.nextPageToken
        } while pageToken != nil

        return items.map { item in
            CalendarSource(
                id: taskSourceID(for: item.id),
                provider: .google,
                kind: .reminder,
                title: item.title.isEmpty ? L.tr("Google Tasks", language: .system) : item.title,
                titleOverride: nil,
                colorHex: "FF9500",
                colorOverrideHex: nil,
                isVisible: true,
                isWritable: true
            )
        }
    }

    private func fetchTasks(
        in interval: DateInterval,
        taskLists: [CalendarSource],
        showsCompletedTasks: Bool
    ) async throws -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for taskList in taskLists {
            guard let taskListID = taskListID(from: taskList.id) else { continue }
            var pageToken: String?

            repeat {
                var queryItems = [
                    URLQueryItem(name: "maxResults", value: "100"),
                    URLQueryItem(name: "showCompleted", value: showsCompletedTasks ? "true" : "false"),
                    URLQueryItem(name: "showDeleted", value: "false"),
                    URLQueryItem(name: "showHidden", value: "true"),
                    URLQueryItem(name: "showAssigned", value: "true"),
                    URLQueryItem(name: "dueMin", value: formatter.string(from: interval.start)),
                    URLQueryItem(name: "dueMax", value: formatter.string(from: interval.end))
                ]

                if let pageToken {
                    queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
                }

                let data = try await authorizedRequest(
                    baseURLString: "https://tasks.googleapis.com/tasks/v1",
                    path: "/lists/\(taskListID.urlPathEncoded)/tasks",
                    queryItems: queryItems
                )

                let response = try JSONDecoder().decode(GoogleTasksResponse.self, from: data)
                result.append(contentsOf: (response.items ?? []).compactMap { item in
                    guard item.deleted != true,
                          showsCompletedTasks || item.status != "completed",
                          let dueDate = item.dueDate else {
                        return nil
                    }

                    let isAllDay = !item.dueIncludesTime
                    let startDate = isAllDay ? Calendar.current.startOfDay(for: dueDate) : dueDate
                    let endDate = isAllDay
                        ? Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86400)
                        : dueDate.addingTimeInterval(60 * 30)

                    return CalendarEvent(
                        id: "google-task:\(taskListID):\(item.id)",
                        calendarID: taskList.id,
                        recurringEventID: nil,
                        kind: .reminder,
                        title: item.title?.isEmpty == false ? item.title! : L.tr("Untitled Reminder", language: .system),
                        location: nil,
                        notes: item.notes,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: isAllDay,
                        isCompleted: item.status == "completed"
                    )
                })
                pageToken = response.nextPageToken
            } while pageToken != nil
        }

        return result
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
            summary: title.isEmpty ? L.tr("Untitled", language: .system) : title,
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
        availability: EventAvailabilityOption = .busy,
        recurringEventID: String? = nil,
        editScope: RecurringEventEditScope = .thisEvent
    ) async throws {
        let targetEventID = editScope == .futureEvents ? (recurringEventID ?? eventID) : eventID
        let payload = GoogleCreateEventRequest(
            summary: title.isEmpty ? L.tr("Untitled", language: .system) : title,
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
            path: "/calendars/\(calendarID.urlPathEncoded)/events/\(targetEventID.urlPathEncoded)",
            queryItems: attachmentURL == nil ? [] : [URLQueryItem(name: "supportsAttachments", value: "true")],
            method: "PUT",
            body: body
        )
    }

    func deleteEvent(
        eventID: String,
        calendarID: String,
        recurringEventID: String? = nil,
        deleteScope: RecurringEventDeleteScope = .thisEvent
    ) async throws {
        let targetEventID = deleteScope == .allEvents ? (recurringEventID ?? eventID) : eventID
        _ = try await authorizedRequest(
            path: "/calendars/\(calendarID.urlPathEncoded)/events/\(targetEventID.urlPathEncoded)",
            queryItems: [],
            method: "DELETE"
        )
    }

    func createTask(
        title: String,
        dueDate: Date,
        isAllDay: Bool,
        calendarID: String,
        notes: String? = nil
    ) async throws {
        guard let taskListID = taskListID(from: calendarID) else {
            throw NSError(domain: "GoogleCalendarService", code: 5, userInfo: [NSLocalizedDescriptionKey: L.tr("Google task could not be found.", language: .system)])
        }

        let payload = GoogleUpdateTaskRequest(
            title: title.isEmpty ? L.tr("Untitled Reminder", language: .system) : title,
            notes: notes,
            due: googleTaskDueString(from: dueDate, isAllDay: isAllDay),
            status: nil
        )
        let body = try JSONEncoder().encode(payload)

        _ = try await authorizedRequest(
            baseURLString: "https://tasks.googleapis.com/tasks/v1",
            path: "/lists/\(taskListID.urlPathEncoded)/tasks",
            queryItems: [],
            method: "POST",
            body: body
        )
    }

    func updateTask(
        eventID: String,
        title: String,
        dueDate: Date,
        isAllDay: Bool,
        notes: String? = nil
    ) async throws {
        let identity = try taskIdentity(fromEventID: eventID)
        let payload = GoogleUpdateTaskRequest(
            title: title.isEmpty ? L.tr("Untitled Reminder", language: .system) : title,
            notes: notes,
            due: googleTaskDueString(from: dueDate, isAllDay: isAllDay),
            status: nil
        )
        let body = try JSONEncoder().encode(payload)

        _ = try await authorizedRequest(
            baseURLString: "https://tasks.googleapis.com/tasks/v1",
            path: "/lists/\(identity.taskListID.urlPathEncoded)/tasks/\(identity.taskID.urlPathEncoded)",
            queryItems: [],
            method: "PATCH",
            body: body
        )
    }

    func setTaskCompletion(eventID: String, isCompleted: Bool) async throws {
        let identity = try taskIdentity(fromEventID: eventID)
        let payload = GoogleUpdateTaskRequest(
            title: nil,
            notes: nil,
            due: nil,
            status: isCompleted ? "completed" : "needsAction"
        )
        let body = try JSONEncoder().encode(payload)

        _ = try await authorizedRequest(
            baseURLString: "https://tasks.googleapis.com/tasks/v1",
            path: "/lists/\(identity.taskListID.urlPathEncoded)/tasks/\(identity.taskID.urlPathEncoded)",
            queryItems: [],
            method: "PATCH",
            body: body
        )
    }

    func deleteTask(eventID: String) async throws {
        let identity = try taskIdentity(fromEventID: eventID)

        _ = try await authorizedRequest(
            baseURLString: "https://tasks.googleapis.com/tasks/v1",
            path: "/lists/\(identity.taskListID.urlPathEncoded)/tasks/\(identity.taskID.urlPathEncoded)",
            queryItems: [],
            method: "DELETE"
        )
    }

    private func authorizedRequest(
        baseURLString: String = "https://www.googleapis.com/calendar/v3",
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw NSError(domain: "GoogleCalendarService", code: 2, userInfo: [NSLocalizedDescriptionKey: L.tr("No signed-in Google user.", language: .system)])
        }

        let user = try await currentUser.refreshTokensIfNeeded()

        var components = URLComponents(string: "\(baseURLString)\(path)")!
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
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? L.tr("Google Calendar API request failed.", language: .system)]
            )
        }

        return data
    }

    private func taskSourceID(for taskListID: String) -> String {
        googleTaskListIDPrefix + taskListID
    }

    private func taskListID(from sourceID: String) -> String? {
        guard sourceID.hasPrefix(googleTaskListIDPrefix) else { return nil }
        return String(sourceID.dropFirst(googleTaskListIDPrefix.count))
    }

    private func taskIdentity(fromEventID eventID: String) throws -> (taskListID: String, taskID: String) {
        let prefix = "google-task:"
        guard eventID.hasPrefix(prefix) else {
            throw NSError(domain: "GoogleCalendarService", code: 5, userInfo: [NSLocalizedDescriptionKey: L.tr("Google task could not be found.", language: .system)])
        }

        let value = eventID.dropFirst(prefix.count)
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw NSError(domain: "GoogleCalendarService", code: 5, userInfo: [NSLocalizedDescriptionKey: L.tr("Google task could not be found.", language: .system)])
        }

        return (parts[0], parts[1])
    }

    private func googleTaskDueString(from date: Date, isAllDay: Bool) -> String {
        let dueDate = isAllDay ? Calendar.current.startOfDay(for: date) : date
        return makeGoogleDateTimeFormatter().string(from: dueDate)
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
