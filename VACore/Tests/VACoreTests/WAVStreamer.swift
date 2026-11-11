import AVFoundation
import Foundation

/// Test helper: reads a mono WAV and hands its samples out in chunks of a chosen size,
/// the way a microphone delivers buffers. The chunk size is the variable under test.
struct WAVStreamer {
    /// The file's samples as Float32, channel 0.
    let samples: [Float]
    /// The file's sample rate in Hz.
    let sampleRate: Double

    /// Reads the whole file. Throws if the file cannot be read or has more than one channel.
    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.channelCount == 1 else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        // A single read can return fewer frames than the file holds, so read in blocks until the end.
        let blockFrames: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames),
              let channel = buffer.floatChannelData?[0] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var all: [Float] = []
        all.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: blockFrames)
            if buffer.frameLength == 0 { break }
            all.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        samples = all
        sampleRate = format.sampleRate
    }

    /// Wraps samples already in memory, for a clip cut from a file, such as a prefix.
    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// The samples in consecutive chunks of `size`. The last chunk may be shorter.
    /// - Parameter size: samples per chunk, at least 1.
    func chunks(size: Int) -> [[Float]] {
        precondition(size >= 1, "chunk size must be at least 1")
        return stride(from: 0, to: samples.count, by: size).map {
            Array(samples[$0..<min($0 + size, samples.count)])
        }
    }
}
