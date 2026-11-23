//
//  SpeechModel.swift
//  VA
//

import AVFoundation
import Observation
import Speech
import VACore

/// Observable status of the on-device speech model for SpeechTranscriber, and
/// the transcript it produces.
@Observable
final class SpeechModel {
  /// Model status for the transcriber's locale, such as "installed" or
  /// "supported".
  private(set) var modelStatus = "—"
  /// The locale the transcriber is built for. Each speech model covers one
  /// locale.
  let locale: Locale
  private let log: EventLog

  init(log: EventLog, locale: Locale = .current) {
    self.log = log
    self.locale = locale
  }

  /// A transcriber for one session. A transcriber attached to a finished
  /// analyzer can't be reused,
  /// so each start builds a new one.
  private func makeTranscriber() -> SpeechTranscriber {
    SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults],
      attributeOptions: [],
    )
  }

  /// Whether the model is usable, not installed but downloadable, or absent for
  /// this locale.
  var availability: SpeechModelState {
    switch modelStatus {
    case "installed": .installed
    case "supported", "downloading": .notInstalled
    default: .unavailable
    }
  }

  /// True while `download()` runs.
  private(set) var isDownloading = false
  /// Message from the last failed download, or nil.
  private(set) var downloadError: String?

  /// Requests and installs the model, then re-reads its status. A download
  /// error is kept for the sheet.
  func download() async {
    isDownloading = true
    downloadError = nil
    defer { isDownloading = false }
    do {
      if let request = try await AssetInventory
        .assetInstallationRequest(supporting: [makeTranscriber()])
      {
        try await request.downloadAndInstall()
      }
    } catch {
      downloadError = error.localizedDescription
    }
    await refreshStatus()
  }

  /// Reads whether the model for the transcriber's locale is on the device.
  func refreshStatus() async {
    modelStatus = switch await AssetInventory
      .status(forModules: [makeTranscriber()])
    {
    case .installed: "installed"
    case .supported: "supported"
    case .downloading: "downloading"
    case .unsupported: "unsupported"
    @unknown default: "unknown"
    }
  }

  /// Finalized text from the transcriber. Only final results are appended here.
  private(set) var committed = ""
  /// Finalized text not yet taken by the prompt. `takePending()` clears it.
  private(set) var pending = ""
  /// Interim text for the phrase in progress. Replaced by each volatile result.
  private(set) var volatile = ""
  /// What the Prompt section shows: committed text followed by the volatile
  /// tail.
  var transcript: String { committed + volatile }

  private var analyzer: SpeechAnalyzer?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var targetFormat: AVAudioFormat?
  private var converter: AVAudioConverter?
  private var resultsTask: Task<Void, Never>?
  /// Start and stop run one after another, so a stop never overlaps the next
  /// start.
  private var queue: Task<Void, Never>?

  /// Starts the analyzer. Queued behind any stop still finishing.
  func start() {
    enqueue { await self.startAnalyzer() }
  }

  /// Ends input and finalizes the analyzer. Queued behind any start still
  /// running.
  func stop() {
    enqueue { await self.stopAnalyzer() }
  }

  private func enqueue(_ work: @escaping () async -> Void) {
    let previous = queue
    queue = Task {
      await previous?.value
      await work()
    }
  }

  private func startAnalyzer() async {
    guard analyzer == nil else { return }
    let transcriber = makeTranscriber()
    guard let format = await SpeechAnalyzer
      .bestAvailableAudioFormat(compatibleWith: [transcriber])
    else {
      log.info("speech: no audio format for \(locale.identifier)")
      return
    }
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    self.analyzer = analyzer
    inputContinuation = continuation
    targetFormat = format
    committed = ""
    pending = ""
    volatile = ""
    resultsTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          let text = String(result.text.characters)
          if result.isFinal {
            self?.committed += text
            self?.pending += text
            self?.volatile = ""
          } else {
            self?.volatile = text
          }
        }
      } catch {
        self?.log.info("speech results error: \(error.localizedDescription)")
      }
    }
    do {
      try await analyzer.start(inputSequence: stream)
      log.info("speech started")
    } catch {
      log.info("speech start error: \(error.localizedDescription)")
    }
  }

  private func stopAnalyzer() async {
    let analyzer = analyzer
    let results = resultsTask
    inputContinuation?.finish()
    self.analyzer = nil
    inputContinuation = nil
    targetFormat = nil
    converter = nil
    volatile = ""
    try? await analyzer?.finalizeAndFinishThroughEndOfInput()
    await results?.value
    resultsTask = nil
  }

  /// Copies channel 0 of a float buffer into a new mono float buffer at the same
  /// sample rate. Avoids the converter's stereo downmix, which produced silence.
  static func channelZero(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let input = source.floatChannelData?[0],
          let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: source.format.sampleRate,
            channels: 1,
            interleaved: false,
          ),
          let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: source.frameLength),
          let output = mono.floatChannelData?[0] else { return nil }
    output.update(from: input, count: Int(source.frameLength))
    mono.frameLength = source.frameLength
    return mono
  }

  /// Copies mono float samples into a 16-bit buffer of `format`, or nil when
  /// `format` has no 16-bit channel data.
  static func quantize(_ source: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let input = source.floatChannelData?[0],
          let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: source.frameLength),
          let samples = output.int16ChannelData?[0] else { return nil }
    for index in 0 ..< Int(source.frameLength) {
      let scaled = (Double(input[index]) * 32767).rounded()
      samples[index] = Int16(max(-32768, min(32767, scaled)))
    }
    output.frameLength = source.frameLength
    return output
  }

  /// Returns the pending finalized text and clears it, so the prompt takes each
  /// phrase once.
  func takePending() -> String {
    let text = pending
    pending = ""
    return text
  }

  /// Passes one captured buffer to the analyzer, converted to the format it
  /// expects: channel 0 only, resampled to float, then quantized to 16-bit.
  func feed(_ buffer: AVAudioPCMBuffer) {
    guard let continuation = inputContinuation,
          let format = targetFormat else { return }
    let floatFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: format.sampleRate,
      channels: format.channelCount,
      interleaved: false,
    )
    guard let floatFormat, let mono = Self.channelZero(buffer) else { return }
    if converter == nil {
      converter = AVAudioConverter(from: mono.format, to: floatFormat)
    }
    guard let converter,
          let resampled = convert(mono, with: converter, to: floatFormat),
          let converted = Self.quantize(resampled, to: format) else { return }
    continuation.yield(AnalyzerInput(buffer: converted))
  }

  private func convert(
    _ buffer: AVAudioPCMBuffer,
    with converter: AVAudioConverter,
    to format: AVAudioFormat,
  )
    -> AVAudioPCMBuffer?
  {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
    guard let output = AVAudioPCMBuffer(
      pcmFormat: format,
      frameCapacity: capacity,
    ) else { return nil }
    var supplied = false
    var error: NSError?
    let status = converter
      .convert(to: output, error: &error) { _, inputStatus in
        if supplied {
          inputStatus.pointee = .noDataNow
          return nil
        }
        supplied = true
        inputStatus.pointee = .haveData
        return buffer
      }
    return status == .error ? nil : output
  }
}
