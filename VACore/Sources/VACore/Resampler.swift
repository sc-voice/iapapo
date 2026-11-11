import Foundation

/// Streaming 3:1 decimation from 48 kHz to 16 kHz. Feed it chunks as the
/// microphone delivers them.
///
/// Gives the same samples as `ArrayResampler48To16` on the concatenated input.
/// Output sample `m` is
/// `Σ_j h[j] · x[3m + 30 − j]`, which needs input up to index `3m + 30`, so
/// each output is emitted once
/// that sample has arrived. `flush()` emits the remaining outputs at the end,
/// with input past the end as zero.
/// Only the last 60 input samples are kept between calls.
public struct Resampler48To16: Sendable {
  private let taps: [Double]
  /// Input samples from absolute index `bufferStart` onward.
  private var buffer: [Double] = []
  private var bufferStart = 0
  /// Total input samples received so far.
  private var received = 0
  /// Output samples emitted so far.
  private var emitted = 0

  public init() {
    taps = ArrayResampler48To16.designTaps()
  }

  /// Feeds the next chunk of 48 kHz samples.
  /// - Returns: the 16 kHz samples that are now complete, possibly none.
  public mutating func process(_ chunk: [Float]) -> [Float] {
    buffer.append(contentsOf: chunk.map(Double.init))
    received += chunk.count
    var out: [Float] = []
    while 3 * emitted + ArrayResampler48To16.halfLength < received {
      out.append(output(emitted))
      emitted += 1
    }
    discardSamplesNoLongerNeeded()
    return out
  }

  /// Ends the stream.
  /// - Returns: the remaining 16 kHz samples, so that the total matches
  /// `ArrayResampler48To16` on the whole input.
  public mutating func flush() -> [Float] {
    var out: [Float] = []
    let total = (received + ArrayResampler48To16.decimation - 1) /
      ArrayResampler48To16.decimation
    while emitted < total {
      out.append(output(emitted))
      emitted += 1
    }
    return out
  }

  /// Output sample `m`, from the input held in the buffer. Input outside
  /// `0..<received` counts as zero.
  private func output(_ m: Int) -> Float {
    var acc = 0.0
    for j in 0 ..< taps.count {
      let i = ArrayResampler48To16.decimation * m + ArrayResampler48To16
        .halfLength - j
      if i >= 0, i < received {
        acc += taps[j] * buffer[i - bufferStart]
      }
    }
    return Float(acc)
  }

  /// Drops input that the next output sample cannot need.
  private mutating func discardSamplesNoLongerNeeded() {
    let keepFrom = ArrayResampler48To16
      .decimation * emitted - ArrayResampler48To16.halfLength
    let drop = min(max(0, keepFrom - bufferStart), buffer.count)
    buffer.removeFirst(drop)
    bufferStart += drop
  }
}
