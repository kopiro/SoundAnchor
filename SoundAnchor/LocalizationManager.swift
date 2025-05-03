import Foundation

class LocalizationManager {
    static let shared = LocalizationManager()
    
    private var currentLanguage: String {
        get {
            // Get system language
            let systemLanguage: String
            if #available(macOS 13.0, *) {
                systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            } else {
                systemLanguage = Locale.current.languageCode ?? "en"
            }
            // Check if we support this language
            return getAvailableLanguages().contains(systemLanguage) ? systemLanguage : "en"
        }
    }
    
    private var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main
        }
        return bundle
    }
    
    func localizedString(for key: String) -> String {
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
    
    func getCurrentLanguage() -> String {
        return currentLanguage
    }
    
    func getAvailableLanguages() -> [String] {
        return ["en", "it", "pt", "es", "fr", "de", "ja", "ko", "ru", "zh-Hans", "zh-Hant", "nl", "sv", "pl", "tr"]
    }
}

// Convenience extension for String
extension String {
    var localized: String {
        return LocalizationManager.shared.localizedString(for: self)
    }
} 