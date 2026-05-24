import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case english
    case korean

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .korean:
            return Locale(identifier: "ko-KR")
        }
    }

    var bundle: Bundle {
        guard self != .system,
              let path = Bundle.main.path(forResource: resourceCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private var resourceCode: String {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"
        case .english:
            return "en"
        case .korean:
            return "ko"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .system:
            return L.tr("System Language", language: language)
        case .english:
            return L.tr("English", language: language)
        case .korean:
            return L.tr("Korean", language: language)
        }
    }
}

enum L {
    static func tr(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        let format = language.bundle.localizedString(forKey: key, value: key, table: nil)
        guard arguments.isEmpty == false else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .system
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}
