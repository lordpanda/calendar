import Foundation
import SwiftUI

struct CalendarSource: Codable, Identifiable, Hashable {
    let id: String
    var provider: CalendarProviderKind
    var kind: CalendarSourceKind
    var title: String
    var titleOverride: String?
    var colorHex: String
    var colorOverrideHex: String?
    var isVisible: Bool
    var isWritable: Bool

    var displayColor: Color {
        Color(hex: colorOverrideHex ?? colorHex) ?? .accentColor
    }

    var displayTitle: String {
        let trimmed = titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? title : trimmed
    }
}

struct CalendarEvent: Codable, Identifiable, Hashable {
    let id: String
    var calendarID: String
    var recurringEventID: String?
    var kind: CalendarItemKind
    var title: String
    var location: String?
    var notes: String?
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var repeatOption: EventRepeatOption = .never
    var invitees: [String] = []
    var attachmentURL: String?
    var alertOption: EventAlertOption = .none
    var visibility: EventVisibilityOption = .default
    var availability: EventAvailabilityOption = .busy
    var isCompleted: Bool = false

    var isRecurring: Bool {
        repeatOption != .never || recurringEventID != nil
    }

    func intersects(_ interval: DateInterval) -> Bool {
        startDate < interval.end && endDate > interval.start
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
    let weekNumbers: [Int]

    var id: Date { date }
}
