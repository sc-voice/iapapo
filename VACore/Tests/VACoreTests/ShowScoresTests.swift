import Foundation
import Testing
@testable import VACore

/// Prints the Swift chain's max probability per clip beside the Python eval max_prob, for each held-out take.
/// Each take is paired with the untrimmed eval record that scripts/python/eval_take.py wrote for it.
/// Run with: swift test --package-path VACore --filter showSwiftScores
@Test func showSwiftScores() async throws {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let run = repo.appendingPathComponent("lab/wakeword/out/JNaU8v4L6/no-take-0Q6-ou")
    let takes: [(take: String, eval: String)] = [
        ("20261102-082403", "eval-0Q75u4Y.json"),
        ("20261103-163155", "eval-0Q75u4t.json"),
        ("20261104-075505", "eval-0Q75tps.json"),
    ]

    let scorer = try await WakeScorer.load(runFolder: run)
    let started = Date()

    for (takeName, evalName) in takes {
        let takeDir = repo.appendingPathComponent("lab/wakeword/takes/\(takeName)")
        let eval = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: run.appendingPathComponent(evalName))) as? [String: Any])
        let pyClips = try #require(eval["clips"] as? [[String: Any]])
        var pyMax: [String: Double] = [:]
        for c in pyClips {
            if let name = c["clip"] as? String, let m = c["max_prob"] as? Double { pyMax[name] = m }
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: takeDir.path)
            .filter { $0.hasSuffix(".wav") }.sorted()
        for file in files {
            let name = (file as NSString).deletingPathExtension
            let streamer = try WAVStreamer(url: takeDir.appendingPathComponent(file))
            let (maxProb, windows) = try await scorer.maxProbability(chunks: streamer.chunks(size: 4096))
            let py = pyMax[name].map { String(format: "%.4f", $0) } ?? "none"
            print("SCORE \(takeName) \(name) windows \(windows) swift \(String(format: "%.4f", maxProb)) python \(py)")
        }
    }
    print("SCORING SECONDS \(String(format: "%.3f", Date().timeIntervalSince(started)))")
}
