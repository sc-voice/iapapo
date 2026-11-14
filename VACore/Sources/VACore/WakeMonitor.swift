import Foundation

/// The wake-word state after one stride of input, with the microphone, ambient
/// and gate state at that time.
public struct WakeScore: Sendable, Equatable {
  /// Probability from the most recent completed window. 0 before the first
  /// window completes.
  public let probability: Float
  /// Index of the most recent completed window, or -1 before the first window.
  /// Window `k` covers samples `[strideK, strideK + 14287)`.
  public let windowIndex: Int
  /// Stream time in seconds at which this stride ended.
  public let endSeconds: Double
  /// RMS level in dBFS of the most recent chunk, floored at -160.
  public let micDb: Float
  /// Ambient floor in dBFS, or nil before the first 0.25 s hop.
  public let ambientDb: Float?
  /// Whether the gate is open.
  public let gateOpen: Bool
}

/// Streams 48 kHz audio through the wake-word chain and emits one event per
/// incoming stride.
///
/// Each event carries the current wake probability, the microphone level of the
/// latest chunk, and the ambient floor. The current probability changes only
/// when a window completes. Feed it microphone buffers as they arrive, in any
/// sizes. It applies no threshold: the caller decides what counts as a detection.
///
/// It also tracks the ambient floor, updated once per 0.25 s hop with a 1.5 s
/// half-life, and the gate state reported in each event.
public struct WakeMonitor {
  /// Samples per ambient hop at 48 kHz: 0.25 s.
  private static let hopSamples = 12_000
  /// Share of the gap to each new hop level. 1 - 0.5^(0.25 / 1.5), about 0.109.
  static let ambientAlpha: Float = 1 - pow(0.5, 0.25 / 1.5)

  private let scorer: WakeScorer
  /// Samples between window starts at 16 kHz.
  private let stride: Int
  private var resampler = Resampler48To16()
  private var cutter: HopCutter
  private var window: SlidingWindow
  /// Windows scored so far. The latest window's index is this count minus one.
  private var scored = 0
  /// Strides emitted so far.
  private var strides = 0
  /// Probability from the most recent completed window, 0 before the first.
  private var currentProbability: Float = 0
  /// RMS level in dBFS of the most recent chunk, -160 when silent.
  private var micDb: Float = -160
  /// Ambient floor in dBFS, nil until the first hop.
  private var ambientDb: Float?
  /// Sum of squared 48 kHz samples and sample count for the hop in progress.
  private var hopSquares: Double = 0
  private var hopCount = 0
  /// Placeholder: the gate starts open until its closing logic lands. The
  /// intended default is closed. The ambient floor does not yet freeze while
  /// the gate is open; that arrives with the gate logic.
  private var gateOpen = true

  /// - Parameters:
  ///   - scorer: the scorer whose model and window probability the monitor uses.
  ///   - strideMs: milliseconds between window starts, and between events. Must
  ///   be a positive multiple of 10 ms, the frame period, so frames align across
  ///   strides. Defaults to the training grid's 250 ms (4000 samples).
  public init(scorer: WakeScorer, strideMs: Int = 250) {
    precondition(
      strideMs > 0 && strideMs % 10 == 0,
      "strideMs \(strideMs) must be a positive multiple of 10"
    )
    let stride = strideMs * LogMelFrontEnd.sampleRate / 1000
    self.scorer = scorer
    self.stride = stride
    cutter = HopCutter(hopLength: stride)
    window = SlidingWindow(step: stride)
  }

  /// Adds 48 kHz mono samples to the stream.
  /// - Parameter chunk: samples in order, of any size, such as a microphone
  /// buffer.
  /// - Returns: one event for each stride this chunk completes, in order,
  /// possibly none.
  public mutating func process(_ chunk: [Float]) async throws -> [WakeScore] {
    micDb = Self.decibels(of: chunk)
    accumulateHop(chunk)
    var events: [WakeScore] = []
    for hop in cutter.process(resampler.process(chunk)) {
      events.append(try await advance(hop: hop))
    }
    return events
  }

  /// Ends the stream, so the scores cover the whole input, as the test harness
  /// does. The final partial stride is scored but emits no event.
  /// - Returns: the events for strides completed by the flushed samples,
  /// possibly none.
  public mutating func flush() async throws -> [WakeScore] {
    var events: [WakeScore] = []
    for hop in cutter.process(resampler.flush()) {
      events.append(try await advance(hop: hop))
    }
    try await scoreWindows(window.process(cutter.flush()))
    return events
  }

  /// Scores the windows one stride completes and returns that stride's event.
  private mutating func advance(hop: [Float]) async throws -> WakeScore {
    try await scoreWindows(window.process(hop))
    strides += 1
    return WakeScore(
      probability: currentProbability,
      windowIndex: scored - 1,
      endSeconds: Double(stride * strides) / Double(LogMelFrontEnd.sampleRate),
      micDb: micDb,
      ambientDb: ambientDb,
      gateOpen: gateOpen,
    )
  }

  /// Scores windows in order, keeping the latest probability.
  private mutating func scoreWindows(_ windows: [[Float]]) async throws {
    for samples in windows {
      currentProbability = try await scorer.probability(of: samples)
      scored += 1
    }
  }

  /// Adds samples to the hop in progress. When a hop completes, its mean power
  /// in dBFS updates the ambient floor. A chunk can overshoot the hop by up to
  /// one buffer, so a hop is at least 0.25 s.
  private mutating func accumulateHop(_ samples: [Float]) {
    hopSquares += samples.reduce(0) { $0 + Double($1 * $1) }
    hopCount += samples.count
    guard hopCount >= Self.hopSamples else { return }
    let power = hopSquares / Double(hopCount)
    let dB = Float(power > 0 ? max(10 * log10(power), -160) : -160)
    if let floor = ambientDb {
      ambientDb = floor + (dB - floor) * Self.ambientAlpha
    } else {
      ambientDb = dB
    }
    hopSquares = 0
    hopCount = 0
  }

  /// RMS level of `samples` in dBFS, floored at -160.
  private static func decibels(of samples: [Float]) -> Float {
    guard !samples.isEmpty else { return -160 }
    let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
    let rms = (sum / Float(samples.count)).squareRoot()
    return rms > 0 ? max(20 * log10(rms), -160) : -160
  }
}
