import Foundation
import Testing
@testable import VACore

/// Streams `Ava_premium_hello.wav` (48 kHz mono) through `WakeMonitor` with the
/// bundled model, in chunks of `size`.
private func monitorScores(chunkSize size: Int) async throws -> [WakeScore] {
  // #filePath is VACore/Tests/VACoreTests/WakeMonitorTests.swift; the repo root
  // is four levels up.
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/Ava_premium_hello.m4a")
  let scorer = try WakeScorer.loadBundled()
  let streamer = try WAVStreamer(url: url)
  var monitor = WakeMonitor(scorer: scorer)
  var scores: [WakeScore] = []
  for chunk in streamer.chunks(size: size) {
    scores += try await monitor.process(chunk)
  }
  scores += try await monitor.flush()
  return scores
}

/// Index of the latest window completed by the end of stride `i` (1-based) at
/// the 250 ms default, or -1 before the first window.
private func latestWindow(atStride i: Int) -> Int {
  let samples = SlidingWindow.step * i
  return samples >= testWindowLength
    ? (samples - testWindowLength) / SlidingWindow.step
    : -1
}

/// One event per incoming stride, numbered from 1 on the stream clock, each
/// carrying the latest completed window's index.
@Test func monitorEmitsOneEventPerStride() async throws {
  let scores = try await monitorScores(chunkSize: 4096)
  #expect(scores.count > 0)
  for (k, score) in scores.enumerated() {
    let i = k + 1
    #expect(score.windowIndex == latestWindow(atStride: i))
    let expectedEnd = Double(SlidingWindow.step * i) / 16000
    #expect(abs(score.endSeconds - expectedEnd) < 1e-9)
  }
}

/// The same audio gives the same events however it is chunked, as a
/// microphone's buffer sizes vary.
@Test func monitorScoresAreChunkSizeIndependent() async throws {
  let reference = try await monitorScores(chunkSize: 4096)
  for size in [977, 1] {
    let scores = try await monitorScores(chunkSize: size)
    #expect(scores.count == reference.count)
    for (a, b) in zip(scores, reference) {
      #expect(a.probability == b.probability, "chunk size \(size): probability")
      #expect(a.windowIndex == b.windowIndex)
      #expect(a.endSeconds == b.endSeconds)
    }
  }
}

/// A 100 ms stride (1600 samples) emits the same events as the direct
/// HopCutter and SlidingWindow chain: one per stride, carrying the latest
/// window's probability, with the gate state and ambient floor.
@Test func monitorAt100ms() async throws {
  let stride = 1600
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/Ava_premium_hello.m4a")
  let scorer = try WakeScorer.loadBundled()

  // Reference: the direct chain, fed in chunks of 3 × stride at 48 kHz. One
  // entry per stride, from the latest completed window.
  var resampler = Resampler48To16()
  var cutter = HopCutter(hopLength: stride)
  var window = SlidingWindow(length: testWindowLength, step: stride)
  var expected: [(probability: Float, windowIndex: Int)] = []
  var current: Float = 0
  var scoredCount = 0
  for chunk in try WAVStreamer(url: url).chunks(size: 3 * stride) {
    for hop in cutter.process(resampler.process(chunk)) {
      for samples in window.process(hop) {
        current = try await scorer.probability(of: samples)
        scoredCount += 1
      }
      expected.append((current, scoredCount - 1))
    }
  }
  for hop in cutter.process(resampler.flush()) {
    for samples in window.process(hop) {
      current = try await scorer.probability(of: samples)
      scoredCount += 1
    }
    expected.append((current, scoredCount - 1))
  }
  for samples in window.process(cutter.flush()) {
    current = try await scorer.probability(of: samples)
    scoredCount += 1
  }
  #expect(scoredCount == 18, "scored \(scoredCount) windows, expected 18")

  var monitor = WakeMonitor(scorer: scorer, strideMs: 100)
  var scores: [WakeScore] = []
  for chunk in try WAVStreamer(url: url).chunks(size: 4096) {
    scores += try await monitor.process(chunk)
  }
  scores += try await monitor.flush()

  #expect(scores.count == expected.count, "\(scores.count) events, expected \(expected.count)")
  for (k, (score, want)) in zip(scores, expected).enumerated() {
    #expect(abs(score.probability - want.probability) < 1e-6, "event \(k): probability")
    #expect(score.windowIndex == want.windowIndex, "event \(k): windowIndex")
    let expectedEnd = Double(stride * (k + 1)) / 16000
    #expect(abs(score.endSeconds - expectedEnd) < 1e-9)
    #expect(score.gateOpen)
  }
  #expect(scores.last?.windowIndex == 17)
  #expect(scores.last?.ambientDb != nil)
}

/// Each event's micDb is the RMS in dBFS of the chunk that was being processed
/// when the event was emitted, floored at -160.
@Test func monitorMicLevelMatchesChunkRMS() async throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/Ava_premium_hello.m4a")
  let scorer = try WakeScorer.loadBundled()
  var monitor = WakeMonitor(scorer: scorer, strideMs: 100)
  var checked = 0
  for chunk in try WAVStreamer(url: url).chunks(size: 4096) {
    let sum = chunk.reduce(Float(0)) { $0 + $1 * $1 }
    let rms = (sum / Float(chunk.count)).squareRoot()
    let expectedDb = rms > 0 ? max(20 * log10(rms), -160) : -160
    for score in try await monitor.process(chunk) {
      #expect(
        abs(score.micDb - expectedDb) < 1e-3,
        "event \(checked): micDb \(score.micDb), chunk \(expectedDb)",
      )
      checked += 1
    }
  }
  #expect(checked > 0, "checked \(checked) events")
}

/// Shape check on the m4a fixture: window 3 above 0.9, window 4 between 0.3 and
/// 0.5, all others below 0.1. Events before window 0 carry 0.
@Test func monitorScoreCurveHasOnePeak() async throws {
  let scores = try await monitorScores(chunkSize: 4096)
  for score in scores {
    switch score.windowIndex {
    case 3:
      #expect(
        score.probability > 0.9,
        "window 3 scored \(score.probability), expected above 0.9",
      )
    case 4:
      #expect(
        score.probability > 0.3 && score.probability < 0.5,
        "window 4 scored \(score.probability), expected 0.3 to 0.5",
      )
    default:
      #expect(
        score.probability < 0.1,
        "window \(score.windowIndex) scored \(score.probability), expected below 0.1",
      )
    }
  }
}
