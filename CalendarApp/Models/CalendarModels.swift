import Foundation
import SwiftUI

enum StartOfWeekOption: String, CaseIterable, Codable, Identifiable {
    case system
    case sunday
    case monday
    case saturday

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .system:
            return L.tr("System Default", language: language)
        case .sunday:
            return L.tr("Sunday", language: language)
        case .monday:
            return L.tr("Monday", language: language)
        case .saturday:
            return L.tr("Saturday", language: language)
        }
    }

    var firstWeekdayOverride: Int? {
        switch self {
        case .system:
            return nil
        case .sunday:
            return 1
        case .monday:
            return 2
        case .saturday:
            return 7
        }
    }
}

enum MonthContentScale: String, CaseIterable, Codable, Identifiable {
    case normal
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:
            return "100%"
        case .large:
            return "125%"
        case .extraLarge:
            return "150%"
        }
    }

    var factor: CGFloat {
        switch self {
        case .normal:
            return 1.0
        case .large:
            return 1.25
        case .extraLarge:
            return 1.5
        }
    }
}

enum CalendarProviderKind: String, CaseIterable, Identifiable {
    case iCloud
    case google

    var id: String { rawValue }
}

enum CalendarSourceKind: String, Codable, Hashable {
    case event
    case reminder
}

enum CalendarItemKind: String, Codable, Hashable {
    case event
    case reminder
}

enum EventRepeatFrequency: String, CaseIterable, Codable, Hashable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .daily: return L.tr("Day", language: language)
        case .weekly: return L.tr("Week", language: language)
        case .monthly: return L.tr("Month", language: language)
        case .yearly: return L.tr("Year", language: language)
        }
    }

    func pluralTitle(language: AppLanguage) -> String {
        switch self {
        case .daily: return L.tr("days", language: language)
        case .weekly: return L.tr("weeks", language: language)
        case .monthly: return L.tr("months", language: language)
        case .yearly: return L.tr("years", language: language)
        }
    }

    func intervalUnitTitle(interval: Int, language: AppLanguage) -> String {
        interval == 1 ? title(language: language).lowercased() : pluralTitle(language: language)
    }

    func summarySentence(interval: Int, language: AppLanguage) -> String {
        let interval = max(1, interval)
        if interval == 1 {
            switch self {
            case .daily: return L.tr("This event repeats every day.", language: language)
            case .weekly: return L.tr("This event repeats every week.", language: language)
            case .monthly: return L.tr("This event repeats every month.", language: language)
            case .yearly: return L.tr("This event repeats every year.", language: language)
            }
        }
        return L.tr("This event repeats every %d %@.", language: language, interval, pluralTitle(language: language))
    }
}

struct CustomRepeatRule: Codable, Hashable {
    var frequency: EventRepeatFrequency
    var interval: Int
    var weekdays: [Int]
    var monthDays: [Int]
    var months: [Int]
    var monthlyPattern: CustomRepeatMonthlyPattern
    var yearlyUsesWeekdays: Bool
    var weekdayOrdinal: CustomRepeatWeekdayOrdinal
    var nthDaySelector: CustomRepeatNthDaySelector

    init(
        frequency: EventRepeatFrequency = .weekly,
        interval: Int = 1,
        weekdays: [Int] = [],
        monthDays: [Int] = [],
        months: [Int] = [],
        monthlyPattern: CustomRepeatMonthlyPattern = .eachDate,
        yearlyUsesWeekdays: Bool = false,
        weekdayOrdinal: CustomRepeatWeekdayOrdinal = .first,
        nthDaySelector: CustomRepeatNthDaySelector = .monday
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.monthDays = monthDays
        self.months = months
        self.monthlyPattern = monthlyPattern
        self.yearlyUsesWeekdays = yearlyUsesWeekdays
        self.weekdayOrdinal = weekdayOrdinal
        self.nthDaySelector = nthDaySelector
    }
}

enum CustomRepeatMonthlyPattern: String, Codable, Hashable, CaseIterable {
    case eachDate
    case nthWeekday
}

enum CustomRepeatWeekdayOrdinal: String, Codable, Hashable, CaseIterable {
    case first
    case second
    case third
    case fourth
    case fifth
    case nextToLast
    case last

    func title(language: AppLanguage) -> String {
        switch self {
        case .first: return L.tr("first", language: language)
        case .second: return L.tr("second", language: language)
        case .third: return L.tr("third", language: language)
        case .fourth: return L.tr("fourth", language: language)
        case .fifth: return L.tr("fifth", language: language)
        case .nextToLast: return L.tr("next to last", language: language)
        case .last: return L.tr("last", language: language)
        }
    }

    var recurrenceValue: Int {
        switch self {
        case .first: return 1
        case .second: return 2
        case .third: return 3
        case .fourth: return 4
        case .fifth: return 5
        case .nextToLast: return -2
        case .last: return -1
        }
    }
}

