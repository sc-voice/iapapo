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
  let url = repo.appendingPathComponent("media/iapapo/holdout/positive-Ava_premium_hello.m4a")
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
  let url = repo.appendingPathComponent("media/iapapo/holdout/positive-Ava_premium_hello.m4a")
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
  let url = repo.appendingPathComponent("media/iapapo/holdout/positive-Ava_premium_hello.m4a")
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

/// One peak on the m4a fixture: the windows scoring above 0.8 form one contiguous run that includes window 3.
/// Window scores for 0Q7YdK (4096-sample chunks), for reference:
///   -1: 0.0 (pre-window events, x3)
///    0: 0.00023   1: 0.000032   2: 0.0081
///    3: 0.99994   4: 0.99910    5: 0.000079   6: 0.000033
/// Events before window 0 carry 0.
@Test func monitorScoreCurveHasOnePeak() async throws {
  let scores = try await monitorScores(chunkSize: 4096)
  let hot = scores.filter { $0.probability > 0.8 }.map(\.windowIndex)
  #expect(!hot.isEmpty, "no window scored above 0.8")
  #expect(hot.contains(3), "run above 0.8 does not include window 3: \(hot)")
  if let first = hot.first, let last = hot.last {
    #expect(hot == Array(first...last), "windows above 0.8 are not one run: \(hot)")
  }
}

/// Debug output only: prints ambientDb and windowDb for every event over the
/// Ava clip, padded with silence to the next stride after one full window.
@Test func monitorPrintsAmbientAndWindowDb() async throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/Ava_premium__.m4a")
  let scorer = try WakeScorer.loadBundled()
  let windowLength48 = scorer.windowLength * 3
  let strideLength48 = 12_000
  let target = ((windowLength48 + strideLength48 - 1) / strideLength48) * strideLength48
  var monitor = WakeMonitor(scorer: scorer)
  var scores: [WakeScore] = []
  var total = 0
  for chunk in try WAVStreamer(url: url).chunks(size: 4096) {
    total += chunk.count
    scores += try await monitor.process(chunk)
  }
  // Seeded uniform noise with RMS 0.001 (-60 dBFS), so runs repeat exactly.
  var seed: UInt64 = 1
  func nextNoise() -> Float {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    let u = Float(seed >> 11) / Float(1 << 53)
    return (u * 2 - 1) * 0.001 * Float(3).squareRoot()
  }
  while total < target {
    let n = min(4096, target - total)
    let noise = (0..<n).map { _ in nextNoise() }
    total += n
    scores += try await monitor.process(noise)
  }
  scores += try await monitor.flush()
  var table = "DBG windowLen16k=\(scorer.windowLength) padTo48k=\(target) hops=\(scores.count)"
  table += "\nDBG   hop    t(s)   ambientDb  windowDb     delta"
  for (k, s) in scores.enumerated() {
    let amb = s.ambientDb.map { String(format: "%8.1f", $0) } ?? "       -"
    let win = s.windowDb.map { String(format: "%8.1f", $0) } ?? "       -"
    let delta = (s.windowDb != nil && s.ambientDb != nil)
      ? String(format: "%8.1f", s.windowDb! - s.ambientDb!)
      : "       -"
    table += "\nDBG \(String(format: "%5d", k + 1)) \(String(format: "%7.2f", s.endSeconds)) \(amb) \(win) \(delta)"
  }
  print(table)
}

/// The Ava hello holdout clip stays positive: the gate is open on every hop
/// and the probability crosses the wake level at hops 7 and 8. Reference trace
/// (ambientDb, windowDb, delta, gate, p) at 250 ms hops:
///   1: -55.1  -45.6   9.5  open  0.000
///   2: -50.9  -36.1  14.8  open  0.000
///   3: -47.3  -30.3  17.0  open  0.000
///   4: -44.1  -26.4  17.7  open  0.000
///   5: -41.2  -23.6  17.6  open  0.000
///   6: -38.5  -21.1  17.3  open  0.008
///   7: -36.2  -20.0  16.2  open  1.000
///   8: -34.1  -19.0  15.1  open  0.999
///   9: -32.4  -18.9  13.5  open  0.000
///  10: -31.2  -19.6  11.6  open  0.000
@Test func monitorHelloClipStaysPositive() async throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/positive-Ava_premium_hello.m4a")
  let scorer = try WakeScorer.loadBundled()
  var monitor = WakeMonitor(scorer: scorer)
  var scores: [WakeScore] = []
  for chunk in try WAVStreamer(url: url).chunks(size: 4096) {
    scores += try await monitor.process(chunk)
  }
  scores += try await monitor.flush()
  var table = "DBG hops=\(scores.count)"
  table += "\nDBG   hop    t(s)   ambientDb  windowDb     delta   gate      p"
  for (k, s) in scores.enumerated() {
    let amb = s.ambientDb.map { String(format: "%8.1f", $0) } ?? "       -"
    let win = s.windowDb.map { String(format: "%8.1f", $0) } ?? "       -"
    let delta = (s.windowDb != nil && s.ambientDb != nil)
      ? String(format: "%8.1f", s.windowDb! - s.ambientDb!)
      : "       -"
    table += "\nDBG \(String(format: "%5d", k + 1)) \(String(format: "%7.2f", s.endSeconds)) \(amb) \(win) \(delta) \(s.gateOpen ? "  open" : "closed") \(String(format: "%6.3f", s.probability))"
  }
  print(table)
  let hops = scores.count
  let allOpen = scores.allSatisfy { $0.gateOpen }
  let anyWake = scores.contains { $0.wakeWord }
  let hop7and8 = hops >= 8 && scores[6].wakeWord && scores[7].wakeWord
  #expect(hops == 10, "hello clip: \(hops) hops, expected 10")
  #expect(allOpen, "gate closed on some hop")
  #expect(anyWake, "no wake word on the hello clip")
  #expect(hop7and8, "hops 7 and 8 not wake words")
}
