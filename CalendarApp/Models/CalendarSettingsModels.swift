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

enum EventTitleMosaic {
    static func title(for event: CalendarEvent, language: AppLanguage) -> String {
        let names = dessertNames(for: language)
        guard !names.isEmpty else { return event.title }

        let key = "\(event.calendarID)|\(event.id)"
        return names[Int(stableHash(for: key) % UInt64(names.count))]
    }

    private static func dessertNames(for language: AppLanguage) -> [String] {
        let languageCode = language.locale.language.languageCode?.identifier
        if language == .korean || (language == .system && languageCode == "ko") {
            return [
                "마카롱", "티라미수", "푸딩", "브라우니", "치즈케이크", "몽블랑",
                "에클레어", "타르트", "파르페", "스콘", "젤라토", "카눌레",
                "와플", "크루아상", "롤케이크", "도넛", "마들렌", "바스크케이크"
            ]
        }

        return [
            "Macaron", "Tiramisu", "Pudding", "Brownie", "Cheesecake", "Mont Blanc",
            "Eclair", "Tart", "Parfait", "Scone", "Gelato", "Cannele",
            "Waffle", "Croissant", "Roll Cake", "Donut", "Madeleine", "Basque Cake"
        ]
    }

    private static func stableHash(for string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
