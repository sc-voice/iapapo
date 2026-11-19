/// Decides which wake scores produce a `VAEvent`.
public protocol WakeEventRule: Sendable {
  /// The event this score produces, or nil. Called once per score, in order.
  mutating func event(for score: WakeScore) -> VAEvent?
}

/// Fires `.sensed(.wakeup)` when `runLength` wake-word strides arrive in a row,
/// at most once per `cooldown` seconds of stream time.
public struct StrideRunRule: WakeEventRule {
  /// Strides in a row that make one wake word.
  public let runLength: Int
  /// Minimum stream seconds between wake events.
  public let cooldown: Double
  private var run = 0
  private var lastFiredAt: Double?

  /// - Parameters:
  ///   - runLength: strides in a row that make one wake word.
  ///   - cooldown: minimum stream seconds between wake events.
  public init(runLength: Int = 4, cooldown: Double = 2) {
    self.runLength = runLength
    self.cooldown = cooldown
  }

  public mutating func event(for score: WakeScore) -> VAEvent? {
    guard score.wakeWord else {
      run = 0
      return nil
    }
    run += 1
    guard run == runLength else { return nil }
    if let last = lastFiredAt, score.endSeconds - last < cooldown { return nil }
    lastFiredAt = score.endSeconds
    return .sensed(.wakeup)
  }
}
