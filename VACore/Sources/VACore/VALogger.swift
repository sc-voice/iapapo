import Foundation
import os

/// Logs through `os.Logger` with a `[VA-<zid>]` prefix on every message.
/// The prefix uses the first 9 characters of a new ZUID for each log call, so each message gets its own prefix.
/// The prefix and the message are both `privacy: .public`, so they appear readable in Console.
/// Values interpolated into the message are public too. Use `log` for the shared instance.
public struct VALogger: Sendable {
  /// Shared instance for the app.
  public static let log = VALogger(subsystem: "net.sc-voice.VA", category: "VA")

  /// Prefix for one log call, such as `[VA-07XD8x1Ab]`. A new ZUID is made on each access.
  public static var prefix: String {
    let zid = String(ZUID.create().text.prefix(9))
    return "[VA-\(zid)]"
  }

  /// The wrapped `os.Logger`.
  let logger: Logger

  /// Creates a logger for a subsystem and category.
  /// - Parameters:
  ///   - subsystem: `os` subsystem, usually the bundle id.
  ///   - category: `os` category, such as `llm`.
  public init(subsystem: String, category: String) {
    self.logger = Logger(subsystem: subsystem, category: category)
  }

  /// Logs a debug message, with the prefix.
  /// - Parameter message: text to log.
  public func debug(_ message: String) {
    logger.debug("\(Self.prefix, privacy: .public) \(message, privacy: .public)")
  }

  /// Logs an info message, with the prefix.
  /// - Parameter message: text to log.
  public func info(_ message: String) {
    logger.info("\(Self.prefix, privacy: .public) \(message, privacy: .public)")
  }

  /// Logs a notice, with the prefix.
  /// - Parameter message: text to log.
  public func notice(_ message: String) {
    logger.notice("\(Self.prefix, privacy: .public) \(message, privacy: .public)")
  }

  /// Logs an error, with the prefix.
  /// - Parameter message: text to log.
  public func error(_ message: String) {
    logger.error("\(Self.prefix, privacy: .public) \(message, privacy: .public)")
  }

  /// Logs a fault, with the prefix.
  /// - Parameter message: text to log.
  public func fault(_ message: String) {
    logger.fault("\(Self.prefix, privacy: .public) \(message, privacy: .public)")
  }
}
