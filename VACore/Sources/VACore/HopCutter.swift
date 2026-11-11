import Foundation

/// Cuts a 16 kHz stream into hops of 4000 samples (0.25 s), the step between wake-word windows.
///
/// Feed it whatever the resampler emits, in any sizes. It holds the leftover samples until a full hop is
/// available. `flush()` returns the leftover as a shorter final hop, unpadded, so the window stage never sees zeros
/// that the input did not contain.
public struct HopCutter: Sendable {
    /// Samples per hop at 16 kHz.
    public static let hopLength = 4000

    /// Samples received but not yet emitted in a hop.
    private var pending: [Float] = []

    public init() {}

    /// Adds samples to the stream.
    /// - Returns: each full hop completed by these samples, in order, possibly none.
    public mutating func process(_ samples: [Float]) -> [[Float]] {
        pending += samples
        var hops: [[Float]] = []
        while pending.count >= Self.hopLength {
            hops.append(Array(pending[0..<Self.hopLength]))
            pending.removeFirst(Self.hopLength)
        }
        return hops
    }

    /// Ends the stream.
    /// - Returns: the leftover samples, fewer than `hopLength`, or empty if none remain.
    public mutating func flush() -> [Float] {
        defer { pending = [] }
        return pending
    }
}
