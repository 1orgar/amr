import Foundation

public enum AMRLocalization {
    public nonisolated(unsafe) static var overrideIsEnglishForTesting: Bool? = nil

    public static var isEnglish: Bool {
        if let override = overrideIsEnglishForTesting {
            return override
        }
        if let env = ProcessInfo.processInfo.environment["AMR_UI_LANG"]?.lowercased() {
            if env == "en" { return true }
            if env == "ru" { return false }
        }
        let lang = Locale.preferredLanguages.first?.lowercased() ?? "ru"
        return !lang.hasPrefix("ru")
    }

    @inline(__always)
    public static func tr(_ en: @autoclosure () -> String, _ ru: @autoclosure () -> String) -> String {
        isEnglish ? en() : ru()
    }
}
