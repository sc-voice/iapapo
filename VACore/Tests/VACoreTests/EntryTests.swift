import Testing
@testable import VACore

private let allAvailable = Availability(microphone: true, speech: .installed)

@Test func microphoneBlocksBeforeSpeech() {
    #expect(entryBlock(for: .idle, availability: Availability(microphone: false, speech: .installed))
        == .microphoneDenied)
    #expect(entryBlock(for: .idle, availability: Availability(microphone: false, speech: .unavailable))
        == .microphoneDenied)
}

@Test func unavailableSpeechBlocksWhenMicrophoneIsAvailable() {
    #expect(entryBlock(for: .listening, availability: Availability(microphone: true, speech: .unavailable))
        == .speechUnavailable)
}

@Test func notInstalledSpeechModelIsItsOwnBlocker() {
    #expect(entryBlock(for: .idle, availability: Availability(microphone: true, speech: .notInstalled))
        == .speechModelNotInstalled)
}

@Test func listeningStatesAllowedWhenAllAvailable() {
    #expect(entryBlock(for: .idle, availability: allAvailable) == nil)
}

@Test func inactiveIsNeverBlocked() {
    #expect(entryBlock(for: .inactive, availability: Availability(microphone: false, speech: .unavailable)) == nil)
}

@Test func blockedEntryStaysAndCuesError() {
    let result = transition(to: .idle, from: .inactive,
                            availability: Availability(microphone: false, speech: .installed))
    #expect(result.step == Step(state: .inactive, effects: [.sound(.error)]))
    #expect(result.block == .microphoneDenied)
}

@Test func missingSpeechModelPlaysAttentionNotError() {
    let result = transition(to: .idle, from: .inactive,
                            availability: Availability(microphone: true, speech: .notInstalled))
    #expect(result.step == Step(state: .inactive, effects: [.sound(.attention)]))
    #expect(result.block == .speechModelNotInstalled)
}

@Test func allowedEntryHasNoBlock() {
    let result = transition(to: .idle, from: .inactive, availability: allAvailable)
    #expect(result.step == Step(state: .idle, effects: [.sound(.idle)]))
    #expect(result.block == nil)
}
