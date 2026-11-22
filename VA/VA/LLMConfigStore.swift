import Foundation
import Security
import VACore

/// Saves LLM configs. The configs go to UserDefaults as one JSON value, and each API key goes to the
/// Keychain under its config's `zuid`, encrypted and kept on this device only.
enum LLMConfigStore {
  /// UserDefaults key for the configs, encoded as `[zuid: LLMConfig]`.
  static let configsKey = "llmConfigs"
  /// UserDefaults key for the active config's `zuid`. Written by the Settings picker.
  static let activeKey = "activeLLMZUID"
  /// Keychain service that groups the LLM API keys.
  private static let service = "com.iapapo.va.llm"

  /// The saved configs, with each API key filled in from the Keychain.
  /// - Returns: the configs keyed by `zuid`, or an empty dictionary when none are saved.
  static func load() -> [String: LLMConfig] {
    guard let data = UserDefaults.standard.data(forKey: configsKey),
      var configs = try? JSONDecoder().decode([String: LLMConfig].self, from: data)
    else { return [:] }
    for zuid in configs.keys {
      configs[zuid]?.apiKey = readAPIKey(for: zuid)
    }
    return configs
  }

  /// Writes the configs to UserDefaults. API keys are not included; use `setAPIKey` for those.
  /// - Parameter configs: the configs keyed by `zuid`.
  static func save(_ configs: [String: LLMConfig]) {
    guard let data = try? JSONEncoder().encode(configs) else { return }
    UserDefaults.standard.set(data, forKey: configsKey)
  }

  /// Stores the API key for a config in the Keychain, replacing any earlier key. A nil or empty key deletes it.
  /// - Parameters:
  ///   - key: the bearer key, or nil to remove it.
  ///   - zuid: the config the key belongs to.
  static func setAPIKey(_ key: String?, for zuid: String) {
    SecItemDelete(keychainQuery(for: zuid) as CFDictionary)
    guard let key, !key.isEmpty, let data = key.data(using: .utf8) else { return }
    var item = keychainQuery(for: zuid)
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
  }

  /// Removes a config's API key from the Keychain. Call this when the config is deleted.
  /// - Parameter zuid: the config whose key to remove.
  static func removeAPIKey(for zuid: String) {
    SecItemDelete(keychainQuery(for: zuid) as CFDictionary)
  }

  /// Reads a config's API key from the Keychain.
  /// - Parameter zuid: the config whose key to read.
  /// - Returns: the key, or nil when none is stored.
  static func readAPIKey(for zuid: String) -> String? {
    var query = keychainQuery(for: zuid)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// The Keychain query that identifies one config's key.
  private static func keychainQuery(for zuid: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: zuid,
    ]
  }
}
