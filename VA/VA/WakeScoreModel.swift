//
//  WakeScoreModel.swift
//  VA
//

import AVFoundation
import Observation
import VACore

/// The value the wake ring shows. Raw scores arrive from `WakeFeed`, one per
/// hop. A higher score is shown at once. A lower score pulls the shown value
/// down by `decayPerHop` of the remaining gap per event, so a lone detection
/// falls to 0.1 within one second at 0.25 s hops.
@MainActor
@Observable
final class WakeScoreModel {
  /// Smoothed score, from 0 to 1. The ring draws this value.
  private(set) var shown: Float = 0

  /// Share of the gap to the live score left after one hop. 0.562 per 0.25 s
  /// hop gives 0.1 after four hops, one second.
  static let decayPerHop: Float = 0.562

  /// Ambient floor in dBFS from the latest score, nil until the first hop.
  private(set) var ambientDb: Float?

  /// Smoothed window level in dBFS from the latest score, nil until the first hop.
  private(set) var windowDb: Float?

  /// Whether the window level is at least the gate margin above the ambient
  /// floor, from the latest score. False until the first hop.
  private(set) var gateOpen = false

  /// Whether the latest window level is at least `marginDb` above the latest
  /// ambient floor. False until both levels are known, so the ring starts gray.
  /// - Parameter marginDb: the gate margin in dB, from the app settings.
  func windowAboveAmbient(by marginDb: Float) -> Bool {
    guard let windowDb, let ambientDb else { return false }
    return windowDb - ambientDb >= marginDb
  }

  /// The wake monitor's scoring period, in milliseconds. One event per stride.
  static let strideMs = WakeMonitor.productionStrideMs
  /// Probability at or above which a stride counts as a wake word.
  static let wakeLevel = WakeMonitor.defaultWakeLevel
  /// Span of the history charts, in milliseconds.
  static let historyMs = 2_000
  /// Events kept for the history charts, derived from the stride period.
  static let historyCount = historyMs / strideMs
  /// True when the `VERBOSE` environment variable is set at launch. Turns on
  /// the per-stride wake log in any build configuration.
  static let verbose = ProcessInfo.processInfo.environment["VERBOSE"] != nil
  /// Microphone level in dBFS per event, newest first.
  private(set) var micHistory: [Float] = []
  /// Mic ring level in dBFS, set from `Microphone.level` for each captured
  /// buffer. Logged only; it does not drive the charts.
  var ringDb: Float = -160
  /// When the wake feed last started, the origin for logged times.
  var clockStart = Date()
  /// Raw score per event, newest first.
  private(set) var scoreHistory: [Float] = []
  /// Whether each event was a wake word, newest first, parallel to `scoreHistory`.
  private(set) var wakeHistory: [Bool] = []
  /// Whether the latest event was a wake word.
  private(set) var wakeWord = false

  /// Shows each score from `scores` until the stream finishes. Wake events are
  /// not decided here; `WakeMonitor` emits them and `VAAgent` reacts.
  /// - Parameter scores: one score per stride, from `WakeMonitor.scores`.
  func consume(_ scores: AsyncStream<WakeScore>) {
    Task {
      for await score in scores {
        receive(score)
      }
    }
  }

  /// Called for each score whose window level clears the wake margin.
  var onAboveAmbient: (() -> Void)?

  /// Applies one score from `WakeMonitor`.
  /// - Parameter score: the window's probability, levels and gate state.
  func receive(_ score: WakeScore) {
    let raw = score.probability
    shown = raw >= shown ? raw : raw + (shown - raw) * Self.decayPerHop
    ambientDb = score.ambientDb
    windowDb = score.windowDb
    gateOpen = score.gateOpen
    if windowAboveAmbient(by: appSettings.ambientWakeDb) { onAboveAmbient?() }
    micHistory = Array(([score.micDb] + micHistory).prefix(Self.historyCount))
    scoreHistory = Array(([raw] + scoreHistory).prefix(Self.historyCount))
    wakeHistory = Array(([score.wakeWord] + wakeHistory).prefix(Self.historyCount))
    wakeWord = score.wakeWord
    if Self.verbose {
      let ms = Int(Date().timeIntervalSince(clockStart) * 1000)
      print("[VA wake] t \(ms) ring \(String(format: "%.1f", ringDb)) bar \(String(format: "%.1f", score.micDb)) raw \(raw) inferred \(shown)")
    }
  }

  /// Returns the shown value, the ambient floor and the history charts to their
  /// starting state, as when the microphone stops.
  func reset() {
    shown = 0
    ambientDb = nil
    windowDb = nil
    gateOpen = false
    micHistory = []
    scoreHistory = []
    wakeHistory = []
    wakeWord = false
  }
}

