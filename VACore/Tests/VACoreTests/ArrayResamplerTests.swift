import Foundation
import Testing
@testable import VACore

/// Reads a file of little-endian float32 values.
private func readFloats(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    return data.withUnsafeBytes { raw in
        (0..<(raw.count / 4)).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
    }
}

/// Reads a file of little-endian float64 values.
private func readDoubles(_ url: URL) throws -> [Double] {
    let data = try Data(contentsOf: url)
    return data.withUnsafeBytes { raw in
        (0..<(raw.count / 8)).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: Double.self) }
    }
}

/// Compares ArrayResampler48To16 with scipy's resample_poly on the take clip in lab/wakeword/reference/resample/.
/// Run scripts/python/export_resample_reference.py first.
@Test func arrayResamplerMatchesScipy() throws {
    // #filePath is VACore/Tests/VACoreTests/ResamplerTests.swift; the repo root is four levels up.
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let dir = repo.appendingPathComponent("lab/wakeword/reference/resample")

    let resampler = ArrayResampler48To16()
    let scipyTaps = try readDoubles(dir.appendingPathComponent("taps.f64"))
    #expect(resampler.taps.count == scipyTaps.count)
    var tapDiff = 0.0
    for (a, b) in zip(resampler.taps, scipyTaps) {
        tapDiff = max(tapDiff, abs(a - b))
    }
    #expect(tapDiff < 1e-12, "tap max |diff| vs scipy: \(tapDiff)")

    // "full" is a whole clip; "odd" has a length that is not a multiple of 3, so its last output sample is partial.
    for name in ["full", "odd"] {
        let input = try readFloats(dir.appendingPathComponent("\(name).in.f32"))
        let expected = try readFloats(dir.appendingPathComponent("\(name).out.f32"))
        let output = resampler.resample(input)
        #expect(output.count == expected.count, "\(name): \(output.count) samples, scipy gives \(expected.count)")
        var maxDiff: Float = 0
        for (a, b) in zip(output, expected) {
            maxDiff = max(maxDiff, abs(a - b))
        }
        #expect(maxDiff < 1e-6, "\(name): max |diff| vs scipy: \(maxDiff)")
    }
}
