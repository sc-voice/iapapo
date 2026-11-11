import Foundation
import Testing
@testable import VACore

/// Checks WAVStreamer against the take clip the resampler reference was made from.
@Test func wavStreamerChunksReassembleToTheFile() throws {
    // #filePath is VACore/Tests/VACoreTests/WAVStreamerTests.swift; the repo root is four levels up.
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let url = repo.appendingPathComponent("lab/wakeword/takes/20261104-075505/negative-001.wav")

    let streamer = try WAVStreamer(url: url)
    #expect(streamer.sampleRate == 48000)
    #expect(streamer.samples.count == 225600)

    // Chunk sizes that divide the length, do not divide it, and are a single sample.
    for size in [4000, 977, 1] {
        let chunks = streamer.chunks(size: size)
        #expect(chunks.dropLast().allSatisfy { $0.count == size }, "size \(size): only the last chunk may be short")
        #expect(chunks.flatMap { $0 } == streamer.samples, "size \(size): chunks do not reassemble to the file")
    }
}
