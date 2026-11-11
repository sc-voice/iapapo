import Foundation

/// One scored window of the wake-word stream.
public struct WakeScore: Sendable, Equatable {
  /// Model probability that the window contains the wake word.
  public let probability: Float
  /// Position of the window in the stream: window `k` covers samples `[4000k,
  /// 4000k + 14287)`.
  public let windowIndex: Int
  /// Stream time in seconds at which the window's last sample arrived.
  public let endSeconds: Double
}

/// Streams 48 kHz audio through the wake-word chain and emits one score per
/// completed window.
///
/// Feed it microphone buffers as they arrive, in any sizes. It keeps the
/// resampler, hop cutter and sliding
/// window between calls, so the scores match `WakeScorer.maxProbability` on the
/// same audio. It applies no
/// threshold: the caller decides what counts as a detection.
public struct WakeMonitor {
  private let scorer: WakeScorer
  private var resampler = Resampler48To16()
  private var cutter = HopCutter()
  private var window = SlidingWindow()
  /// Windows scored so far. The next window's index is this count.
  private var scored = 0

  /// - Parameter scorer: the scorer whose model and window probability the
  /// monitor uses.
  public init(scorer: WakeScorer) {
    self.scorer = scorer
  }

  /// Adds 48 kHz mono samples to the stream.
  /// - Parameter chunk: samples in order, of any size, such as a microphone
  /// buffer.
  /// - Returns: one score for each window this chunk completes, in order,
  /// possibly none.
  public mutating func process(_ chunk: [Float]) async throws -> [WakeScore] {
    var windows: [[Float]] = []
    for hop in cutter.process(resampler.process(chunk)) {
      windows += window.process(hop)
    }
    return try await score(windows)
  }

  /// Ends the stream, so the scores cover the whole input, as the test harness
  /// does.
  /// - Returns: the scores for windows completed by the flushed samples,
  /// possibly none.
  public mutating func flush() async throws -> [WakeScore] {
    var windows: [[Float]] = []
    for hop in cutter.process(resampler.flush()) {
      windows += window.process(hop)
    }
    windows += window.process(cutter.flush())
    return try await score(windows)
  }

  /// Scores windows in order and numbers them from the stream position.
  private mutating func score(_ windows: [[Float]]) async throws
    -> [WakeScore]
  {
    var scores: [WakeScore] = []
    for samples in windows {
      let probability = try await scorer.probability(of: samples)
      let end = Double(SlidingWindow.step * scored + SlidingWindow.length) /
        Double(LogMelFrontEnd.sampleRate)
      scores.append(WakeScore(
        probability: probability,
        windowIndex: scored,
        endSeconds: end,
      ))
      scored += 1
    }
    return scores
  }
}
