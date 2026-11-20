import Testing
@testable import VACore

private let allAvailable = Availability(microphone: true, speech: .installed)

@Test func microphoneDoesNotBlockEntry() {
  #expect(entryBlock(
    for: .idle,
    availability: Availability(microphone: false, speech: .installed),
  ) == nil)
  #expect(entryBlock(
    for: .idle,
    availability: Availability(microphone: false, speech: .unavailable),
  ) == .speechUnavailable)
}

@Test func unavailableSpeechBlocksWhenMicrophoneIsAvailable() {
  #expect(entryBlock(
    for: .listening,
    availability: Availability(microphone: true, speech: .unavailable),
  )
    == .speechUnavailable)
}

@Test func notInstalledSpeechModelIsItsOwnBlocker() {
  #expect(entryBlock(
    for: .idle,
    availability: Availability(microphone: true, speech: .notInstalled),
  )
    == .speechModelNotInstalled)
}

@Test func listeningStatesAllowedWhenAllAvailable() {
  #expect(entryBlock(for: .idle, availability: allAvailable) == nil)
}

@Test func inactiveIsNeverBlocked() {
  #expect(entryBlock(
    for: .inactive,
    availability: Availability(microphone: false, speech: .unavailable),
  ) == nil)
}

@Test func blockedEntryStaysAndCuesError() {
  let result = transition(to: .idle, from: .inactive,
                          availability: Availability(
                            microphone: true,
                            speech: .unavailable,
                          ))
  #expect(result.step == Step(state: .inactive, notifications: [.requestFailed]))
  #expect(result.block == .speechUnavailable)
}

@Test func missingSpeechModelPlaysAttentionNotError() {
  let result = transition(to: .idle, from: .inactive,
                          availability: Availability(
                            microphone: true,
                            speech: .notInstalled,
                          ))
  #expect(result.step == Step(state: .inactive, notifications: [.attentionNeeded]))
  #expect(result.block == .speechModelNotInstalled)
}

@Test func allowedEntryHasNoBlock() {
  let result = transition(
    to: .idle,
    from: .inactive,
    availability: allAvailable,
  )
  #expect(result.step == Step(state: .idle, notifications: [.idleStarted]))
  #expect(result.block == nil)
}
