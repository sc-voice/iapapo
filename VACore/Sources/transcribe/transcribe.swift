import AVFoundation
import Foundation
import VACoreSpeech

/// Transcribes one audio file on the device with `SpeechModel`, the same engine the app uses.
///
/// Usage: transcribe <audio file>
/// Prints each speech log line, then the final transcript and the elapsed time.
@main
@MainActor
struct Transcribe {
    /// Collects log lines from `SpeechModel` so the tool can wait for specific events.
    final class Log {
        var lines: [String] = []
    }

    struct Failure: Error, LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func main() async {
        guard CommandLine.arguments.count > 1 else {
            print("usage: transcribe <audio file>")
            exit(2)
        }
        do {
            try await run(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func run(url: URL) async throws {
        let log = Log()
        let model = SpeechModel(log: { line in
            log.lines.append(line)
            print("speech: \(line)")
        })

        await model.refreshStatus()
        if model.availability != .installed {
            print("speech model is \(model.modelStatus); downloading")
            await model.download()
            if let error = model.downloadError {
                throw Failure("speech model download failed: \(error)")
            }
            guard model.availability == .installed else {
                throw Failure("speech model unavailable: \(model.modelStatus)")
            }
        }

        let file = try AVAudioFile(forReading: url)
        let started = Date()
        model.start()
        try await waitUntilStarted(log: log)

        let chunk: AVAudioFrameCount = 4_096
        let buffer = try require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk))
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            if buffer.frameLength == 0 { break }
            model.feed(buffer)
        }

        await model.finish()
        let seconds = Date().timeIntervalSince(started)
        print("transcript: \"\(model.transcript)\"")
        print(String(format: "elapsed: %.2f s", seconds))
    }

    /// Waits for the analyzer's start log line. Audio fed before then is dropped.
    static func waitUntilStarted(log: Log) async throws {
        for _ in 0..<200 {
            if log.lines.contains("speech started") { return }
            if let failure = log.lines.first(where: { $0.contains("error") }) {
                throw Failure(failure)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure("speech analyzer did not start within 10 s")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure("could not allocate audio buffer") }
        return value
    }
}
