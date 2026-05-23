import Foundation

@Observable
final class CalendarViewModel {
    var visibleYear: Int
    var scrollToTodayTrigger = 0
    var months: [CalendarMonth] = []
    var events: [CalendarEvent] = []
    var calendarSources: [CalendarSource] = []

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        visibleYear = calendar.component(.year, from: Date())
        calendarSources = SampleCalendarData.sources
        events = SampleCalendarData.events(calendars: calendarSources, calendar: calendar)
        months = Self.makeMonths(around: Date(), calendar: calendar)
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
