//
//  WakeWordSamples.swift
//  VA
//

import AVFoundation
import Observation
import VACore

/// Whether a clip contains the wake word or something else.
enum SampleLabel: String {
  case positive
  case negative
}

/// Stores wake-word training clips as WAV files under
/// Documents/WakeWord/<take>/.
/// A take is one recording session. Retakes start a new take, so earlier clips
/// are never overwritten.
struct SampleStore {
  /// Documents/WakeWord, the parent of every take.
  let root: URL = FileManager.default.urls(
    for: .documentDirectory,
    in: .userDomainMask,
  )[0]
    .appending(path: "WakeWord", directoryHint: .isDirectory)

  /// The first 8 characters of the UUID64 timeId for `date`: its full 48-bit
  /// millisecond timestamp in the
  /// nf order-preserving alphabet, so names sort chronologically and each name
  /// is exact to 1 ms.
  static func timeId8(_ date: Date) -> String {
    let value = UInt64(date.timeIntervalSince1970 * 1000) << 16
    let bytes = (0 ..< 8)
      .map { UInt8(truncatingIfNeeded: value >> UInt64(56 - 8 * $0)) }
    return String(OPB64.encode(bytes).prefix(8))
  }

  /// Creates a take folder named by its 8-character timeId, so takes sort
  /// chronologically.
  func newTake() throws -> URL {
    let take = root.appending(
      path: Self.timeId8(.now),
      directoryHint: .isDirectory,
    )
    try FileManager.default.createDirectory(
      at: take,
      withIntermediateDirectories: true,
    )
    return take
  }

  /// The next clip path for `label` in `take`, numbered after the clips already
  /// there.
  func nextClipURL(_ label: SampleLabel, in take: URL) throws -> URL {
    let existing = try FileManager.default.contentsOfDirectory(
      at: take,
      includingPropertiesForKeys: nil,
    )
    .filter { $0.lastPathComponent.hasPrefix(label.rawValue + "-") }
    return take.appending(path: String(
      format: "%@-%03ld.wav",
      label.rawValue,
      existing.count + 1,
    ))
  }
}

/// Level limits a positive clip must meet to be kept. A positive that is
/// silent, clipped, or barely above its own
/// start noise is rejected. Negatives are exempt: the transcriber has already
/// confirmed they contain no wake word,
/// and their frame levels set the take's noise floor.
enum ClipCheck {
  /// dB a clip's peak must rise above the session noise floor to count as
  /// sound.
  ///
  /// The session noise floor F comes from the negatives recorded in the current
  /// take:
  /// 1. Split every negative clip into 20 ms frames (`frameSeconds`) and take
  /// each frame's RMS in dBFS.
  /// 2. F = the 10th percentile of all those frame levels (`percentile10`),
  /// with linear interpolation.
  ///    The quietest tenth of the frames is the room and mic noise, so F is the
  /// noise to rise above.
  /// 3. Gate G = F + `marginDb`. A clip whose peak is below G is treated as
  /// silence.
  ///    The 30 dB margin is a choice: a real utterance should sit well above
  /// the noise, and this leaves
  ///    room for quiet speakers.
  /// Before any negatives are recorded in a take, G is `fallbackPeakDb`.
  /// Derived from the training negatives in lab/wakeword (24.2 s): F = -62.1
  /// dBFS, so the fallback is -32.
  static let marginDb: Float = 30
  /// Peak gate, in dBFS, used until the take has negative frames to measure a
  /// floor from.
  static let fallbackPeakDb: Float = -32
  /// Peak at or above this linear level counts as clipping.
  static let clipLevel: Float = 0.99
  /// Least gap, in dB, between the clip's peak and the noise at its start.
  static let minSnrDb: Float = 15
  /// Seconds at the start of a clip taken as its noise floor.
  static let noiseSeconds: Double = 0.2
  /// Length of one frame, in seconds, for the session noise floor.
  static let frameSeconds: Double = 0.02

  /// The 10th percentile of `values`, interpolated linearly between the two
  /// nearest ranks.
  /// Matches numpy's default percentile.
  static func percentile10(_ values: [Float]) -> Float {
    let sorted = values.sorted()
    let position = 0.1 * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = Float(position - Double(lower))
    return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
  }

  /// Converts a linear amplitude to dBFS, floored at -180 dB for silence.
  static func decibels(_ linear: Double) -> Float {
    Float(20 * log10(max(linear, 1e-9)))
  }
}

