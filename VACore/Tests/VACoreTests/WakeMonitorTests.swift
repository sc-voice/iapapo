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
  let url = repo.appendingPathComponent("media/iapapo/Ava_premium_hello.m4a")
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

/// Windows a stream of `inputSamples` 48 kHz samples completes, counting the
/// resampler's ceil(n / 3) output.
private func expectedWindows(inputSamples: Int) -> Int {
  let outputSamples = (inputSamples + 2) / 3
  guard outputSamples >= SlidingWindow.length else { return 0 }
  return (outputSamples - SlidingWindow.length) / SlidingWindow.step + 1
}

/// One event per completed window, numbered from 0, spaced 0.25 s apart on the
/// stream clock.
@Test func monitorEmitsOneScorePerWindow() async throws {
  let scores = try await monitorScores(chunkSize: 4096)
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("media/iapapo/Ava_premium_hello.m4a")
  let samples = try WAVStreamer(url: url).samples.count

  #expect(
    scores.count == expectedWindows(inputSamples: samples),
    "scored \(scores.count) windows",
  )
  #expect(scores.count > 0)
  for (k, score) in scores.enumerated() {
    #expect(score.windowIndex == k)
    let expectedEnd = Double(SlidingWindow.step * k + SlidingWindow.length) /
      16000
    #expect(abs(score.endSeconds - expectedEnd) < 1e-9)
  }
}

/// The same audio gives the same scores however it is chunked, as a
/// microphone's buffer sizes vary.
@Test func monitorScoresAreChunkSizeIndependent() async throws {
  let reference = try await monitorScores(chunkSize: 4096)
  for size in [977, 1] {
    let scores = try await monitorScores(chunkSize: size)
    #expect(
      scores == reference,
      "chunk size \(size) differs from chunk size 4096",
    )
  }
}

/// Shape check on the m4a fixture: window 3 above 0.9, window 4 between 0.3 and
/// 0.5, all others below 0.1.
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
