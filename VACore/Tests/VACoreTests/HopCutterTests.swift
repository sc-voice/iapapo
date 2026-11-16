import Foundation
import Testing
@testable import VACore

/// Cuts a stream in the given chunk sizes and returns every hop, including the
/// shorter final hop.
private func cut(_ chunks: [[Float]]) -> [[Float]] {
  var cutter = HopCutter()
  var hops: [[Float]] = []
  for chunk in chunks {
    hops += cutter.process(chunk)
  }
  let tail = cutter.flush()
  if !tail.isEmpty {
    hops.append(tail)
  }
  return hops
}

/// Splits `x` into consecutive chunks of `size`. The last chunk may be shorter.
private func split(_ x: [Float], size: Int) -> [[Float]] {
  stride(from: 0, to: x.count, by: size).map { Array(x[$0 ..< min(
    $0 + size,
    x.count,
  )]) }
}

/// Synthetic stream: 10001 samples, counting up, cut in chunks of 3000. The
/// final hop holds the 2001 leftover samples, unpadded.
@Test func hopCutterLeavesTheFinalHopShort() {
  let x = (0 ..< 10001).map { Float($0) }
  let hops = cut(split(x, size: 3000))
  #expect(hops.map(\.count) == [4000, 4000, 2001])
  #expect(hops.flatMap(\.self) == x)
}

/// The take through WAVStreamer, then the streaming resampler, then the hop
/// cutter. Every hop but the last is 4000 samples,
/// and the hops glued together are exactly the whole-clip resampler output,
/// with no padding.
@Test func hopCutterHopsGlueToWholeClipResampler() throws {
  // #filePath is VACore/Tests/VACoreTests/HopCutterTests.swift; the repo root
  // is four levels up.
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("media/iapapo/holdout/Ava_premium_hello.m4a")
  let streamer = try WAVStreamer(url: url)
  let expected = ArrayResampler48To16().resample(streamer.samples)

  for size in [4000, 4096, 977, 1] {
    var resampler = Resampler48To16()
    var cutter = HopCutter()
    var hops: [[Float]] = []
    for chunk in streamer.chunks(size: size) {
      hops += cutter.process(resampler.process(chunk))
    }
    hops += cutter.process(resampler.flush())
    let tail = cutter.flush()
    if !tail.isEmpty {
      hops.append(tail)
    }

    #expect(
      hops.dropLast().allSatisfy { $0.count == HopCutter.hopLength },
      "chunks of \(size): a hop before the last is not full",
    )
    #expect(
      hops.flatMap(\.self) == expected,
      "chunks of \(size): hops do not glue to the whole-clip resampler output",
    )
  }
}
