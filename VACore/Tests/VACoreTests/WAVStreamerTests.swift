import Foundation
import Testing
@testable import VACore

/// Checks WAVStreamer on the tracked 48 kHz hello clip, which it reads as AAC.
@Test func wavStreamerChunksReassembleToTheFile() throws {
  // #filePath is VACore/Tests/VACoreTests/WAVStreamerTests.swift; the repo root
  // is four levels up.
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/positive-Ava_premium_hello.m4a")

  let streamer = try WAVStreamer(url: url)
  #expect(streamer.sampleRate == 48000)
  #expect(!streamer.samples.isEmpty)

  // Chunk sizes that divide the length, do not divide it, and are a single
  // sample.
  for size in [4000, 977, 1] {
    let chunks = streamer.chunks(size: size)
    #expect(
      chunks.dropLast().allSatisfy { $0.count == size },
      "size \(size): only the last chunk may be short",
    )
    #expect(
      chunks.flatMap(\.self) == streamer.samples,
      "size \(size): chunks do not reassemble to the file",
    )
  }
}
