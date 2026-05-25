import Foundation

enum CalendarProviderKind: String, CaseIterable, Codable, Identifiable {
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

enum RecurringEventEditScope: Equatable {
    case thisEvent
    case futureEvents
}

enum RecurringEventDeleteScope: Equatable {
    case thisEvent
    case allEvents
}
