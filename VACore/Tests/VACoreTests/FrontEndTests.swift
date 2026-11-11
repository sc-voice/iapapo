import Foundation
import Testing
@testable import VACore

/// Reads a file of little-endian float32 values.
private func readFloats(_ url: URL) throws -> [Float] {
  let data = try Data(contentsOf: url)
  return data.withUnsafeBytes { raw in
    (0 ..< (raw.count / 4)).map { raw.loadUnaligned(
      fromByteOffset: $0 * 4,
      as: Float.self,
    ) }
  }
}

/// WAV → Resampler48To16 → HopCutter → SlidingWindow → LogMelFrontEnd, on the
/// take's first negative clip.
/// The windows and log-mel features must match the frontend reference that
/// scripts/python/export_frontend_reference.py
/// wrote from train.load_clip. Negatives are not trimmed, so that clip's
/// windows are the reference's first rows.
@Test func frontEndFromWAVMatchesPython() throws {
  // #filePath is VACore/Tests/VACoreTests/FrontEndTests.swift; the repo root is
  // four levels up.
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo
    .appendingPathComponent(
      "lab/wakeword/takes/20261104-075505/negative-001.wav",
    )
  let dir = repo.appendingPathComponent("lab/wakeword/reference/frontend")

  let manifest = try JSONSerialization.jsonObject(
    with: Data(contentsOf: dir
      .appendingPathComponent("manifest.json"))) as? [String: Any]
  let clips = try #require(manifest?["window_clip"] as? [String])
  let frames = try #require(manifest?["frames"] as? Int)
  let nMels = try #require(manifest?["n_mels"] as? Int)
  let windowLen = try #require(manifest?["window_len"] as? Int)
  #expect(windowLen == SlidingWindow.length)
  let clipWindows = clips.prefix { $0 == "negative-001" }.count

  let audio = try readFloats(dir.appendingPathComponent("windows.f32"))
  let reference = try readFloats(dir.appendingPathComponent("features.f32"))

  let streamer = try WAVStreamer(url: url)
  var resampler = Resampler48To16()
  var cutter = HopCutter()
  var window = SlidingWindow()
  var windows: [[Float]] = []
  for chunk in streamer.chunks(size: 4096) {
    for hop in cutter.process(resampler.process(chunk)) {
      windows += window.process(hop)
    }
  }
  for hop in cutter.process(resampler.flush()) {
    windows += window.process(hop)
  }
  windows += window.process(cutter.flush())

  #expect(
    windows.count == clipWindows,
    "chain made \(windows.count) windows, reference has \(clipWindows) for this clip",
  )
  let frontEnd = LogMelFrontEnd()
  var windowDiff: Float = 0
  var featureDiff: Float = 0
  for (k, w) in windows.prefix(clipWindows).enumerated() {
    let expectedAudio = audio[(k * windowLen) ..< ((k + 1) * windowLen)]
    for (a, b) in zip(w, expectedAudio) {
      windowDiff = max(windowDiff, abs(a - b))
    }
    let (values, gotFrames) = frontEnd.features(w)
    #expect(gotFrames == frames)
    let expected =
      reference[(k * nMels * frames) ..< ((k + 1) * nMels * frames)]
    for (a, b) in zip(values, expected) {
      featureDiff = max(featureDiff, abs(a - b))
    }
  }
  #expect(windowDiff < 1e-6, "max |window diff| vs Python: \(windowDiff)")
  // Same tolerance as logMelMatchesPython: float32 rounding near log = -10.
  #expect(featureDiff < 2e-4, "max |feature diff| vs Python: \(featureDiff)")
}
