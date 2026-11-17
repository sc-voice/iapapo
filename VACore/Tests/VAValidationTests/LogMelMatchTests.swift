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

/// Compares LogMelFrontEnd with the reference features from
/// scripts/export_frontend_reference.py.
/// Run the export first: lab/wakeword/reference/frontend/ must hold
/// windows.f32, features.f32 and manifest.json.
@Test func logMelMatchesPython() throws {
  // #filePath is VACore/Tests/VACoreTests/LogMelTests.swift; the repo root is
  // four levels up.
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let dir = repo.appendingPathComponent("lab/wakeword/reference/frontend")

  let manifest = try JSONSerialization.jsonObject(
    with: Data(contentsOf: dir
      .appendingPathComponent("manifest.json"))) as? [String: Any]
  let windowCount = try #require(manifest?["windows"] as? Int)
  let windowLen = try #require(manifest?["window_len"] as? Int)
  let frames = try #require(manifest?["frames"] as? Int)
  let nMels = try #require(manifest?["n_mels"] as? Int)
  // The reference features must come from the front end this port was written
  // from.
  #expect(manifest?["frontend_nfhash"] as? String == LogMelFrontEnd.frontendID,
          "reference features are from front end \(manifest?["frontend_nfhash"] ?? "none"), port is \(LogMelFrontEnd.frontendID)")

  let audio = try readFloats(dir.appendingPathComponent("windows.f32"))
  let reference = try readFloats(dir.appendingPathComponent("features.f32"))
  #expect(audio.count == windowCount * windowLen)
  #expect(reference.count == windowCount * nMels * frames)

  let frontEnd = LogMelFrontEnd()
  var maxDiff: Float = 0
  for w in 0 ..< windowCount {
    let window = Array(audio[(w * windowLen) ..< ((w + 1) * windowLen)])
    let (values, gotFrames) = frontEnd.features(window)
    #expect(gotFrames == frames)
    let expected =
      reference[(w * nMels * frames) ..< ((w + 1) * nMels * frames)]
    for (a, b) in zip(values, expected) {
      maxDiff = max(maxDiff, abs(a - b))
    }
  }
  // Both sides are float32. The reference set itself differs from exact float64
  // math by about 7.6e-5
  // (measured in Python), so float32 rounding alone accounts for differences of
  // this size near log = -10.
  #expect(maxDiff < 2e-4, "max |diff| vs Python: \(maxDiff)")
}
