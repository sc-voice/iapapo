import Foundation
import Testing
@testable import VACore

/// Complete windows in `count` 16 kHz samples at `step` spacing.
private func completeWindows(_ count: Int, step: Int) -> Int {
  count < testWindowLength
    ? 0 : (count - testWindowLength) / step + 1
}

/// Scores `Ava_premium_hello.m4a` through the full chain at one hop size. Each
/// 48 kHz input chunk is 3 × `step` samples, so the resampler emits one hop's
/// worth of 16 kHz samples per chunk: chunk size equals hop size.
/// - Returns: the number of windows scored, and the highest probability.
private func scoreAtHop(_ step: Int) async throws
  -> (windows: Int, maxProb: Float, perWindowMs: Double, totalMs: Double)
{
  // #filePath is VACore/Tests/VACoreTests/ProductionHopTests.swift; the repo
  // root is four levels up.
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/Ava_premium_hello.m4a")
  let scorer = try WakeScorer.loadBundled()
  let streamer = try WAVStreamer(url: url)

  let clock = ContinuousClock()
  let wallStart = clock.now
  var resampler = Resampler48To16()
  var cutter = HopCutter(hopLength: step)
  var window = SlidingWindow(length: testWindowLength, step: step)
  var windows: [[Float]] = []
  for chunk in streamer.chunks(size: 3 * step) {
    for hop in cutter.process(resampler.process(chunk)) {
      windows += window.process(hop)
    }
  }
  for hop in cutter.process(resampler.flush()) {
    windows += window.process(hop)
  }
  windows += window.process(cutter.flush())

  let expected = completeWindows(
    ArrayResampler48To16().resample(streamer.samples).count,
    step: step,
  )
  #expect(
    windows.count == expected,
    "step \(step): scored \(windows.count) windows, expected \(expected)",
  )
  #expect(windows.allSatisfy { $0.count == testWindowLength })

  var maxProb: Float = 0
  var inference = Duration.zero
  var bins = [Int](repeating: 0, count: 5)
  var binOf: [Int] = []
  for samples in windows {
    let started = clock.now
    let p = try await scorer.probability(of: samples)
    inference += clock.now - started
    #expect(p >= 0 && p <= 1, "step \(step): probability \(p) outside [0, 1]")
    maxProb = max(maxProb, p)
    let bin = min(4, max(0, Int(p * 5)))
    bins[bin] += 1
    binOf.append(bin)
  }
  // A run is a maximal block of consecutive window indices in one bin.
  var runs = [Int](repeating: 0, count: 5)
  for k in binOf.indices where k == 0 || binOf[k - 1] != binOf[k] {
    runs[binOf[k]] += 1
  }
  let summary = (0 ..< 5).map { "\(bins[$0])@\(runs[$0])" }
  print("step \(step) windows@runs, bins 0.0–0.2 … 0.8–1.0: \(summary)")
  let perWindowMs = windows.isEmpty ? 0 :
    Double(inference.components.attoseconds) / 1e15 / Double(windows.count)
    + Double(inference.components.seconds) * 1000 / Double(windows.count)
  let totalMs = Double((clock.now - wallStart).components.seconds) * 1000
    + Double((clock.now - wallStart).components.attoseconds) / 1e15
  print("step \(step) total \(String(format: "%.1f", totalMs)) ms")
  return (windows.count, maxProb, perWindowMs, totalMs)
}

/// Production hop experiments. Run in release, for example:
/// `swift test -c release --package-path VACore --filter productionHop`
/// Hops of 1600 (0.1 s, production) and other steps are checked for window
/// count and output range. There is no Python reference at these steps.
@Test(arguments: [1600, 1440, 1280, 1120, 960, 800, 4000])
func productionHopScoresEveryWindow(step: Int) async throws {
  let result = try await scoreAtHop(step)
  print("step \(step) (\(Double(step) / 16000) s): \(result.windows) windows, "
    + "max \(result.maxProb), inference \(String(format: "%.2f", result.perWindowMs)) ms/window")
}
