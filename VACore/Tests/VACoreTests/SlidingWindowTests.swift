import Foundation
import Testing
@testable import VACore

/// Splits `x` into consecutive chunks of `size`. The last chunk may be shorter.
private func split(_ x: [Float], size: Int) -> [[Float]] {
    stride(from: 0, to: x.count, by: size).map { Array(x[$0..<min($0 + size, x.count)]) }
}

/// Number of complete windows in a stream of `count` samples.
private func completeWindows(_ count: Int) -> Int {
    count < SlidingWindow.length ? 0 : (count - SlidingWindow.length) / SlidingWindow.step + 1
}

/// Window k must be samples [4000k, 4000k + 14287) of the stream, for every complete window and no others.
private func checkWindows(_ windows: [[Float]], of stream: [Float], label: String) {
    #expect(windows.count == completeWindows(stream.count), "\(label): \(windows.count) windows, expected \(completeWindows(stream.count))")
    for (k, window) in windows.enumerated() {
        let start = SlidingWindow.step * k
        #expect(window.count == SlidingWindow.length, "\(label): window \(k) has \(window.count) samples")
        #expect(window == Array(stream[start..<(start + SlidingWindow.length)]), "\(label): window \(k) is not at 4000k")
    }
}

/// The take's 16 kHz output, fed to SlidingWindow in several chunk sizes. Windows must sit on the training grid.
@Test func slidingWindowCutsTrainingGrid() throws {
    // #filePath is VACore/Tests/VACoreTests/SlidingWindowTests.swift; the repo root is four levels up.
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let url = repo.appendingPathComponent("media/iapapo/Ava_premium_hello.m4a")
    let streamer = try WAVStreamer(url: url)
    let stream = ArrayResampler48To16().resample(streamer.samples)
    #expect(completeWindows(stream.count) == 8)

    for size in [4000, 977, 1, 4096] {
        var window = SlidingWindow()
        var windows: [[Float]] = []
        for chunk in split(stream, size: size) {
            windows += window.process(chunk)
        }
        checkWindows(windows, of: stream, label: "chunks of \(size)")
    }
}

/// The full chain: WAVStreamer, Resampler48To16, HopCutter, SlidingWindow. Windows must sit on the same grid,
/// measured on the zero-padded hop stream.
@Test func slidingWindowAfterHopCutterKeepsTrainingGrid() throws {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let url = repo.appendingPathComponent("media/iapapo/Ava_premium_hello.m4a")
    let streamer = try WAVStreamer(url: url)

    var resampler = Resampler48To16()
    var cutter = HopCutter()
    var window = SlidingWindow()
    var glued: [Float] = []
    var windows: [[Float]] = []
    for chunk in streamer.chunks(size: 4096) {
        for hop in cutter.process(resampler.process(chunk)) {
            glued += hop
            windows += window.process(hop)
        }
    }
    for hop in cutter.process(resampler.flush()) {
        glued += hop
        windows += window.process(hop)
    }
    let tail = cutter.flush()
    glued += tail
    windows += window.process(tail)

    checkWindows(windows, of: glued, label: "hop chain")
}
