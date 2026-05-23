import Foundation

enum SampleCalendarData {
    static let sources: [CalendarSource] = [
        CalendarSource(id: "icloud-personal", provider: .iCloud, title: "Personal", colorHex: "007AFF", colorOverrideHex: nil, isVisible: true, isWritable: true),
        CalendarSource(id: "google-work", provider: .google, title: "Work", colorHex: "34A853", colorOverrideHex: nil, isVisible: true, isWritable: true),
        CalendarSource(id: "google-family", provider: .google, title: "Family", colorHex: "F9AB00", colorOverrideHex: nil, isVisible: true, isWritable: true)
    ]

    static func events(calendars: [CalendarSource], calendar: Calendar) -> [CalendarEvent] {
        let now = Date()
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now

        return [
            event("Design review", calendarID: calendars[1].id, dayOffset: 2, hour: 10, duration: 1.5, from: monthStart, calendar: calendar),
            event("Lunch with Mina", calendarID: calendars[0].id, dayOffset: 2, hour: 12, duration: 1, from: monthStart, calendar: calendar),
            event("Product sync", calendarID: calendars[1].id, dayOffset: 7, hour: 9, duration: 2, from: monthStart, calendar: calendar),
            event("Family dinner", calendarID: calendars[2].id, dayOffset: 12, hour: 18, duration: 2, from: monthStart, calendar: calendar),
            event("Gym", calendarID: calendars[0].id, dayOffset: 12, hour: 7, duration: 1, from: monthStart, calendar: calendar),
            event("Sprint planning", calendarID: calendars[1].id, dayOffset: 16, hour: 14, duration: 1.5, from: monthStart, calendar: calendar),
            event("Trip hold", calendarID: calendars[2].id, dayOffset: 22, hour: 0, duration: 24, isAllDay: true, from: monthStart, calendar: calendar)
        ]
    }

    private static func event(
        _ title: String,
        calendarID: String,
        dayOffset: Int,
        hour: Int,
        duration: Double,
        isAllDay: Bool = false,
        from monthStart: Date,
        calendar: Calendar
    ) -> CalendarEvent {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: monthStart) ?? monthStart
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(byAdding: .minute, value: Int(duration * 60), to: start) ?? start

        return CalendarEvent(
            id: UUID().uuidString,
            calendarID: calendarID,
            title: title,
            location: nil,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay
        )
    }
}
