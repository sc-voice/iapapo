import Foundation
import Testing
@testable import VACore

/// WAV → WakeScorer (Resampler48To16 → HopCutter → SlidingWindow → LogMelFrontEnd → Core ML), on the take's first negative clip.
/// The clip's maximum probability must match the PyTorch max_prob in the eval record for this run, within 1e-3.
@Test func scoreFromWAVMatchesPythonEval() async throws {
    // #filePath is VACore/Tests/VACoreTests/ScoreFromWAVTests.swift; the repo root is four levels up.
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let url = repo.appendingPathComponent("lab/wakeword/takes/20261104-075505/negative-001.wav")
    let run = repo.appendingPathComponent("lab/wakeword/out/JNaU8v4L6/no-take-0Q6-ou")

    let scorer = try await WakeScorer.load(runFolder: run)
    let streamer = try WAVStreamer(url: url)
    let (maxProb, scored) = try await scorer.maxProbability(chunks: streamer.chunks(size: 4096))

    let evalURL = run.appendingPathComponent("eval-0Q70Tk.json")
    let eval = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: evalURL)) as? [String: Any])
    let clips = try #require(eval["clips"] as? [[String: Any]])
    let entry = try #require(clips.first { ($0["clip"] as? String) == "negative-001" })
    let expected = Float(try #require(entry["max_prob"] as? Double))

    #expect(scored == 16, "scored \(scored) windows, expected 16")
    #expect(abs(maxProb - expected) < 1e-3, "chain max \(maxProb) vs Python \(expected)")
}
