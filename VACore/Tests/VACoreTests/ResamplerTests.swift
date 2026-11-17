import Foundation
import Testing
@testable import VACore

/// Runs chunks through Resampler48To16 and returns everything it emits,
/// including the flush.
private func streamed(_ chunks: [[Float]]) -> [Float] {
  var resampler = Resampler48To16()
  var out: [Float] = []
  for chunk in chunks {
    out += resampler.process(chunk)
  }
  out += resampler.flush()
  return out
}

/// Feeds the take clip, chunked by WAVStreamer, through the streaming resampler
/// at several chunk sizes.
/// Each run must equal ArrayResampler48To16 on the whole clip, exactly, since
/// both do the same arithmetic in the same order.
@Test func streamingResamplerMatchesWholeClip() throws {
  // #filePath is VACore/Tests/VACoreTests/ResamplerTests.swift; the repo root
  // is four levels up.
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/positive-Ava_premium_hello.m4a")
  let streamer = try WAVStreamer(url: url)
  let expected = ArrayResampler48To16().resample(streamer.samples)

  for size in [4000, 4096, 977, 1] {
    let got = streamed(streamer.chunks(size: size))
    #expect(
      got.count == expected.count,
      "chunks of \(size): \(got.count) samples, expected \(expected.count)",
    )
    #expect(
      got == expected,
      "chunks of \(size): output differs from the whole-clip result",
    )
  }
}

/// A clip whose length is not a multiple of 3, so the last output sample comes
/// from flush().
@Test func streamingResamplerFlushesPartialTail() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/positive-Ava_premium_hello.m4a")
  let full = try WAVStreamer(url: url)
  let odd = WAVStreamer(
    samples: Array(full.samples.prefix(100_001)),
    sampleRate: full.sampleRate,
  )
  let expected = ArrayResampler48To16().resample(odd.samples)
  #expect(expected.count == 33334)

  for size in [4096, 977, 1] {
    let got = streamed(odd.chunks(size: size))
    #expect(
      got.count == expected.count,
      "chunks of \(size): \(got.count) samples, expected \(expected.count)",
    )
    #expect(
      got == expected,
      "chunks of \(size): output differs from the whole-clip result",
    )
  }
}
