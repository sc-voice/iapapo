/// The app's tunable settings. Every consumer takes this one type and reads only
/// the properties it needs. Values are read on each use, so changes apply at once.
public protocol AppSettings: Sendable {
  /// dB the window level must rise above the ambient floor to open the wake gate.
  var ambientWakeDb: Float { get }
  /// Identifier of the voice the speaker uses, or nil for the default voice.
  var voiceIdentifier: String? { get }
  /// Seconds listening lasts without a signal above the wake margin, before the
  /// agent returns to idle.
  var listenTimeout: Double { get }
}

/// Settings with fixed values, for tests and for callers that take the defaults.
public struct FixedSettings: AppSettings {
  public let ambientWakeDb: Float
  public let voiceIdentifier: String?
  public let listenTimeout: Double

  /// - Parameters:
  ///   - ambientWakeDb: gate margin in dB. Defaults to `WakeMonitor.defaultAmbientWakeDb`.
  ///   - voiceIdentifier: voice identifier, or nil for the default voice.
  ///   - listenTimeout: seconds of listening without a signal. Defaults to `VAConfig.listenTimeout`.
  public init(
    ambientWakeDb: Float = WakeMonitor.defaultAmbientWakeDb,
    voiceIdentifier: String? = nil,
    listenTimeout: Double = VAConfig().listenTimeout
  ) {
    self.ambientWakeDb = ambientWakeDb
    self.voiceIdentifier = voiceIdentifier
    self.listenTimeout = listenTimeout
  }
}
