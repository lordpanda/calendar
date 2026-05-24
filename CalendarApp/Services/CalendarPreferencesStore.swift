import Foundation

struct CalendarPreferences: Codable, Equatable {
    var isVisible: Bool
    var colorOverrideHex: String?
    var titleOverride: String?
}

struct CalendarAppSettings: Codable, Equatable {
    var startOfWeek: StartOfWeekOption
    var showsWeekNumbers: Bool
    var defaultCalendarID: String?
    var calendarOrder: [String]
    var lastICloudSyncAt: Date?
    var lastGoogleSyncAt: Date?

    static let `default` = CalendarAppSettings(
        startOfWeek: .system,
        showsWeekNumbers: false,
        defaultCalendarID: nil,
        calendarOrder: [],
        lastICloudSyncAt: nil,
        lastGoogleSyncAt: nil
    )

    private enum CodingKeys: String, CodingKey {
        case startOfWeek
        case showsWeekNumbers
        case defaultCalendarID
        case calendarOrder
        case lastICloudSyncAt
        case lastGoogleSyncAt
    }

    init(
        startOfWeek: StartOfWeekOption,
        showsWeekNumbers: Bool,
        defaultCalendarID: String?,
        calendarOrder: [String],
        lastICloudSyncAt: Date?,
        lastGoogleSyncAt: Date?
    ) {
        self.startOfWeek = startOfWeek
        self.showsWeekNumbers = showsWeekNumbers
        self.defaultCalendarID = defaultCalendarID
        self.calendarOrder = calendarOrder
        self.lastICloudSyncAt = lastICloudSyncAt
        self.lastGoogleSyncAt = lastGoogleSyncAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startOfWeek = try container.decodeIfPresent(StartOfWeekOption.self, forKey: .startOfWeek) ?? .system
        showsWeekNumbers = try container.decodeIfPresent(Bool.self, forKey: .showsWeekNumbers) ?? false
        defaultCalendarID = try container.decodeIfPresent(String.self, forKey: .defaultCalendarID)
        calendarOrder = try container.decodeIfPresent([String].self, forKey: .calendarOrder) ?? []
        lastICloudSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastICloudSyncAt)
        lastGoogleSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastGoogleSyncAt)
    }
}

private struct CalendarPreferencesPayload: Codable {
    var calendars: [String: CalendarPreferences]
    var settings: CalendarAppSettings
}

@MainActor
final class CalendarPreferencesStore {
    private let defaults: UserDefaults
    private let key = "calendar.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> (preferences: [String: CalendarPreferences], settings: CalendarAppSettings) {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(CalendarPreferencesPayload.self, from: data) else {
            return ([:], .default)
        }

        return (decoded.calendars, decoded.settings)
    }

    func save(preferences: [String: CalendarPreferences], settings: CalendarAppSettings) {
        let payload = CalendarPreferencesPayload(calendars: preferences, settings: settings)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }
}
