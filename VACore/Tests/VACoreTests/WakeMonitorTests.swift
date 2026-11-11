import Foundation
import Testing
@testable import VACore

/// Streams `Ava_premium_hello.wav` (48 kHz mono) through `WakeMonitor` with the lab model, in chunks of `size`.
private func monitorScores(chunkSize size: Int) async throws -> [WakeScore] {
    // #filePath is VACore/Tests/VACoreTests/WakeMonitorTests.swift; the repo root is four levels up.
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let url = repo.appendingPathComponent("lab/wakeword/monitor/Ava_premium_hello.wav")
    let run = repo.appendingPathComponent("lab/wakeword/out/JNaU8v4L6/no-take-0Q6-ou")

    let scorer = try await WakeScorer.load(runFolder: run)
    let streamer = try WAVStreamer(url: url)
    var monitor = WakeMonitor(scorer: scorer)
    var scores: [WakeScore] = []
    for chunk in streamer.chunks(size: size) {
        scores += try await monitor.process(chunk)
    }
    scores += try await monitor.flush()
    return scores
}

/// Windows a stream of `inputSamples` 48 kHz samples completes, counting the resampler's ceil(n / 3) output.
private func expectedWindows(inputSamples: Int) -> Int {
    let outputSamples = (inputSamples + 2) / 3
    guard outputSamples >= SlidingWindow.length else { return 0 }
    return (outputSamples - SlidingWindow.length) / SlidingWindow.step + 1
}

/// One event per completed window, numbered from 0, spaced 0.25 s apart on the stream clock.
@Test func monitorEmitsOneScorePerWindow() async throws {
    let scores = try await monitorScores(chunkSize: 4096)
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("lab/wakeword/monitor/Ava_premium_hello.wav")
    let samples = try WAVStreamer(url: url).samples.count

    #expect(scores.count == expectedWindows(inputSamples: samples), "scored \(scores.count) windows")
    #expect(scores.count > 0)
    for (k, score) in scores.enumerated() {
        #expect(score.windowIndex == k)
        let expectedEnd = Double(SlidingWindow.step * k + SlidingWindow.length) / 16_000
        #expect(abs(score.endSeconds - expectedEnd) < 1e-9)
    }
}

/// The same audio gives the same scores however it is chunked, as a microphone's buffer sizes vary.
@Test func monitorScoresAreChunkSizeIndependent() async throws {
    let reference = try await monitorScores(chunkSize: 4096)
    for size in [977, 1] {
        let scores = try await monitorScores(chunkSize: size)
        #expect(scores == reference, "chunk size \(size) differs from chunk size 4096")
    }
}

/// Shape check on `Ava_premium_hello.wav` with the lab model. Window 3 (ends at 1.643 s) must score above 0.9, and every
/// Typical scores: 0, 0, 0, 1, 0.27, 0, 0, 0
@Test func monitorScoreCurveHasOnePeak() async throws {
    let scores = try await monitorScores(chunkSize: 4096)
    for score in scores {
        if score.windowIndex == 3 {
            #expect(score.probability > 0.9, "window 3 scored \(score.probability), expected above 0.9")
        } else {
            #expect(score.probability < 0.3, "window \(score.windowIndex) scored \(score.probability), expected below 0.3")
        }
    }
}