/// Writes captured mic buffers to one WAV file at a time. Buffers are dropped
/// when not recording.
/// The file takes the format of the first buffer, so nothing is resampled at
/// capture.
/// Also tracks the open clip's peak and start noise, so `rejectionReason()` can
/// judge it before it is kept.
/// Negative clips that are kept add their frame levels to `negativeFrameDb`,
/// which sets the take's noise floor.
@Observable
final class ClipRecorder {
  /// Whether a clip is being written.
  private(set) var isRecording = false
  /// 20 ms frame levels, in dBFS, of the negative clips kept in the current
  /// take.
  private(set) var negativeFrameDb: [Float] = []
  private var url: URL?
  private var file: AVAudioFile?
  private let log: EventLog
  private var label: SampleLabel?
  private var peak: Float = 0
  private var noiseSquares: Double = 0
  private var noiseFrames = 0
  private var noiseLimit = 0
  private var clipFrameDb: [Float] = []
  private var frameSquares: Double = 0
  private var frameCount = 0
  private var frameLimit = 0

  init(log: EventLog) {
    self.log = log
  }

  /// Arms the recorder for one clip of `label`. Captured buffers from now on
  /// are written to `url` until `stop()`.
  func start(writingTo url: URL, label: SampleLabel) {
    self.url = url
    self.label = label
    file = nil
    isRecording = true
    peak = 0
    noiseSquares = 0
    noiseFrames = 0
    noiseLimit = 0
    clipFrameDb = []
    frameSquares = 0
    frameCount = 0
    frameLimit = 0
  }

  /// Closes the clip. The file is complete once this returns.
  func stop() {
    isRecording = false
    file = nil
    url = nil
    label = nil
  }

  /// Forgets the negatives of the previous take, so a new take measures its own
  /// floor.
  func resetFloor() {
    negativeFrameDb = []
  }

  /// The peak gate for the open clip: the session floor plus
  /// `ClipCheck.marginDb`,
  /// or `ClipCheck.fallbackPeakDb` while the take has no negatives yet.
  func peakGateDb() -> (gate: Float, source: String) {
    guard !negativeFrameDb.isEmpty else {
      return (ClipCheck.fallbackPeakDb, "fallback")
    }
    let floor = ClipCheck.percentile10(negativeFrameDb)
    return (
      floor + ClipCheck.marginDb,
      String(format: "session floor %.1f dBFS", floor),
    )
  }

  /// Why the open clip should be discarded, or nil if it passes `ClipCheck`.
  /// Read it before `stop()`.
  /// Negatives are not level-checked: the transcriber has already confirmed
  /// they contain no wake word.
  func rejectionReason() -> String? {
    guard label == .positive else { return nil }
    let peakDb = ClipCheck.decibels(Double(peak))
    if peak >= ClipCheck.clipLevel {
      return String(format: "clipped (peak %.1f dBFS)", peakDb)
    }
    let (gate, source) = peakGateDb()
    if peakDb < gate {
      return String(
        format: "too quiet (peak %.1f dBFS, need %.1f from %@)",
        peakDb,
        gate,
        source,
      )
    }
    let noiseRms = noiseFrames > 0 ? (noiseSquares / Double(noiseFrames))
      .squareRoot() : 0
    let noiseDb = ClipCheck.decibels(noiseRms)
    let snr = peakDb - noiseDb
    if snr < ClipCheck.minSnrDb {
      return String(
        format: "no speech above noise (%.1f dB, need %.0f)",
        snr,
        ClipCheck.minSnrDb,
      )
    }
    return nil
  }

  /// Adds the open clip's frame levels to the take's floor, if the clip is a
  /// negative. Call only for kept clips.
  func keepClipFrames() {
    guard label == .negative else { return }
    negativeFrameDb += clipFrameDb
  }

  /// Appends one captured buffer. Called for every mic buffer; does nothing
  /// when not recording.
  func capture(_ buffer: AVAudioPCMBuffer) {
    guard isRecording, let url else { return }
    if noiseLimit == 0 {
      noiseLimit = Int(buffer.format.sampleRate * ClipCheck.noiseSeconds)
    }
    if frameLimit == 0 {
      frameLimit = Int(buffer.format.sampleRate * ClipCheck.frameSeconds)
    }
    if let samples = buffer.floatChannelData?[0] {
      for index in 0 ..< Int(buffer.frameLength) {
        let value = samples[index]
        peak = max(peak, abs(value))
        if noiseFrames < noiseLimit {
          noiseSquares += Double(value * value)
          noiseFrames += 1
        }
        if frameLimit > 0 {
          frameSquares += Double(value * value)
          frameCount += 1
          if frameCount == frameLimit {
            clipFrameDb
              .append(ClipCheck
                .decibels((frameSquares / Double(frameCount)).squareRoot()))
            frameSquares = 0
            frameCount = 0
          }
        }
      }
    }
    do {
      if file == nil {
        file = try AVAudioFile(
          forWriting: url,
          settings: buffer.format.settings,
          commonFormat: buffer.format.commonFormat,
          interleaved: buffer.format.isInterleaved,
        )
      }
      try file?.write(from: buffer)
    } catch {
      log.info("clip write error: \(error.localizedDescription)")
    }
  }
}
