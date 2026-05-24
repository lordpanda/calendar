import Foundation

struct CalendarPreferences: Codable, Equatable {
    var isVisible: Bool
    var colorOverrideHex: String?
    var titleOverride: String?
}

struct CalendarAppSettings: Codable, Equatable {
    var isICloudSyncEnabled: Bool
    var startOfWeek: StartOfWeekOption
    var showsWeekNumbers: Bool
    var showsCompletedTasks: Bool
    var monthContentScale: MonthContentScale
    var language: AppLanguage
    var usesDeviceTimeZone: Bool
    var defaultCalendarID: String?
    var calendarOrder: [String]
    var lastICloudSyncAt: Date?
    var lastGoogleSyncAt: Date?

    static let `default` = CalendarAppSettings(
        isICloudSyncEnabled: false,
        startOfWeek: .system,
        showsWeekNumbers: false,
        showsCompletedTasks: true,
        monthContentScale: .normal,
        language: .system,
        usesDeviceTimeZone: true,
        defaultCalendarID: nil,
        calendarOrder: [],
        lastICloudSyncAt: nil,
        lastGoogleSyncAt: nil
    )

    private enum CodingKeys: String, CodingKey {
        case isICloudSyncEnabled
        case startOfWeek
        case showsWeekNumbers
        case showsCompletedTasks
        case monthContentScale
        case language
        case usesDeviceTimeZone
        case defaultCalendarID
        case calendarOrder
        case lastICloudSyncAt
        case lastGoogleSyncAt
    }

    init(
        isICloudSyncEnabled: Bool,
        startOfWeek: StartOfWeekOption,
        showsWeekNumbers: Bool,
        showsCompletedTasks: Bool,
        monthContentScale: MonthContentScale,
        language: AppLanguage,
        usesDeviceTimeZone: Bool,
        defaultCalendarID: String?,
        calendarOrder: [String],
        lastICloudSyncAt: Date?,
        lastGoogleSyncAt: Date?
    ) {
        self.isICloudSyncEnabled = isICloudSyncEnabled
        self.startOfWeek = startOfWeek
        self.showsWeekNumbers = showsWeekNumbers
        self.showsCompletedTasks = showsCompletedTasks
        self.monthContentScale = monthContentScale
        self.language = language
        self.usesDeviceTimeZone = usesDeviceTimeZone
        self.defaultCalendarID = defaultCalendarID
        self.calendarOrder = calendarOrder
        self.lastICloudSyncAt = lastICloudSyncAt
        self.lastGoogleSyncAt = lastGoogleSyncAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isICloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isICloudSyncEnabled) ?? false
        startOfWeek = try container.decodeIfPresent(StartOfWeekOption.self, forKey: .startOfWeek) ?? .system
        showsWeekNumbers = try container.decodeIfPresent(Bool.self, forKey: .showsWeekNumbers) ?? false
        showsCompletedTasks = try container.decodeIfPresent(Bool.self, forKey: .showsCompletedTasks) ?? true
        monthContentScale = try container.decodeIfPresent(MonthContentScale.self, forKey: .monthContentScale) ?? .normal
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        usesDeviceTimeZone = try container.decodeIfPresent(Bool.self, forKey: .usesDeviceTimeZone) ?? true
        defaultCalendarID = try container.decodeIfPresent(String.self, forKey: .defaultCalendarID)
        calendarOrder = try container.decodeIfPresent([String].self, forKey: .calendarOrder) ?? []
        lastICloudSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastICloudSyncAt)
        lastGoogleSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastGoogleSyncAt)
    }
}

private struct CalendarPreferencesPayload: Codable {
    var calendars: [String: CalendarPreferences]
    var settings: CalendarAppSettings
    var cachedCalendarSources: [CalendarSource]?
    var cachedEvents: [CalendarEvent]?
}

@MainActor
final class CalendarPreferencesStore {
    private let defaults: UserDefaults
    private let key = "calendar.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> (
        preferences: [String: CalendarPreferences],
        settings: CalendarAppSettings,
        cachedCalendarSources: [CalendarSource],
        cachedEvents: [CalendarEvent]
    ) {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(CalendarPreferencesPayload.self, from: data) else {
            return ([:], .default, [], [])
        }

        return (
            decoded.calendars,
            decoded.settings,
            decoded.cachedCalendarSources ?? [],
            decoded.cachedEvents ?? []
        )
    }

    func save(
        preferences: [String: CalendarPreferences],
        settings: CalendarAppSettings,
        cachedCalendarSources: [CalendarSource],
        cachedEvents: [CalendarEvent]
    ) {
        let payload = CalendarPreferencesPayload(
            calendars: preferences,
            settings: settings,
            cachedCalendarSources: cachedCalendarSources,
            cachedEvents: cachedEvents
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }
}
