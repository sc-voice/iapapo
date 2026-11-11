import CoreML
import Foundation
import Testing
@testable import VACore

/// Reads a file of little-endian float32 values.
private func readWakeFloats(_ url: URL) throws -> [Float] {
  let data = try Data(contentsOf: url)
  return data.withUnsafeBytes { raw in
    (0 ..< (raw.count / 4)).map { raw.loadUnaligned(
      fromByteOffset: $0 * 4,
      as: Float.self,
    ) }
  }
}

/// Scores the windows of the 20261104 take through LogMelFrontEnd and the
/// exported Core ML model, then compares
/// each clip's max probability with the PyTorch score recorded in
/// eval-0Q70Tk.json.
/// Needs lab/wakeword/reference/frontend/
/// (scripts/python/export_frontend_reference.py) and the run's
/// wakenet.mlpackage.
@Test func wakeScoresMatchPythonEval() async throws {
  // #filePath is VACore/Tests/VACoreTests/WakeScoreTests.swift; the repo root
  // is four levels up.
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let dir = repo.appendingPathComponent("lab/wakeword/reference/frontend")
  let run = repo
    .appendingPathComponent("lab/wakeword/out/JNaU8v4L6/no-take-0Q6-ou")

  let manifest = try JSONSerialization.jsonObject(
    with: Data(contentsOf: dir
      .appendingPathComponent("manifest.json"))) as? [String: Any]
  let windowCount = try #require(manifest?["windows"] as? Int)
  let windowLen = try #require(manifest?["window_len"] as? Int)
  let nMels = try #require(manifest?["n_mels"] as? Int)
  let frames = try #require(manifest?["frames"] as? Int)
  let windowClips = try #require(manifest?["window_clip"] as? [String])
  #expect(windowClips.count == windowCount)

  let audio = try readWakeFloats(dir.appendingPathComponent("windows.f32"))
  #expect(audio.count == windowCount * windowLen)

  let compiled = try await MLModel
    .compileModel(at: run.appendingPathComponent("wakenet.mlpackage"))
  let model = try MLModel(contentsOf: compiled)
  let frontEnd = LogMelFrontEnd()

  var maxProb: [String: Float] = [:]
  for w in 0 ..< windowCount {
    let window = Array(audio[(w * windowLen) ..< ((w + 1) * windowLen)])
    let (values, gotFrames) = frontEnd.features(window)
    #expect(gotFrames == frames)

    let input = try MLMultiArray(
      shape: [1, 1, NSNumber(value: nMels), NSNumber(value: frames)],
      dataType: .float32,
    )
    let ptr = input.dataPointer.bindMemory(
      to: Float.self,
      capacity: values.count,
    )
    values.withUnsafeBufferPointer { buf in
      ptr.update(from: buf.baseAddress!, count: values.count)
    }
    let provider =
      try MLDictionaryFeatureProvider(
        dictionary: ["logmel": MLFeatureValue(multiArray: input)],
      )
    let out = try await model.prediction(from: provider)
    let prob = try #require(out.featureValue(for: "prob")?.multiArrayValue)
    let p = prob[0].floatValue

    let clip = windowClips[w]
    maxProb[clip] = max(maxProb[clip] ?? 0, p)
  }

  // The PyTorch per-clip max scores from the eval record for this take.
  let evalURL = run.appendingPathComponent("eval-0Q70Tk.json")
  let eval = try #require(try JSONSerialization
    .jsonObject(with: Data(contentsOf: evalURL)) as? [String: Any])
  let clips = try #require(eval["clips"] as? [[String: Any]])
  #expect(clips.count == maxProb.count)

  // Core ML and PyTorch agree to about 1e-6 on this take (see
  // test_coreml_match.py), so 1e-3 is the same tolerance.
  for clip in clips {
    let name = try #require(clip["clip"] as? String)
    let expected = try Float(#require(clip["max_prob"] as? Double))
    let got = try #require(maxProb[name])
    #expect(
      abs(got - expected) < 1e-3,
      "\(name): Swift \(got) vs Python \(expected)",
    )
  }
}
