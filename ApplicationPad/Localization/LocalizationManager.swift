import Foundation
import LauncherCore

@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    var bundle: Bundle = .main
    var revision: Int = 0

    private init() {
        updateBundle()
    }

    func setLanguage(_ code: String) {
        LauncherSettings.language = code
        updateBundle()
        revision += 1
        updateCoreStrings()
    }

    func updateBundle() {
        let code = LauncherSettings.language
        if code == "system" {
            let preferred = Bundle.main.preferredLocalizations.first ?? "en"
            if let path = Bundle.main.path(forResource: preferred, ofType: "lproj"),
               let langBundle = Bundle(path: path) {
                bundle = langBundle
            } else {
                bundle = .main
            }
        } else if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
    }

    func updateCoreStrings() {
        LauncherCoreStrings.defaultFolderName = L("Folder")
        LauncherCoreStrings.settingsItemName = L("ApplicationPad Settings")
    }
}

func L(_ key: String) -> String {
    LocalizationManager.shared.bundle.localizedString(forKey: key, value: nil, table: nil)
}
