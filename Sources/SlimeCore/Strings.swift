import Foundation

/// UI language: Chinese when the user's first preferred language is Chinese, English otherwise.
enum Lang: Equatable {
    case en, zh

    /// `SLIMEY_LANG=en|zh` overrides the system language.
    static var system: Lang {
        switch ProcessInfo.processInfo.environment["SLIMEY_LANG"] {
        case "zh": return .zh
        case "en": return .en
        default: return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
        }
    }

    var locale: Locale { Locale(identifier: self == .zh ? "zh_CN" : "en_US") }
}

enum L10n {
    static var lang = Lang.system

    /// Picks the string for the current language.
    static func t(_ en: String, _ zh: String) -> String { lang == .zh ? zh : en }
}
