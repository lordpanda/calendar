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
