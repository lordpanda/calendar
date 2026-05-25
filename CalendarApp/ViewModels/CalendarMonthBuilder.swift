import Foundation

enum CalendarMonthBuilder {
    static func configuredCalendar(base: Calendar, startOfWeek: StartOfWeekOption) -> Calendar {
        var configured = base
        if let firstWeekday = startOfWeek.firstWeekdayOverride {
            configured.firstWeekday = firstWeekday
        }
        return configured
    }

    static func makeMonths(around date: Date, radius: Int, calendar: Calendar) -> [CalendarMonth] {
        (-radius...radius).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: date) else {
                return nil
            }

            return makeMonth(containing: month, calendar: calendar)
        }
    }

    private static func makeMonth(containing date: Date, calendar: Calendar) -> CalendarMonth? {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let firstGridDate = gridStart(for: monthInterval.start, calendar: calendar),
              let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastGridDate = gridEnd(for: lastDayOfMonth, calendar: calendar) else {
            return nil
        }

        let gridDayCount = (calendar.dateComponents([.day], from: firstGridDate, to: lastGridDate).day ?? 0) + 1
        let visibleDayCount = max(gridDayCount, 42)
        let days = (0..<visibleDayCount).compactMap { offset -> CalendarDay? in
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

        let weekNumbers = weeks.compactMap { week in
            week.first.map { calendar.component(.weekOfYear, from: $0.date) }
        }

        return CalendarMonth(date: monthInterval.start, weeks: weeks, weekNumbers: weekNumbers)
    }

    private static func gridStart(for monthStart: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: monthStart)
        let firstWeekday = calendar.firstWeekday
        let daysBack = (weekday - firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysBack, to: monthStart)
    }

    private static func gridEnd(for monthEnd: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: monthEnd)
        let firstWeekday = calendar.firstWeekday
        let lastWeekday = ((firstWeekday + 5) % 7) + 1
        let daysForward = (lastWeekday - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysForward, to: monthEnd)
    }
}

enum CalendarSyncDescriptionFormatter {
    static func string(for date: Date?, language: AppLanguage) -> String {
        guard let date else { return L.tr("Never", language: language) }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
