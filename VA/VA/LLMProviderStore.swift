import Foundation
import Security
import VACore

/// Saves LLM providers and their defaults. Providers go to UserDefaults as one JSON value, without API keys.
/// Each API key goes to the Keychain under its provider's `zuid`, kept on this device only.
enum LLMProviderStore {
  /// UserDefaults key for the providers, encoded as `[LLMProvider]`.
  static let providersKey = "llmProviders"
  /// UserDefaults key for the default provider's `id`. Pi's name for this setting.
  static let defaultProviderKey = "defaultProvider"
  /// UserDefaults key for the default model's `id`. Pi's name for this setting.
  static let defaultModelKey = "defaultModel"
  /// Keychain service that groups the provider API keys.
  private static let service = "com.iapapo.va.llm"

  /// The saved providers, with each API key filled in from the Keychain.
  /// - Returns: the providers, or an empty array when none are saved.
  static func load() -> [LLMProvider] {
    guard let data = UserDefaults.standard.data(forKey: providersKey) else {
      // First run: nothing saved yet, so offer the default provider. It is saved only when the list is next saved.
      return [.appleFoundationModels]
    }
    guard var providers = try? JSONDecoder().decode([LLMProvider].self, from: data)
    else { return [] }
    for index in providers.indices {
      providers[index].apiKey = readAPIKey(for: providers[index].id)
    }
    return providers
  }

  /// Writes the providers to UserDefaults. API keys are not included; use `setAPIKey` for those.
  /// - Parameter providers: the providers to save.
  static func save(_ providers: [LLMProvider]) {
    guard let data = try? JSONEncoder().encode(providers) else { return }
    UserDefaults.standard.set(data, forKey: providersKey)
  }

  /// Stores a provider's API key in the Keychain, replacing any earlier key. A nil or empty key deletes it.
  /// - Parameters:
  ///   - key: the bearer key, or nil to remove it.
  ///   - zuid: the provider's `id` (its `zuid` text).
  static func setAPIKey(_ key: String?, for zuid: String) {
    SecItemDelete(keychainQuery(for: zuid) as CFDictionary)
    guard let key, !key.isEmpty, let data = key.data(using: .utf8) else { return }
    var item = keychainQuery(for: zuid)
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    assert(status == errSecSuccess, "Keychain add failed: \(status)")
  }

  /// Removes a provider's API key from the Keychain. Call this when the provider is deleted.
  /// - Parameter zuid: the provider's `id` (its `zuid` text).
  static func removeAPIKey(for zuid: String) {
    SecItemDelete(keychainQuery(for: zuid) as CFDictionary)
  }

  /// Reads a provider's API key from the Keychain.
  /// - Parameter zuid: the provider's `id` (its `zuid` text).
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

  /// Sets the default provider when none is set, and the default model to the provider's first model when none is set.
  /// Called after each save, so the first provider becomes the default and its first fetched model follows.
  /// - Parameter provider: the provider that was just saved or fetched.
  static func adoptDefaults(for provider: LLMProvider) {
    let defaults = UserDefaults.standard
    if (defaults.string(forKey: defaultProviderKey) ?? "").isEmpty {
      defaults.set(provider.id, forKey: defaultProviderKey)
    }
    guard defaults.string(forKey: defaultProviderKey) == provider.id,
      (defaults.string(forKey: defaultModelKey) ?? "").isEmpty,
      let first = provider.models.first
    else { return }
    defaults.set(first.id, forKey: defaultModelKey)
  }

  /// Clears both defaults when they point at the given provider. Call this when that provider is deleted.
  /// - Parameter id: the provider's `id` (its `zuid` text).
  static func forgetDefaults(ifProvider id: String) {
    let defaults = UserDefaults.standard
    guard defaults.string(forKey: defaultProviderKey) == id else { return }
    defaults.removeObject(forKey: defaultProviderKey)
    defaults.removeObject(forKey: defaultModelKey)
  }

  /// The Keychain query that identifies one provider's key.
  private static func keychainQuery(for zuid: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: zuid,
    ]
  }
}
