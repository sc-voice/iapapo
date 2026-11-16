import Foundation

/// Cuts a 16 kHz stream into the scoring windows the model was trained on.
///
/// Window `k` is the samples `[step * k, step * k + length)` of the stream. With
/// the default step, that is the grid `train.py` scores.
/// A window is emitted as soon as the stream has reached its last sample.
/// Windows are not padded at the end,
/// so a window that the stream never completes is never emitted, as in
/// training.
/// Only the samples the next window needs are kept.
public struct SlidingWindow: Sendable {
  /// Samples between window starts at 16 kHz (0.25 s).
  public static let step = 4000

  /// Samples per window, from the model's `window_len` (see `WakeScorer`).
  private let length: Int
  /// Samples between window starts for this stream.
  private let step: Int
  /// Samples from absolute index `bufferStart` onward.
  private var buffer: [Float] = []
  private var bufferStart = 0
  /// Total samples received so far.
  private var received = 0
  /// Windows emitted so far. The next window starts at `step * emitted`.
  private var emitted = 0

  /// - Parameters:
  ///   - length: samples per window, the model's `window_len`.
  ///   - step: samples between window starts; the training grid by default.
  public init(length: Int, step: Int = SlidingWindow.step) {
    self.length = length
    self.step = step
  }

  /// Adds samples to the stream.
  /// - Returns: each window completed by these samples, in order, possibly
  /// none.
  public mutating func process(_ samples: [Float]) -> [[Float]] {
    buffer += samples
    received += samples.count
    var windows: [[Float]] = []
    while step * emitted + length <= received {
      let start = step * emitted - bufferStart
      windows.append(Array(buffer[start ..< (start + length)]))
      emitted += 1
    }
    let keepFrom = step * emitted
    let drop = min(max(0, keepFrom - bufferStart), buffer.count)
    buffer.removeFirst(drop)
    bufferStart += drop
    return windows
  }
}
