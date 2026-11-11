import Foundation

/// Cuts a 16 kHz stream into the scoring windows the model was trained on.
///
/// Window `k` is the samples `[4000k, 4000k + 14287)` of the stream, which is
/// the grid `train.py` scores.
/// A window is emitted as soon as the stream has reached its last sample.
/// Windows are not padded at the end,
/// so a window that the stream never completes is never emitted, as in
/// training.
/// Only the samples the next window needs are kept.
public struct SlidingWindow: Sendable {
  /// Samples per window at 16 kHz (0.893 s).
  public static let length = 14287
  /// Samples between window starts at 16 kHz (0.25 s).
  public static let step = 4000

  /// Samples from absolute index `bufferStart` onward.
  private var buffer: [Float] = []
  private var bufferStart = 0
  /// Total samples received so far.
  private var received = 0
  /// Windows emitted so far. The next window starts at `step * emitted`.
  private var emitted = 0

  public init() {}

  /// Adds samples to the stream.
  /// - Returns: each window completed by these samples, in order, possibly
  /// none.
  public mutating func process(_ samples: [Float]) -> [[Float]] {
    buffer += samples
    received += samples.count
    var windows: [[Float]] = []
    while Self.step * emitted + Self.length <= received {
      let start = Self.step * emitted - bufferStart
      windows.append(Array(buffer[start ..< (start + Self.length)]))
      emitted += 1
    }
    let keepFrom = Self.step * emitted
    let drop = min(max(0, keepFrom - bufferStart), buffer.count)
    buffer.removeFirst(drop)
    bufferStart += drop
    return windows
  }
}
