import Foundation

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
