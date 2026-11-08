import Foundation

func ML(_ key: String) -> String {
  LocalizationManager.shared.bundle.localizedString(forKey: key, value: nil, table: "MacUI")
}
