import Foundation
import SwiftUI

enum CalendarProviderKind: String, CaseIterable, Identifiable {
    case iCloud
    case google

    var id: String { rawValue }
}

struct CalendarSource: Identifiable, Hashable {
    let id: String
    var provider: CalendarProviderKind
    var title: String
    var colorHex: String
    var colorOverrideHex: String?
    var isVisible: Bool
    var isWritable: Bool

    var displayColor: Color {
        Color(hex: colorOverrideHex ?? colorHex) ?? .accentColor
    }
}

struct CalendarEvent: Identifiable, Hashable {
    let id: String
    var calendarID: String
    var title: String
    var location: String?
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool

    func intersects(_ interval: DateInterval) -> Bool {
        DateInterval(start: startDate, end: endDate).intersects(interval)
    }
}

struct CalendarDay: Identifiable, Hashable {
    let date: Date
    let monthDate: Date
    let isInDisplayedMonth: Bool

    var id: Date { Calendar.current.startOfDay(for: date) }
}

struct CalendarMonth: Identifiable, Hashable {
    let date: Date
    let weeks: [[CalendarDay]]

    var id: Date { date }
}