/// Runs `WakeMonitor` on microphone buffers and posts each raw score to a
/// `WakeScoreModel`. Scoring runs off the main actor. Buffers are converted to
/// 48 kHz mono Float32 on the main actor first.
@MainActor
final class WakeFeed {
  /// 48 kHz mono Float32, the format `WakeMonitor` expects.
  private static let target = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 48_000,
    channels: 1,
    interleaved: false,
  )!

  private let model: WakeScoreModel
  private let log: EventLog
  private let agent: VAAgent
  private let settings: any AppSettings
  private let scorer: WakeScorer?
  private var continuation: AsyncStream<[Float]>.Continuation?
  private var task: Task<Void, Never>?
  private var converter: AVAudioConverter?
  /// Converted samples not yet forming a full stride.
  private var pending: [Float] = []
  /// One stride at 48 kHz, the period `WakeMonitor` scores at.
  private static let strideSamples = 48 * WakeScoreModel.strideMs

  /// - Parameters:
  ///   - model: receives each raw score.
  ///   - log: records when the bundled model is missing.
  ///   - agent: receives each wake event from the monitor.
  ///   - settings: supplies the wake monitor's ambient wake margin.
  init(model: WakeScoreModel, log: EventLog, agent: VAAgent, settings: any AppSettings) {
    self.model = model
    self.log = log
    self.agent = agent
    self.settings = settings
    do {
      scorer = try WakeScorer.loadBundled()
    } catch {
      scorer = nil
      log.info("wake scorer unavailable: \(error.localizedDescription)")
    }
  }

  /// Starts a fresh monitor for a new microphone session. Does nothing if the
  /// bundled model is missing or the feed is already running.
  func start() {
    guard let scorer, task == nil else { return }
    let (stream, continuation) = AsyncStream<[Float]>.makeStream()
    self.continuation = continuation
    model.clockStart = Date()
    let monitor = WakeMonitor(
      scorer: scorer,
      strideMs: WakeMonitor.productionStrideMs,
      wakeLevel: WakeScoreModel.wakeLevel,
      settings: settings,
    )
    model.consume(monitor.scores)
    let agent = agent
    let events = monitor.events
    Task {
      for await event in events {
        agent.send(event)
      }
    }
    let log = log
    task = Task { [monitor] in
      var monitor = monitor
      var warnedOverrun = false
      for await chunk in stream {
        do {
          let started = ContinuousClock.now
          // Scores reach the model and events reach the agent through the
          // monitor's streams, so the returned array is not needed here.
          _ = try await monitor.process(chunk)
          // One stride must score within one stride period, or the events lag
          // the audio. Warn once per session.
          if !warnedOverrun, started.duration(to: .now) > .milliseconds(WakeScoreModel.strideMs) {
            warnedOverrun = true
            log.warn("wake scoring slower than real time; events will lag")
          }
        } catch {
          let cancelled = Task.isCancelled
          let levelDb = chunk.isEmpty ? -160 : Float(10 * log10(max(chunk.reduce(0) { $0 + Double($1 * $1) } / Double(chunk.count), 1e-16)))
          print("[VA wake] scoring error: \(error) taskCancelled \(cancelled) chunk \(chunk.count) samples \(String(format: "%.1f", levelDb)) dBFS")
          print(Thread.callStackSymbols.prefix(12).joined(separator: "\n"))
        }
      }
      // Ends `scores` and `events`, so the model and agent loops finish too.
      monitor.finish()
    }
  }

  /// Ends the current monitor and returns the ring to zero.
  func stop() {
    continuation?.finish()
    continuation = nil
    task?.cancel()
    task = nil
    converter = nil
    pending = []
    model.reset()
  }

  /// Converts one microphone buffer and queues it for scoring. Does nothing
  /// while the feed is stopped.
  /// - Parameter buffer: a buffer from `Microphone`, in its capture format.
  func feed(_ buffer: AVAudioPCMBuffer) {
    guard let continuation else { return }
    pending += samples(from: buffer)
    while pending.count >= Self.strideSamples {
      continuation.yield(Array(pending.prefix(Self.strideSamples)))
      pending.removeFirst(Self.strideSamples)
    }
  }

  /// The buffer's samples as 48 kHz mono Float32. Channel 0 is used when the
  /// buffer is already in that format, and an `AVAudioConverter` is used
  /// otherwise.
  private func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
    var source = buffer
    // 48 kHz non-interleaved Float32 is read as channel 0 directly, the same
    // channel the mic ring reads. Anything else goes through the converter.
    let direct = buffer.format.sampleRate == 48_000
      && buffer.format.commonFormat == .pcmFormatFloat32
      && !buffer.format.isInterleaved
    if !direct {
      if converter?.inputFormat != buffer.format {
        converter = AVAudioConverter(from: buffer.format, to: Self.target)
      }
      guard let converter else { return [] }
      let capacity = AVAudioFrameCount(
        Double(buffer.frameLength) * 48_000 / buffer.format.sampleRate
      ) + 16
      guard let output = AVAudioPCMBuffer(
        pcmFormat: Self.target,
        frameCapacity: capacity,
      ) else { return [] }
      var supplied = false
      var error: NSError?
      // The conversion is synchronous, so this input is used only inside it.
      nonisolated(unsafe) let input = buffer
      converter.convert(to: output, error: &error) { _, status in
        if supplied {
          status.pointee = .noDataNow
          return nil
        }
        supplied = true
        status.pointee = .haveData
        return input
      }
      guard error == nil else {
        print("[VA wake] convert error: \(String(describing: error))")
        return []
      }
      source = output
    } else {
    }
    guard let data = source.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: data, count: Int(source.frameLength)))
  }
}
