import EventKit
import Foundation

final class EventKitService: @unchecked Sendable {
    enum AccessState: Equatable {
        case unknown
        case notDetermined
        case granted
        case denied
        case restricted
        case writeOnly
    }

    private let eventStore = EKEventStore()
    private var continuation: AsyncStream<Void>.Continuation?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func currentAccessState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess:
            return .granted
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unknown
        }
    }

    func requestAccess() async throws -> AccessState {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try await eventStore.requestFullAccessToEvents()
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try await eventStore.requestFullAccessToReminders()
        }
        return currentAccessState()
    }

    func requestReminderAccessIfNeeded() async throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .notDetermined else { return }
        _ = try await eventStore.requestFullAccessToReminders()
    }

    func fetchCalendars() -> [CalendarSource] {
        let eventCalendars = eventStore.calendars(for: .event).map { calendar in
            CalendarSource(
                id: Self.sourceID(for: calendar, kind: .event),
                provider: .iCloud,
                kind: .event,
                title: calendar.title,
                titleOverride: nil,
                colorHex: calendar.cgColor.hexRGB ?? "007AFF",
                colorOverrideHex: nil,
                isVisible: true,
                isWritable: calendar.allowsContentModifications
            )
        }

        let reminderCalendars = eventStore.calendars(for: .reminder).map { calendar in
            CalendarSource(
                id: Self.sourceID(for: calendar, kind: .reminder),
                provider: .iCloud,
                kind: .reminder,
                title: calendar.title,
                titleOverride: nil,
                colorHex: calendar.cgColor.hexRGB ?? "FF9500",
                colorOverrideHex: nil,
                isVisible: true,
                isWritable: calendar.allowsContentModifications
            )
        }

        return (eventCalendars + reminderCalendars)
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func fetchEvents(
        in interval: DateInterval,
        calendars: [CalendarSource],
        showsCompletedTasks: Bool
    ) async -> [CalendarEvent] {
        let eventIDs = Set(calendars.filter { $0.kind == .event }.map(\.id))
        let reminderIDs = Set(calendars.filter { $0.kind == .reminder }.map(\.id))

        var items: [CalendarEvent] = []

        if !eventIDs.isEmpty {
            let selectedEventCalendars = eventStore.calendars(for: .event).filter {
                eventIDs.contains(Self.sourceID(for: $0, kind: .event))
            }
            let predicate = eventStore.predicateForEvents(withStart: interval.start, end: interval.end, calendars: selectedEventCalendars)

            let events = eventStore.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .map { event -> CalendarEvent in
                    let invitees = event.attendees?.map { attendee in
                        String(attendee.url.absoluteString.trimmingPrefix("mailto:"))
                    } ?? []

                    return CalendarEvent(
                        id: event.eventIdentifier ?? UUID().uuidString,
                        calendarID: Self.sourceID(for: event.calendar, kind: .event),
                        kind: .event,
                        title: event.title?.isEmpty == false ? event.title : L.tr("Untitled", language: .system),
                        location: event.location,
                        notes: event.notes,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        isAllDay: event.isAllDay,
                        repeatOption: Self.repeatOption(for: event.recurrenceRules),
                        invitees: invitees,
                        attachmentURL: event.url?.absoluteString,
                        alertOption: EventAlertOption.option(for: event.alarms?.first?.relativeOffset),
                        visibility: .default,
                        availability: Self.availabilityOption(for: event.availability)
                    )
                }
            items.append(contentsOf: events)
        }

        if !reminderIDs.isEmpty {
            let selectedReminderCalendars = eventStore.calendars(for: .reminder).filter {
                reminderIDs.contains(Self.sourceID(for: $0, kind: .reminder))
            }
            let reminders = await fetchRemindersWithTimeout(
                in: interval,
                calendars: selectedReminderCalendars,
                showsCompletedTasks: showsCompletedTasks
            )
            items.append(contentsOf: reminders)
        }

        return items.sorted { $0.startDate < $1.startDate }
    }

    private func fetchRemindersWithTimeout(
        in interval: DateInterval,
        calendars: [EKCalendar],
        showsCompletedTasks: Bool
    ) async -> [CalendarEvent] {
        guard !calendars.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            let completion = ReminderFetchCompletion(continuation)
            let incompletePredicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: interval.start,
                ending: interval.end,
                calendars: calendars
            )
            let completedPredicate = eventStore.predicateForCompletedReminders(
                withCompletionDateStarting: interval.start,
                ending: interval.end,
                calendars: calendars
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                completion.resume(with: [])
            }

            eventStore.fetchReminders(matching: incompletePredicate) { incompleteReminders in
                guard showsCompletedTasks else {
                    completion.resume(with: Self.mappedReminders(incompleteReminders ?? [], in: interval))
                    return
                }

                self.eventStore.fetchReminders(matching: completedPredicate) { completedReminders in
                    let allReminders = (incompleteReminders ?? []) + (completedReminders ?? [])
                    completion.resume(with: Self.mappedReminders(allReminders, in: interval))
                }
            }
        }
    }

    private static func mappedReminders(_ reminders: [EKReminder], in interval: DateInterval) -> [CalendarEvent] {
        reminders
            .compactMap { reminder -> CalendarEvent? in
                guard let dueDate = reminder.dueDateComponents?.date else { return nil }
                let isAllDay = reminder.dueDateComponents?.hour == nil && reminder.dueDateComponents?.minute == nil
                let startDate = isAllDay ? Calendar.current.startOfDay(for: dueDate) : dueDate
                let endDate = isAllDay
                    ? Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate.addingTimeInterval(86400)
                    : dueDate.addingTimeInterval(60 * 30)
                let event = CalendarEvent(
                    id: reminder.calendarItemIdentifier,
                    calendarID: Self.sourceID(for: reminder.calendar, kind: .reminder),
                    kind: .reminder,
                    title: reminder.title.isEmpty ? L.tr("Untitled Reminder", language: .system) : reminder.title,
                    location: nil,
                    notes: reminder.notes,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    isCompleted: reminder.isCompleted
                )
                return event.intersects(interval) ? event : nil
            }
            .sorted { $0.startDate < $1.startDate }
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
    ) throws {
        guard let rawCalendarID = Self.rawCalendarID(from: calendarID),
              let calendar = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == rawCalendarID }) else {
            throw NSError(domain: "EventKitService", code: 1, userInfo: [NSLocalizedDescriptionKey: L.tr("Selected calendar could not be found.", language: .system)])
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title.isEmpty ? L.tr("Untitled", language: .system) : title
        event.startDate = startDate
        event.endDate = max(endDate, startDate.addingTimeInterval(60))
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        event.recurrenceRules = recurrenceRules(for: repeatOption)
        event.alarms = alertOption.offset.map { [EKAlarm(relativeOffset: $0)] }
        event.url = attachmentURL.flatMap(URL.init(string:))
        event.availability = ekAvailability(for: availability)

        try eventStore.save(event, span: .thisEvent)
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
    ) throws {
        guard let event = eventStore.event(withIdentifier: eventID) else {
            throw NSError(domain: "EventKitService", code: 2, userInfo: [NSLocalizedDescriptionKey: L.tr("Event could not be found.", language: .system)])
        }

        guard let rawCalendarID = Self.rawCalendarID(from: calendarID),
              let calendar = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == rawCalendarID }) else {
            throw NSError(domain: "EventKitService", code: 1, userInfo: [NSLocalizedDescriptionKey: L.tr("Selected calendar could not be found.", language: .system)])
        }

        event.calendar = calendar
        event.title = title.isEmpty ? L.tr("Untitled", language: .system) : title
        event.startDate = startDate
        event.endDate = max(endDate, startDate.addingTimeInterval(60))
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        event.recurrenceRules = recurrenceRules(for: repeatOption)
        event.alarms = alertOption.offset.map { [EKAlarm(relativeOffset: $0)] }
        event.url = attachmentURL.flatMap(URL.init(string:))
        event.availability = ekAvailability(for: availability)

        try eventStore.save(event, span: .thisEvent)
    }

    func deleteEvent(eventID: String) throws {
        guard let event = eventStore.event(withIdentifier: eventID) else {
            throw NSError(domain: "EventKitService", code: 2, userInfo: [NSLocalizedDescriptionKey: L.tr("Event could not be found.", language: .system)])
        }

        try eventStore.remove(event, span: .thisEvent)
    }

    func createReminder(
        title: String,
        dueDate: Date,
        isAllDay: Bool,
        calendarID: String,
        notes: String? = nil
    ) throws {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title.isEmpty ? L.tr("Untitled Reminder", language: .system) : title
        reminder.notes = notes
        reminder.dueDateComponents = Self.reminderDueDateComponents(from: dueDate, isAllDay: isAllDay)

        if let rawCalendarID = Self.rawCalendarID(from: calendarID),
           let calendar = eventStore.calendar(withIdentifier: rawCalendarID) {
            reminder.calendar = calendar
        } else if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
            reminder.calendar = defaultCalendar
        }

        try eventStore.save(reminder, commit: true)
    }

    func updateReminder(
        reminderID: String,
        title: String,
        dueDate: Date,
        isAllDay: Bool,
        calendarID: String,
        notes: String? = nil
    ) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw NSError(domain: "EventKitService", code: 3, userInfo: [NSLocalizedDescriptionKey: L.tr("Reminder could not be found.", language: .system)])
        }

        if let rawCalendarID = Self.rawCalendarID(from: calendarID),
           let calendar = eventStore.calendar(withIdentifier: rawCalendarID) {
            reminder.calendar = calendar
        }

        reminder.title = title.isEmpty ? L.tr("Untitled Reminder", language: .system) : title
        reminder.notes = notes
        reminder.dueDateComponents = Self.reminderDueDateComponents(from: dueDate, isAllDay: isAllDay)

        try eventStore.save(reminder, commit: true)
    }

    func setReminderCompletion(reminderID: String, isCompleted: Bool) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw NSError(domain: "EventKitService", code: 3, userInfo: [NSLocalizedDescriptionKey: L.tr("Reminder could not be found.", language: .system)])
        }

        reminder.isCompleted = isCompleted
        try eventStore.save(reminder, commit: true)
    }

    private static func sourceID(for calendar: EKCalendar, kind: CalendarSourceKind) -> String {
        "\(kind.rawValue):\(calendar.calendarIdentifier)"
    }

    private static func rawCalendarID(from sourceID: String) -> String? {
        sourceID.split(separator: ":", maxSplits: 1).last.map(String.init)
    }

    private static func reminderDueDateComponents(from date: Date, isAllDay: Bool) -> DateComponents {
        var components = Calendar.current.dateComponents(
            isAllDay ? [.calendar, .timeZone, .year, .month, .day] : [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: date
        )
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        return components
    }

    private static func repeatOption(for rules: [EKRecurrenceRule]?) -> EventRepeatOption {
        guard let rule = rules?.first else { return .never }
        let interval = max(1, rule.interval)
        let mappedFrequency: EventRepeatFrequency
        switch rule.frequency {
        case .daily: mappedFrequency = .daily
        case .weekly: mappedFrequency = .weekly
        case .monthly: mappedFrequency = .monthly
        case .yearly: mappedFrequency = .yearly
        @unknown default: return .never
        }

        if interval > 1 {
            return .custom(CustomRepeatRule(frequency: mappedFrequency, interval: interval))
        }

        switch mappedFrequency {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }

    private func recurrenceRules(for option: EventRepeatOption) -> [EKRecurrenceRule]? {
        let frequency: EKRecurrenceFrequency
        let interval: Int
        switch option {
        case .daily:
            frequency = .daily
            interval = 1
        case .weekly:
            frequency = .weekly
            interval = 1
        case .monthly:
            frequency = .monthly
            interval = 1
        case .yearly:
            frequency = .yearly
            interval = 1
        case .never:
            return nil
        case .custom(let rule):
            switch rule.frequency {
            case .daily: frequency = .daily
            case .weekly: frequency = .weekly
            case .monthly: frequency = .monthly
            case .yearly: frequency = .yearly
            }
            interval = max(1, rule.interval)
        }
        return [EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: daysOfTheWeek(for: option),
            daysOfTheMonth: daysOfTheMonth(for: option),
            monthsOfTheYear: monthsOfTheYear(for: option),
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )]
    }

    private func daysOfTheWeek(for option: EventRepeatOption) -> [EKRecurrenceDayOfWeek]? {
        guard case .custom(let rule) = option else { return nil }
        if rule.frequency == .weekly {
            let weekdays = rule.weekdays.isEmpty ? nil : rule.weekdays
            return weekdays?.compactMap { EKWeekday(rawValue: $0).map(EKRecurrenceDayOfWeek.init) }
        }
        if (rule.frequency == .monthly && rule.monthlyPattern == .nthWeekday) || (rule.frequency == .yearly && rule.yearlyUsesWeekdays) {
            guard let weekday = rule.nthDaySelector.weekdayNumber,
                  let ekWeekday = EKWeekday(rawValue: weekday) else {
                return nil
            }
            return [EKRecurrenceDayOfWeek(ekWeekday, weekNumber: rule.weekdayOrdinal.recurrenceValue)]
        }
        return nil
    }

    private func daysOfTheMonth(for option: EventRepeatOption) -> [NSNumber]? {
        guard case .custom(let rule) = option,
              rule.frequency == .monthly,
              rule.monthlyPattern == .eachDate,
              !rule.monthDays.isEmpty else {
            return nil
        }
        return rule.monthDays.map(NSNumber.init(value:))
    }

    private func monthsOfTheYear(for option: EventRepeatOption) -> [NSNumber]? {
        guard case .custom(let rule) = option,
              rule.frequency == .yearly,
              !rule.months.isEmpty else {
            return nil
        }
        return rule.months.map(NSNumber.init(value:))
    }

    private static func availabilityOption(for availability: EKEventAvailability) -> EventAvailabilityOption {
        switch availability {
        case .free: return .free
        case .tentative: return .tentative
        case .unavailable: return .unavailable
        case .busy, .notSupported: return .busy
        @unknown default: return .busy
        }
    }

    private func ekAvailability(for option: EventAvailabilityOption) -> EKEventAvailability {
        switch option {
        case .busy: return .busy
        case .free: return .free
        case .tentative: return .tentative
        case .unavailable: return .unavailable
        }
    }

    func observeChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    @objc
    private func handleStoreChanged() {
        continuation?.yield(())
    }
}

private final class ReminderFetchCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[CalendarEvent], Never>?

    init(_ continuation: CheckedContinuation<[CalendarEvent], Never>) {
        self.continuation = continuation
    }

    func resume(with events: [CalendarEvent]) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: events)
    }
}

private extension CGColor {
    var hexRGB: String? {
        guard let converted = converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3 else {
            return nil
        }

        let red = Int(round(components[0] * 255))
        let green = Int(round(components[1] * 255))
        let blue = Int(round(components[2] * 255))
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
