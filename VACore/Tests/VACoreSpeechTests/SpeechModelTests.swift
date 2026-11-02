import AVFoundation
import Testing
import VACore
@testable import VACoreSpeech

@MainActor
private func makeModel() -> (SpeechModel, () -> [String]) {
    var lines: [String] = []
    let model = SpeechModel(log: { lines.append($0) }, locale: Locale(identifier: "en-US"))
    return (model, { lines })
}

@Test @MainActor func newModelIsEmptyAndUnavailable() {
    let (model, _) = makeModel()
    #expect(model.modelStatus == "—")
    #expect(model.availability == .unavailable)
    #expect(model.transcript == "")
    #expect(model.isDownloading == false)
    #expect(model.downloadError == nil)
    #expect(model.locale.identifier == "en-US")
}

@Test @MainActor func creatingAModelLogsNothing() {
    let (_, lines) = makeModel()
    #expect(lines().isEmpty)
}

@Test func statusStringsMapToEntryStates() {
    #expect(SpeechModel.availability(forStatus: "installed") == .installed)
    #expect(SpeechModel.availability(forStatus: "supported") == .notInstalled)
    #expect(SpeechModel.availability(forStatus: "downloading") == .notInstalled)
    #expect(SpeechModel.availability(forStatus: "unsupported") == .unavailable)
    #expect(SpeechModel.availability(forStatus: "unknown") == .unavailable)
    #expect(SpeechModel.availability(forStatus: "—") == .unavailable)
}

@Test @MainActor func feedBeforeStartIsIgnored() throws {
    let (model, _) = makeModel()
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
    buffer.frameLength = 480
    model.feed(buffer)
    #expect(model.transcript == "")
}

@Test @MainActor func convertResamplesFortyEightKilohertzToSixteen() throws {
    let (model, _) = makeModel()
    let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let converter = try #require(AVAudioConverter(from: source, to: target))

    // The app reuses one converter across buffers, so measure steady state over ten 0.1 s buffers.
    // A single conversion loses about 240 frames to resampler startup, which is why one buffer is not enough.
    var total = 0
    for _ in 0..<10 {
        let input = try #require(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4_800))
        input.frameLength = 4_800
        let output = try #require(model.convert(input, with: converter, to: target))
        #expect(output.format.sampleRate == 16_000)
        total += Int(output.frameLength)
    }
    // One second of audio at 16 kHz is 16000 frames; allow 2% for the one-time startup delay.
    #expect(abs(total - 16_000) <= 320)
}
