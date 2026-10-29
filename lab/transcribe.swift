import Foundation
import Speech

// Usage: swift transcribe.swift <audio file>
// Prints the on-device Apple speech transcription and its alternatives.

guard CommandLine.arguments.count > 1 else {
    print("usage: transcribe.swift <audio file>")
    exit(1)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])

let authSemaphore = DispatchSemaphore(value: 0)
var authStatus = SFSpeechRecognizerAuthorizationStatus.notDetermined
SFSpeechRecognizer.requestAuthorization { status in
    authStatus = status
    authSemaphore.signal()
}
authSemaphore.wait()
guard authStatus == .authorized else {
    print("speech recognition not authorized: \(authStatus.rawValue)")
    exit(1)
}

guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
    print("no recognizer for en-US")
    exit(1)
}
print("on-device available: \(recognizer.supportsOnDeviceRecognition)")

let request = SFSpeechURLRecognitionRequest(url: url)
request.requiresOnDeviceRecognition = false
request.shouldReportPartialResults = false

let done = DispatchSemaphore(value: 0)
recognizer.recognitionTask(with: request) { result, error in
    if let error = error {
        print("error: \(error.localizedDescription)")
        done.signal()
        return
    }
    guard let result = result, result.isFinal else { return }
    print("best: \"\(result.bestTranscription.formattedString)\"")
    for (i, t) in result.transcriptions.enumerated() {
        let conf = t.segments.first.map { String(format: "%.2f", $0.confidence) } ?? "-"
        print("  alt \(i): \"\(t.formattedString)\" (first-segment confidence \(conf))")
    }
    done.signal()
}
done.wait()
