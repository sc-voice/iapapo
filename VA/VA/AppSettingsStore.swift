import Foundation
import VACore

/// The app's settings in UserDefaults, where the Settings tab's `@AppStorage`
/// writes them. The keys are defined here once.
struct UserDefaultsSettings: AppSettings {
  /// UserDefaults key for the ambient wake margin in dB.
  static let ambientWakeDbKey = "ambientWakeDb"
  /// UserDefaults key for the speaker's voice identifier.
  static let voiceIdentifierKey = "voiceIdentifier"
  /// UserDefaults key for the listen timeout, in seconds.
  static let listenTimeoutKey = "listenTimeout"
  /// Ambient wake margin in dB when Settings has no value.
  static let defaultAmbientWakeDb: Double = 5
  /// Listen timeout in seconds when Settings has no value: one minute.
  static let defaultListenTimeout: Double = 60

  var ambientWakeDb: Float {
    Float(UserDefaults.standard.object(forKey: Self.ambientWakeDbKey) as? Double
      ?? Self.defaultAmbientWakeDb)
  }

  var voiceIdentifier: String? {
    UserDefaults.standard.string(forKey: Self.voiceIdentifierKey)
  }

  var listenTimeout: Double {
    UserDefaults.standard.object(forKey: Self.listenTimeoutKey) as? Double
      ?? Self.defaultListenTimeout
  }
}