enum CustomRepeatNthDaySelector: String, Codable, Hashable, CaseIterable {
    case day
    case weekday
    case weekendDay
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    func title(language: AppLanguage) -> String {
        switch self {
        case .day: return L.tr("day", language: language)
        case .weekday: return L.tr("weekday", language: language)
        case .weekendDay: return L.tr("weekend day", language: language)
        case .sunday: return L.tr("Sunday", language: language)
        case .monday: return L.tr("Monday", language: language)
        case .tuesday: return L.tr("Tuesday", language: language)
        case .wednesday: return L.tr("Wednesday", language: language)
        case .thursday: return L.tr("Thursday", language: language)
        case .friday: return L.tr("Friday", language: language)
        case .saturday: return L.tr("Saturday", language: language)
        }
    }

    var weekdayNumber: Int? {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        case .day, .weekday, .weekendDay: return nil
        }
    }
}

enum EventRepeatOption: Codable, Hashable, Identifiable {
    case never
    case daily
    case weekly
    case monthly
    case yearly
    case custom(CustomRepeatRule)

    var id: String {
        switch self {
        case .never: return "never"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        case .custom(let rule): return "custom-\(rule.frequency.rawValue)-\(rule.interval)"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .never: return L.tr("Never", language: language)
        case .daily: return L.tr("Every Day", language: language)
        case .weekly: return L.tr("Every Week", language: language)
        case .monthly: return L.tr("Every Month", language: language)
        case .yearly: return L.tr("Every Year", language: language)
        case .custom(let rule):
            let interval = max(1, rule.interval)
            if interval == 1 {
                return L.tr("Every %@", language: language, rule.frequency.title(language: language))
            }
            return L.tr("Every %d %@", language: language, interval, rule.frequency.pluralTitle(language: language))
        }
    }

    static let presetOptions: [EventRepeatOption] = [.never, .daily, .weekly, .monthly, .yearly]

    private enum CodingKeys: String, CodingKey {
        case kind
        case frequency
        case interval
    }

    init(from decoder: Decoder) throws {
        if let rawValue = try? decoder.singleValueContainer().decode(String.self) {
            switch rawValue {
            case "never": self = .never
            case "daily": self = .daily
            case "weekly": self = .weekly
            case "monthly": self = .monthly
            case "yearly": self = .yearly
            default: self = .never
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "never": self = .never
        case "daily": self = .daily
        case "weekly": self = .weekly
        case "monthly": self = .monthly
        case "yearly": self = .yearly
        case "custom":
            let frequency = try container.decode(EventRepeatFrequency.self, forKey: .frequency)
            let interval = try container.decode(Int.self, forKey: .interval)
            self = .custom(CustomRepeatRule(frequency: frequency, interval: interval))
        default:
            self = .never
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .never:
            try container.encode("never", forKey: .kind)
        case .daily:
            try container.encode("daily", forKey: .kind)
        case .weekly:
            try container.encode("weekly", forKey: .kind)
        case .monthly:
            try container.encode("monthly", forKey: .kind)
        case .yearly:
            try container.encode("yearly", forKey: .kind)
        case .custom(let rule):
            try container.encode("custom", forKey: .kind)
            try container.encode(rule.frequency, forKey: .frequency)
            try container.encode(rule.interval, forKey: .interval)
        }
    }
}

enum EventAlertOption: String, CaseIterable, Codable, Hashable, Identifiable {
    case none
    case atTime
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .none: return L.tr("None", language: language)
        case .atTime: return L.tr("At time of event", language: language)
        case .fiveMinutes: return L.tr("5 minutes before", language: language)
        case .fifteenMinutes: return L.tr("15 minutes before", language: language)
        case .thirtyMinutes: return L.tr("30 minutes before", language: language)
        case .oneHour: return L.tr("1 hour before", language: language)
        case .oneDay: return L.tr("1 day before", language: language)
        }
    }

    var offset: TimeInterval? {
        switch self {
        case .none: return nil
        case .atTime: return 0
        case .fiveMinutes: return -5 * 60
        case .fifteenMinutes: return -15 * 60
        case .thirtyMinutes: return -30 * 60
        case .oneHour: return -60 * 60
        case .oneDay: return -24 * 60 * 60
        }
    }

    static func option(for offset: TimeInterval?) -> EventAlertOption {
        guard let offset else { return .none }
        return allCases.min { lhs, rhs in
            abs((lhs.offset ?? .greatestFiniteMagnitude) - offset) < abs((rhs.offset ?? .greatestFiniteMagnitude) - offset)
        } ?? .none
    }
}

enum EventVisibilityOption: String, CaseIterable, Codable, Hashable, Identifiable {
    case `default`
    case publicEvent
    case privateEvent
    case confidential

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .default: return L.tr("Default", language: language)
        case .publicEvent: return L.tr("Public", language: language)
        case .privateEvent: return L.tr("Private", language: language)
        case .confidential: return L.tr("Confidential", language: language)
        }
    }
}

enum EventAvailabilityOption: String, CaseIterable, Codable, Hashable, Identifiable {
    case busy
    case free
    case tentative
    case unavailable

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .busy: return L.tr("Busy", language: language)
        case .free: return L.tr("Free", language: language)
        case .tentative: return L.tr("Tentative", language: language)
        case .unavailable: return L.tr("Unavailable", language: language)
        }
    }
}

struct CalendarSource: Identifiable, Hashable {
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

struct CalendarEvent: Identifiable, Hashable {
    let id: String
    var calendarID: String
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
