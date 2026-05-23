import Foundation

@Observable
@MainActor
final class CalendarViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var visibleYear: Int
    var scrollToTodayTrigger = 0
    var months: [CalendarMonth] = []
    var events: [CalendarEvent] = []
    var calendarSources: [CalendarSource] = []
    var accessState: EventKitService.AccessState = .notDetermined
    var loadState: LoadState = .idle

    private let calendar: Calendar
    private let eventKitService: EventKitService

    init(
        calendar: Calendar = .current,
        eventKitService: EventKitService = EventKitService()
    ) {
        self.calendar = calendar
        self.eventKitService = eventKitService
        visibleYear = calendar.component(.year, from: Date())
        months = Self.makeMonths(around: Date(), calendar: calendar)
        accessState = eventKitService.currentAccessState()
    }

    var hasConnectedCalendars: Bool {
        !calendarSources.isEmpty
    }

    var hasWritableCalendars: Bool {
        calendarSources.contains { $0.isWritable }
    }

    var statusMessage: String {
        switch accessState {
        case .notDetermined:
            return "Calendar access has not been requested yet."
        case .denied:
            return "Calendar access was denied. Enable access in Settings to load local calendars."
        case .restricted:
            return "Calendar access is restricted on this device."
        case .writeOnly:
            return "Only write-only calendar access is available, so existing events cannot be read."
        case .unknown:
            return "Calendar authorization state is unknown."
        case .granted:
            if calendarSources.isEmpty {
                return "No local calendars are currently available."
            }
            return "Connected to local calendars through EventKit."
        }
    }

    func loadInitialData() async {
        accessState = eventKitService.currentAccessState()

        if accessState == .granted {
            await reloadCalendarsAndEvents()
        }
    }

    func requestCalendarAccess() async {
        loadState = .loading

        do {
            accessState = try await eventKitService.requestAccess()

            if accessState == .granted {
                await reloadCalendarsAndEvents()
            } else {
                calendarSources = []
                events = []
                loadState = .loaded
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func updateVisibleYear(for month: CalendarMonth) {
        visibleYear = calendar.component(.year, from: month.date)
    }

    func events(on date: Date) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let interval = DateInterval(start: start, end: end)

        return events
            .filter { event in
                calendarSources.first(where: { $0.id == event.calendarID })?.isVisible == true && event.intersects(interval)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    func color(for event: CalendarEvent) -> String {
        calendarSources.first(where: { $0.id == event.calendarID })?.colorOverrideHex
            ?? calendarSources.first(where: { $0.id == event.calendarID })?.colorHex
            ?? "007AFF"
    }

    func day(for date: Date) -> CalendarDay {
        CalendarDay(
            date: calendar.startOfDay(for: date),
            monthDate: calendar.dateInterval(of: .month, for: date)?.start ?? date,
            isInDisplayedMonth: true
        )
    }

    private func reloadCalendarsAndEvents() async {
        loadState = .loading
        let calendars = eventKitService.fetchCalendars()
        let interval = visibleDateInterval()

        calendarSources = calendars
        events = eventKitService.fetchEvents(in: interval, calendars: calendars)
        loadState = .loaded
    }

    private func visibleDateInterval() -> DateInterval {
        guard let firstMonth = months.first?.date,
              let lastMonth = months.last?.date,
              let intervalEnd = calendar.date(byAdding: .month, value: 1, to: lastMonth) else {
            let now = Date()
            return DateInterval(start: now, duration: 60 * 60 * 24 * 365)
        }

        return DateInterval(start: firstMonth, end: intervalEnd)
    }

    private static func makeMonths(around date: Date, calendar: Calendar) -> [CalendarMonth] {
        (-18...18).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: date) else {
                return nil
            }

            return makeMonth(containing: month, calendar: calendar)
        }
    }

    private static func makeMonth(containing date: Date, calendar: Calendar) -> CalendarMonth? {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let firstGridDate = gridStart(for: monthInterval.start, calendar: calendar) else {
            return nil
        }

        let days = (0..<42).compactMap { offset -> CalendarDay? in
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: firstGridDate) else {
                return nil
            }

            return CalendarDay(
                date: dayDate,
                monthDate: monthInterval.start,
                isInDisplayedMonth: calendar.isDate(dayDate, equalTo: monthInterval.start, toGranularity: .month)
            )
        }

        let weeks = stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }

        return CalendarMonth(date: monthInterval.start, weeks: weeks)
    }

    private static func gridStart(for monthStart: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: monthStart)
        let firstWeekday = calendar.firstWeekday
        let daysBack = (weekday - firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysBack, to: monthStart)
    }
}
